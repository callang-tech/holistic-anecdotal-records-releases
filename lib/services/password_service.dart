import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Handles the local system password without storing the plaintext password.
///
/// Passwords are stored as PBKDF2-HMAC-SHA256 hashes with a per-password salt.
/// Existing plaintext passwords from older builds are migrated to a hash after
/// a successful normal login.
class PasswordService {
  static const _passwordKey = 'system_password';
  static const _recoveryEmailKey = 'system_password_recovery_email';
  static const _resetCodeHashKey = 'system_password_reset_code_hash';
  static const _resetCodeExpiryKey = 'system_password_reset_code_expiry';

  static const _format = 'pbkdf2_sha256_v1';
  static const _iterations = 120000;
  static const _saltLength = 16;
  static const _derivedKeyLength = 32;
  static const _resetCodeLength = 6;
  static const _resetCodeValidity = Duration(minutes: 10);

  final Random _random = Random.secure();

  Future<String?> getStoredPasswordRecord() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_passwordKey);
  }

  Future<bool> hasPassword() async {
    final record = await getStoredPasswordRecord();
    return record != null && record.trim().isNotEmpty;
  }

  Future<String?> getRecoveryEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_recoveryEmailKey);
  }

  Future<void> setRecoveryEmail(String email) async {
    final normalized = email.trim().toLowerCase();
    if (normalized.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_recoveryEmailKey, normalized);
  }

  /// Verifies the supplied password.
  ///
  /// Older versions of the app stored plaintext passwords. If an old
  /// plaintext value is encountered and matches, it is immediately replaced
  /// with a salted PBKDF2 hash.
  Future<bool> verify(String password) async {
    final prefs = await SharedPreferences.getInstance();
    final record = prefs.getString(_passwordKey);

    if (record == null || record.trim().isEmpty) {
      return false;
    }

    if (record.startsWith('$_format|')) {
      return _verifyHash(password, record);
    }

    // Legacy migration: the old application stored the password directly.
    if (password == record) {
      await _storeHashedPassword(password, prefs: prefs);
      return true;
    }

    return false;
  }

  /// Creates/replaces the local password with a hashed value.
  Future<void> setPassword(String password) async {
    final normalized = password;
    if (normalized.length < 8) {
      throw ArgumentError('Password must contain at least 8 characters.');
    }

    final prefs = await SharedPreferences.getInstance();
    await _storeHashedPassword(normalized, prefs: prefs);
  }

  /// Removes the local password. The next PasswordGate request can require
  /// creation of a new password.
  Future<void> clearPassword() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_passwordKey);
  }

  /// Generates and stores a one-time reset code.
  ///
  /// Only the hash and expiration are stored locally; the actual code is
  /// returned to PasswordGate so it can be sent to the verified Google email.
  Future<String> createResetCode() async {
    final code = _generateNumericCode();
    final prefs = await SharedPreferences.getInstance();

    final salt = _randomBytes(_saltLength);
    final hash = _pbkdf2(
      utf8.encode(code),
      salt,
      iterations: _iterations,
      length: _derivedKeyLength,
    );

    await prefs.setString(
      _resetCodeHashKey,
      '${base64UrlEncode(salt)}:${base64UrlEncode(hash)}',
    );
    await prefs.setInt(
      _resetCodeExpiryKey,
      DateTime.now().add(_resetCodeValidity).millisecondsSinceEpoch,
    );

    return code;
  }

  Future<bool> verifyResetCode(String code) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_resetCodeHashKey);
    final expiryMillis = prefs.getInt(_resetCodeExpiryKey);

    if (stored == null || expiryMillis == null) {
      return false;
    }

    if (DateTime.now().millisecondsSinceEpoch > expiryMillis) {
      await clearResetCode();
      return false;
    }

    final separator = stored.indexOf(':');
    if (separator <= 0) {
      await clearResetCode();
      return false;
    }

    final salt = stored.substring(0, separator);
    final expected = stored.substring(separator + 1);
    final derived = _pbkdf2(
      utf8.encode(code.trim()),
      base64Url.decode(salt),
      iterations: _iterations,
      length: _derivedKeyLength,
    );

    final actual = base64UrlEncode(derived);
    return _constantTimeEquals(actual, expected);
  }

  Future<void> clearResetCode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_resetCodeHashKey);
    await prefs.remove(_resetCodeExpiryKey);
  }

  Future<void> resetPassword({
    required String resetCode,
    required String newPassword,
  }) async {
    final valid = await verifyResetCode(resetCode);
    if (!valid) {
      throw StateError('The reset code is invalid or has expired.');
    }

    await setPassword(newPassword);
    await clearResetCode();
  }

  Future<void> _storeHashedPassword(
    String password, {
    required SharedPreferences prefs,
  }) async {
    final salt = _randomBytes(_saltLength);
    final derived = _pbkdf2(
      utf8.encode(password),
      salt,
      iterations: _iterations,
      length: _derivedKeyLength,
    );

    final record = [
      _format,
      _iterations,
      base64UrlEncode(salt),
      base64UrlEncode(derived),
    ].join('|');

    await prefs.setString(_passwordKey, record);
  }

  bool _verifyHash(String password, String record) {
    final parts = record.split('|');
    if (parts.length != 4 || parts[0] != _format) {
      return false;
    }

    final iterations = int.tryParse(parts[1]);
    if (iterations == null || iterations < 1) {
      return false;
    }

    try {
      final salt = base64Url.decode(parts[2]);
      final expected = base64Url.decode(parts[3]);
      final actual = _pbkdf2(
        utf8.encode(password),
        salt,
        iterations: iterations,
        length: expected.length,
      );

      return _constantTimeBytesEqual(actual, expected);
    } catch (_) {
      return false;
    }
  }

  String _generateNumericCode() {
    final value = _random.nextInt(1000000);
    return value.toString().padLeft(_resetCodeLength, '0');
  }

  Uint8List _randomBytes(int length) {
    return Uint8List.fromList(
      List<int>.generate(length, (_) => _random.nextInt(256)),
    );
  }

  Uint8List _pbkdf2(
    List<int> password,
    List<int> salt, {
    required int iterations,
    required int length,
  }) {
    final hmac = Hmac(sha256, password);
    final blocks = <int>[];
    var blockIndex = 1;

    while (blocks.length < length) {
      final indexBytes = Uint8List(4)
        ..[0] = (blockIndex >> 24) & 0xff
        ..[1] = (blockIndex >> 16) & 0xff
        ..[2] = (blockIndex >> 8) & 0xff
        ..[3] = blockIndex & 0xff;

      var u = hmac.convert(<int>[...salt, ...indexBytes]).bytes;
      final t = List<int>.from(u);

      for (var i = 1; i < iterations; i++) {
        u = hmac.convert(u).bytes;
        for (var j = 0; j < t.length; j++) {
          t[j] ^= u[j];
        }
      }

      blocks.addAll(t);
      blockIndex++;
    }

    return Uint8List.fromList(blocks.take(length).toList());
  }

  bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return result == 0;
  }

  bool _constantTimeBytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }
}
