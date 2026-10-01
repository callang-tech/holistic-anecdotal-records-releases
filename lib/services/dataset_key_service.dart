import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import 'sync_context_service.dart';

/// Messages are deliberately independent of underlying payloads/exceptions.
class DataSecurityException implements Exception {
  const DataSecurityException(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract interface class DatasetKeyStore {
  Future<String?> read();
  Future<void> write(String value);
}

/// The only persistent secret storage used by production. No preferences or
/// plaintext-file fallback. CRED_PERSIST_LOCAL_MACHINE persists for THIS user
/// across logons on this computer; it is not DPAPI's machine-wide scope flag.
class WindowsDatasetKeyStore implements DatasetKeyStore {
  static const _name = 'HolisticAnecdotalRecords/DatasetKey/v1';
  void _requireWindows() {
    if (!Platform.isWindows) {
      throw const DataSecurityException('Windows secure storage is required.');
    }
  }

  @override
  Future<String?> read() async {
    _requireWindows();
    return using((arena) {
      final output = arena<Pointer<CREDENTIAL>>();
      final result = CredRead(PCWSTR(_name.toNativeUtf16(allocator: arena)),
          CRED_TYPE_GENERIC, output);
      if (!result.value) {
        if (result.error == ERROR_NOT_FOUND) return null;
        throw const DataSecurityException(
            'Windows Credential Manager read failed.');
      }
      final credential = output.value;
      try {
        final size = credential.ref.CredentialBlobSize;
        if (size <= 0 || size > 2048) throw const FormatException();
        return utf8.decode(credential.ref.CredentialBlob.asTypedList(size));
      } finally {
        credential.ref.CredentialBlob
            .asTypedList(credential.ref.CredentialBlobSize)
            .fillRange(0, credential.ref.CredentialBlobSize, 0);
        CredFree(credential);
      }
    });
  }

  @override
  Future<void> write(String value) async {
    _requireWindows();
    using((arena) {
      final bytes = utf8.encode(value);
      if (bytes.length > 2048) throw const FormatException();
      final blob = arena<Uint8>(bytes.length);
      blob.asTypedList(bytes.length).setAll(0, bytes);
      final credential = arena<CREDENTIAL>();
      credential.ref
        ..Type = CRED_TYPE_GENERIC
        ..TargetName = PWSTR(_name.toNativeUtf16(allocator: arena))
        ..UserName = PWSTR('Holistic dataset'.toNativeUtf16(allocator: arena))
        ..CredentialBlobSize = bytes.length
        ..CredentialBlob = blob
        ..Persist = CRED_PERSIST_LOCAL_MACHINE;
      try {
        if (!CredWrite(credential, 0).value) {
          throw const DataSecurityException(
              'Windows Credential Manager write failed.');
        }
      } finally {
        blob.asTypedList(bytes.length).fillRange(0, bytes.length, 0);
      }
    });
  }
}

class DatasetKey {
  DatasetKey(
      {required this.id, required this.datasetId, required List<int> bytes})
      : bytes = List.unmodifiable(bytes) {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(id) ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(datasetId) ||
        bytes.length != 32 ||
        bytes.any((b) => b < 0 || b > 255)) {
      throw const DataSecurityException('Invalid encryption key record.');
    }
  }
  final String id, datasetId;
  final List<int> bytes;
  SecretKey get secret => SecretKey(bytes);
  String encode() => jsonEncode({
        'v': 1,
        'id': id,
        'dataset': datasetId,
        'key': base64UrlEncode(bytes),
      });
  static DatasetKey decode(String value) {
    try {
      final map = jsonDecode(value) as Map<String, dynamic>;
      if (map['v'] != 1) throw const FormatException();
      return DatasetKey(
          id: map['id'] as String,
          datasetId: map['dataset'] as String,
          bytes: base64Url.decode(map['key'] as String));
    } catch (_) {
      throw const DataSecurityException('Invalid encryption key record.');
    }
  }
}

List<int> securityRandomBytes(int length) {
  final random = Random.secure();
  return List.generate(length, (_) => random.nextInt(256));
}

String _randomId() => securityRandomBytes(16)
    .map((b) => b.toRadixString(16).padLeft(2, '0'))
    .join();

class DatasetKeyService {
  DatasetKeyService(
      {required DatasetKeyStore store, required SyncContextService context})
      : _store = store,
        _context = context;
  static final instance = DatasetKeyService(
      store: WindowsDatasetKeyStore(), context: SyncContextService.instance);
  final DatasetKeyStore _store;
  final SyncContextService _context;

  Future<DatasetKey?> load() async {
    try {
      final stored = await _store.read();
      return stored == null ? null : DatasetKey.decode(stored);
    } catch (_) {
      throw const DataSecurityException(
          'Windows secure storage is unavailable or its encryption record is invalid. Cloud synchronization is blocked.');
    }
  }

  Future<DatasetKey> requireKey() async =>
      await load() ??
      (throw const DataSecurityException(
          'Encryption is not configured. Set up encryption for a fresh cloud dataset, or import its recovery key in Admin > Data Security.'));

  Future<void> _save(DatasetKey key) async {
    try {
      final value = key.encode();
      await _store.write(value);
      if (await _store.read() != value) throw const FormatException();
    } catch (_) {
      throw const DataSecurityException(
          'Could not securely save the encryption key. Cloud synchronization must not continue until secure storage is working.');
    }
  }

  Future<void> setUp() => _context.exclusive(() async {
        if (await load() != null) {
          throw const DataSecurityException(
              'Encryption is already configured. The existing key was not replaced.');
        }
        await _save(DatasetKey(
            id: _randomId(),
            datasetId: _randomId(),
            bytes: securityRandomBytes(32)));
      });

  Future<String> exportRecovery(String password) =>
      _context.exclusive(() async {
        if (password.runes.length < 16) {
          throw const DataSecurityException(
              'Use a recovery password of at least 16 characters.');
        }
        final key = await requireKey();
        // PBKDF2 is intentionally off the UI isolate; parameters are fixed by v1.
        return RecoveryPackage.sealInBackground(key, password);
      });

  Future<void> importRecovery(String package, String password,
          {bool replaceExisting = false}) =>
      _context.exclusive(() async {
        // Authenticate completely before any persistent write.
        final key = await RecoveryPackage.openInBackground(package, password);
        final current = await load();
        if (current != null && !replaceExisting) {
          throw const DataSecurityException(
              'Confirm replacement of the installed recovery key first.');
        }
        await _save(key);
      });
}

class RecoveryPackage {
  // These closures capture only sendable arguments, never the service/guard.
  static Future<String> sealInBackground(DatasetKey key, String password) =>
      Isolate.run(() => seal(key, password));
  static Future<DatasetKey> openInBackground(String package, String password) =>
      Isolate.run(() => open(package, password));
  static const format = 'HOLISTIC-RECOVERY-v1';
  static const iterations = 600000;
  static final _cipher = AesGcm.with256bits();
  static Future<SecretKey> _derive(String password, List<int> salt) =>
      Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256)
          .deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);

  static List<int> _aad(String id, String dataset, String salt) =>
      utf8.encode(jsonEncode(
          [format, 'PBKDF2-HMAC-SHA256', iterations, id, dataset, salt]));

  static Future<String> seal(DatasetKey key, String password) async {
    final salt = securityRandomBytes(16);
    final encodedSalt = base64UrlEncode(salt);
    final box = await _cipher.encrypt(utf8.encode(key.encode()),
        secretKey: await _derive(password, salt),
        nonce: securityRandomBytes(12),
        aad: _aad(key.id, key.datasetId, encodedSalt));
    return jsonEncode({
      'format': format,
      'kdf': 'PBKDF2-HMAC-SHA256',
      'iterations': iterations,
      'id': key.id,
      'dataset': key.datasetId,
      'salt': encodedSalt,
      'data':
          base64UrlEncode([...box.nonce, ...box.cipherText, ...box.mac.bytes]),
    });
  }

  static Future<DatasetKey> open(String package, String password) async {
    try {
      if (package.length > 8192) throw const FormatException();
      final map = jsonDecode(package) as Map<String, dynamic>;
      if (map['format'] != format ||
          map['kdf'] != 'PBKDF2-HMAC-SHA256' ||
          map['iterations'] != iterations) {
        throw const FormatException();
      }
      final saltText = map['salt'] as String;
      final salt = base64Url.decode(saltText);
      final packed = base64Url.decode(map['data'] as String);
      if (salt.length != 16 || packed.length < 29) {
        throw const FormatException();
      }
      final bytes = await _cipher.decrypt(
          SecretBox(packed.sublist(12, packed.length - 16),
              nonce: packed.sublist(0, 12),
              mac: Mac(packed.sublist(packed.length - 16))),
          secretKey: await _derive(password, salt),
          aad: _aad(map['id'] as String, map['dataset'] as String, saltText));
      final key = DatasetKey.decode(utf8.decode(bytes));
      if (key.id != map['id'] || key.datasetId != map['dataset']) {
        throw const FormatException();
      }
      return key;
    } catch (_) {
      throw const DataSecurityException(
          'Recovery file could not be authenticated. Check the file and recovery password. No key was imported.');
    }
  }
}
