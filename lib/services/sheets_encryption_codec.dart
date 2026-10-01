import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'dataset_key_service.dart';

/// Wire-only encryption. Domain maps, SQLite, and sync fingerprints stay plaintext.
class SheetsEncryptionCodec {
  SheetsEncryptionCodec(this.keys);
  final DatasetKeyService keys;
  static final _cipher = AesGcm.with256bits();
  static const protectedFields = <String, List<String>>{
    'LEARNERS': [
      'LearnerReferenceNumber',
      'LastName',
      'FirstName',
      'MiddleName',
      'Sex',
      'BirthDate',
      'Age',
      'PersonalContactNumber',
      'RegionCode',
      'Region',
      'ProvinceCode',
      'Province',
      'CityMunicipalityCode',
      'TownMunicipality',
      'BarangayCode',
      'Barangay',
      'Purok',
      'Street',
      'HouseNo',
      'Parents',
      'Guardian',
      'RelationshipToGuardian',
      'ParentsContactNumber',
      'NotesDetails'
    ],
    'TEACHERS': ['TeacherName', 'MobileNumber', 'Status'],
    'SECTIONS': ['SchoolYear', 'GradeLevel', 'SectionName', 'Adviser'],
    'SCHOOL_HISTORY': [
      'SchoolYear',
      'Grade',
      'School',
      'Section',
      'Adviser',
      'NotesDetails'
    ],
    'INCIDENTS': [
      'IncidentDate',
      'IncidentTime',
      'Observer',
      'BehaviorProblem',
      'ObservationDetails',
      'Intervention',
      'ActionTaken',
      'Remarks',
      'Details'
    ],
  };

  List<String> _fields(String table) =>
      protectedFields[table] ??
      (throw const DataSecurityException('Unsupported encrypted table.'));

  List<int> _aad(
      DatasetKey key, String table, String column, Map<String, Object?> row) {
    final syncId = row['SyncID']?.toString().trim() ?? '';
    final parent = row['LearnerSyncID']?.toString().trim() ?? '';
    final deleted = int.tryParse(row['Deleted']?.toString() ?? '');
    if (syncId.isEmpty ||
        deleted == null ||
        deleted < 0 ||
        deleted > 2 ||
        ((table == 'SCHOOL_HISTORY' || table == 'INCIDENTS') &&
            parent.isEmpty)) {
      throw const DataSecurityException(
          'Invalid encrypted record identity or lifecycle metadata.');
    }
    return utf8.encode(jsonEncode([
      'holistic-fields-v1',
      key.id,
      key.datasetId,
      table,
      column,
      syncId,
      parent,
      deleted
    ]));
  }

  Future<Map<String, Object?>> encode(String table, Map<String, Object?> row,
      {DatasetKey? key}) async {
    final installed = key ?? await keys.requireKey();
    final result = Map<String, Object?>.of(row);
    for (final column in _fields(table)) {
      final value = row[column];
      if (value is String && value.startsWith('ENC:')) {
        // Only an authenticated envelope in this exact context is idempotent.
        await _decrypt(installed, table, column, row, value);
        continue;
      }
      if (value != null && value is! String && value is! int) {
        throw const DataSecurityException('Unsupported protected value type.');
      }
      final box = await _cipher.encrypt(utf8.encode(jsonEncode(value)),
          secretKey: installed.secret,
          nonce: securityRandomBytes(12),
          aad: _aad(installed, table, column, row));
      final envelope = 'ENC:v1:${installed.id}:${base64UrlEncode([
            ...box.nonce,
            ...box.cipherText,
            ...box.mac.bytes
          ])}';
      if (envelope.length > 50000) {
        throw const DataSecurityException(
            'An encrypted value exceeds the Google Sheets cell limit. Shorten the value before synchronizing.');
      }
      result[column] = envelope;
    }
    return result;
  }

  Future<Object?> _decrypt(DatasetKey key, String table, String column,
      Map<String, Object?> row, Object? value) async {
    if (value is! String || !value.startsWith('ENC:')) {
      throw const DataSecurityException(
          'Unencrypted or missing protected cloud value. Version 1 requires a fresh encrypted dataset; legacy migration is not supported.');
    }
    try {
      final parts = value.split(':');
      if (value.length > 50000 ||
          parts.length != 4 ||
          parts[0] != 'ENC' ||
          parts[1] != 'v1' ||
          parts[2] != key.id ||
          !RegExp(r'^[A-Za-z0-9_-]+={0,2}$').hasMatch(parts[3])) {
        throw const FormatException();
      }
      final bytes = base64Url.decode(parts[3]);
      if (bytes.length < 29) throw const FormatException();
      final plaintext = await _cipher.decrypt(
          SecretBox(bytes.sublist(12, bytes.length - 16),
              nonce: bytes.sublist(0, 12),
              mac: Mac(bytes.sublist(bytes.length - 16))),
          secretKey: key.secret,
          aad: _aad(key, table, column, row));
      final result = jsonDecode(utf8.decode(plaintext));
      if (result != null && result is! String && result is! int) {
        throw const FormatException();
      }
      return result;
    } catch (_) {
      throw const DataSecurityException(
          'A cloud value could not be authenticated. Check the recovery key or restore an intact encrypted cloud copy. No plaintext fallback is allowed.');
    }
  }

  Future<Map<String, Object?>> decode(String table, Map<String, Object?> row,
      {DatasetKey? key}) async {
    final installed = key ?? await keys.requireKey();
    final result = Map<String, Object?>.of(row);
    for (final column in _fields(table)) {
      result[column] =
          await _decrypt(installed, table, column, row, row[column]);
    }
    return result;
  }

  Future<List<Map<String, Object?>>> decodeRows(
      String table, List<Map<String, Object?>> rows) async {
    final key = await keys.requireKey(); // Even an empty dataset needs a key.
    final result = <Map<String, Object?>>[];
    for (final row in rows) {
      result.add(await decode(table, row, key: key));
    }
    return result;
  }
}
