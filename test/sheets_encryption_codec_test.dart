import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holistic_anecdotal_records/models/sync_record_state.dart';
import 'package:holistic_anecdotal_records/services/dataset_key_service.dart';
import 'package:holistic_anecdotal_records/services/sheets_encryption_codec.dart';
import 'package:holistic_anecdotal_records/services/sync_context_service.dart';
import 'support/encrypted_sheets_fixture.dart';

void main() {
  late MemoryKeyStore store;
  late DatasetKeyService keys;
  late SheetsEncryptionCodec codec;
  final metadata = <String, Object?>{
    'SyncID': 'synthetic-row',
    'LearnerSyncID': 'parent',
    'CreatedAt': '2026-09-01',
    'UpdatedAt': '2026-09-02',
    'DeviceID': 'test',
    'Version': 1,
    'Deleted': 0
  };
  setUp(() async {
    store = MemoryKeyStore();
    keys = DatasetKeyService(
        store: store,
        context: SyncContextService(
            database: () => throw StateError('No database allowed')));
    await keys.setUp();
    codec = SheetsEncryptionCodec(keys);
  });
  final securityError = isA<DataSecurityException>();

  test('AES-256-GCM NIST zero-key known answer', () async {
    final box = await AesGcm.with256bits().encrypt(List.filled(16, 0),
        secretKey: SecretKey(List.filled(32, 0)), nonce: List.filled(12, 0));
    String hex(List<int> v) =>
        v.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    expect(hex(box.cipherText), 'cea7403d4d606b6e074ec5d3baf39d18');
    expect(hex(box.mac.bytes), 'd0d1c8a799996bf0265b98b5d48ab919');
  });

  for (final table in EncryptedMemorySheets.headers.keys) {
    test(
        '$table exact field policy, metadata, randomized round trip and idempotence',
        () async {
      final fields = SheetsEncryptionCodec.protectedFields[table]!;
      final original = <String, Object?>{
        for (final c in EncryptedMemorySheets.headers[table]!)
          c: fields.contains(c)
              ? 'Ñ test $c'
              : c.endsWith('ID')
                  ? 71
                  : metadata[c],
        ...metadata
      };
      // Only columns actually belonging to the table.
      original.removeWhere(
          (k, _) => !EncryptedMemorySheets.headers[table]!.contains(k));
      final first = await codec.encode(table, original);
      final second = await codec.encode(table, original);
      for (final column in original.keys) {
        if (fields.contains(column)) {
          expect(first[column], startsWith('ENC:v1:'));
          expect(first[column], isNot(second[column]));
        } else {
          expect(first[column], original[column]);
        }
      }
      expect(await codec.decode(table, first), original);
      expect(await codec.decode(table, second), original);
      expect(await codec.encode(table, first), first);
      expect(
          SyncRecordState.same(await codec.decode(table, first),
              await codec.decode(table, second)),
          isTrue);
    });
  }

  test('policy is exactly every domain column, not technical metadata', () {
    const technical = {
      'SyncID',
      'LearnerID',
      'TeacherID',
      'SectionID',
      'SchoolHistoryID',
      'IncidentID',
      'LearnerSyncID',
      'CreatedAt',
      'UpdatedAt',
      'DeviceID',
      'Version',
      'Deleted'
    };
    for (final table in EncryptedMemorySheets.headers.keys) {
      expect(
          SheetsEncryptionCodec.protectedFields[table]!.toSet(),
          EncryptedMemorySheets.headers[table]!
              .where((c) => !technical.contains(c))
              .toSet());
    }
  });

  for (final value in <Object?>[
    null,
    '',
    '   ',
    13,
    '001230',
    '2026-09-26',
    "Ma. Niño Dela-Peña O'Neil",
    'n\u0303',
    'Una\nIkalawa\r\n🙂'
  ]) {
    test('typed value ${jsonEncode(value)} survives exactly', () async {
      final row = {...metadata, 'NotesDetails': value};
      final encrypted = await codec.encode('LEARNERS', row);
      expect(
          (await codec.decode('LEARNERS', encrypted))['NotesDetails'], value);
    });
  }

  test('wrong key with same ID and unknown ID fail', () async {
    final row =
        await codec.encode('TEACHERS', {...metadata, 'TeacherName': 'Private'});
    final key = await keys.requireKey();
    store.value = DatasetKey(
            id: key.id,
            datasetId: key.datasetId,
            bytes: securityRandomBytes(32))
        .encode();
    await expectLater(codec.decode('TEACHERS', row), throwsA(securityError));
    store.value = null;
    await keys.setUp();
    await expectLater(codec.decode('TEACHERS', row), throwsA(securityError));
  });

  for (final part in ['nonce', 'ciphertext', 'tag']) {
    test('modified $part fails authentication', () async {
      final row = await codec.encode('TEACHERS', metadata);
      final chunks = (row['TeacherName'] as String).split(':');
      final bytes = base64Url.decode(chunks[3]);
      final index = part == 'nonce'
          ? 0
          : part == 'tag'
              ? bytes.length - 1
              : 12;
      bytes[index] ^= 1;
      row['TeacherName'] =
          '${chunks.take(3).join(':')}:${base64UrlEncode(bytes)}';
      await expectLater(codec.decode('TEACHERS', row), throwsA(securityError));
    });
  }

  for (final bad in <Object?>[
    null,
    '',
    'legacy plaintext',
    'ENC:',
    'ENC:v2:x:AAAA',
    'ENC:v1:x:%%%%'
  ]) {
    test('cleared/legacy/malformed/unsupported input $bad fails closed',
        () async {
      final row = await codec.encode('TEACHERS', metadata);
      row['TeacherName'] = bad;
      await expectLater(codec.decode('TEACHERS', row), throwsA(securityError));
    });
  }

  test('context binds row, column, table, parent, dataset and lifecycle',
      () async {
    final row = await codec.encode('SCHOOL_HISTORY', metadata);
    for (final edit in [
      {'SyncID': 'another'},
      {'LearnerSyncID': 'another'},
      {'Deleted': 1},
      {'School': row['Adviser']}
    ]) {
      await expectLater(codec.decode('SCHOOL_HISTORY', {...row, ...edit}),
          throwsA(securityError));
    }
    await expectLater(codec.decode('SECTIONS', row), throwsA(securityError));
    final key = await keys.requireKey();
    store.value =
        DatasetKey(id: key.id, datasetId: 'f' * 32, bytes: key.bytes).encode();
    await expectLater(
        codec.decode('SCHOOL_HISTORY', row), throwsA(securityError));
  });

  test(
      'local numeric IDs and canonical Sheets Deleted string do not prevent decryption',
      () async {
    final row =
        await codec.encode('SCHOOL_HISTORY', {...metadata, 'LearnerID': 1});
    final result = await codec
        .decode('SCHOOL_HISTORY', {...row, 'LearnerID': 999, 'Deleted': '0'});
    expect(result['LearnerID'], 999);
  });

  test(
      'missing/failed secure storage blocks even empty downloads, never creates a key',
      () async {
    store.value = null;
    await expectLater(codec.decodeRows('TEACHERS', []), throwsA(securityError));
    await expectLater(
        codec.encode('TEACHERS', metadata), throwsA(securityError));
    expect(store.value, isNull);
    store.failRead = true;
    await expectLater(codec.decodeRows('TEACHERS', []), throwsA(securityError));
  });

  test('oversized protected cell fails before transport', () async {
    await expectLater(
        codec.encode('TEACHERS', {...metadata, 'TeacherName': 'x' * 50000}),
        throwsA(securityError));
  });
}
