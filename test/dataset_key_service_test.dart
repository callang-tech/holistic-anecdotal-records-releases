import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:holistic_anecdotal_records/services/dataset_key_service.dart';
import 'package:holistic_anecdotal_records/services/sheets_encryption_codec.dart';
import 'package:holistic_anecdotal_records/services/sync_context_service.dart';
import 'support/encrypted_sheets_fixture.dart';

void main() {
  late MemoryKeyStore store;
  late DatasetKeyService service;
  const password = 'Synthetic recovery password 123!';
  DatasetKeyService make(MemoryKeyStore s) => DatasetKeyService(
      store: s,
      context: SyncContextService(
          database: () => throw StateError('No SQLite in key tests')));
  setUp(() {
    store = MemoryKeyStore();
    service = make(store);
  });

  test('setup creates 256 bits and never replaces an installed key', () async {
    await service.setUp();
    final key = await service.requireKey();
    expect(key.bytes.length, 32);
    expect(key.id.length, 32);
    final before = store.value;
    await expectLater(service.setUp(), throwsA(isA<DataSecurityException>()));
    expect(store.value, before);
    expect(store.writes, 1);
  });
  test('secure-store failures have no insecure fallback', () async {
    store.failWrite = true;
    await expectLater(service.setUp(), throwsA(isA<DataSecurityException>()));
    expect(store.value, isNull);
    store.failRead = true;
    await expectLater(service.setUp(), throwsA(isA<DataSecurityException>()));
    expect(store.writes, 0);
  });
  test('concurrent setup does not replace a key', () async {
    final attempts = await Future.wait([service.setUp(), service.setUp()]
        .map((f) => f.then((_) => true, onError: (_) => false)));
    expect(attempts.where((v) => v).length, 1);
    expect(store.writes, 1);
  });
  test(
      'protected recovery, wrong password, corruption, confirmed import and second device',
      () async {
    await service.setUp();
    final original = await service.requireKey();
    final package = await service.exportRecovery(password);
    expect(package, isNot(contains(base64UrlEncode(original.bytes))));
    expect(package, isNot(contains(password)));
    final otherStore = MemoryKeyStore();
    final other = make(otherStore);
    await other.setUp();
    final before = otherStore.value;
    await expectLater(
        other.importRecovery(package, 'Wrong recovery password',
            replaceExisting: true),
        throwsA(isA<DataSecurityException>()));
    expect(otherStore.value, before);
    final corrupt = jsonDecode(package) as Map<String, dynamic>;
    final data = base64Url.decode(corrupt['data'] as String)..[13] ^= 1;
    corrupt['data'] = base64UrlEncode(data);
    await expectLater(
        other.importRecovery(jsonEncode(corrupt), password,
            replaceExisting: true),
        throwsA(isA<DataSecurityException>()));
    expect(otherStore.value, before);
    await expectLater(other.importRecovery(package, password),
        throwsA(isA<DataSecurityException>()));
    expect(otherStore.value, before);
    await other.importRecovery(package, password, replaceExisting: true);
    final imported = await other.requireKey();
    expect(imported.bytes, original.bytes);
    expect(imported.id, original.id);
    expect(imported.datasetId, original.datasetId);
    final row = await SheetsEncryptionCodec(service).encode(
        'TEACHERS', {'SyncID': 'test', 'Deleted': 0, 'TeacherName': 'Peña'});
    expect(
        (await SheetsEncryptionCodec(other)
            .decode('TEACHERS', row))['TeacherName'],
        'Peña');
    // A new installation imports without replacement confirmation.
    final fresh = make(MemoryKeyStore());
    await fresh.importRecovery(package, password);
    expect((await fresh.requireKey()).bytes, original.bytes);
  }, timeout: const Timeout(Duration(minutes: 3)));
  test('weak export password and malformed recovery fail without writes',
      () async {
    await service.setUp();
    await expectLater(
        service.exportRecovery('short'), throwsA(isA<DataSecurityException>()));
    final before = store.value;
    for (final malformed in ['{}', 'not json', 'x' * 8193]) {
      await expectLater(
          service.importRecovery(malformed, password, replaceExisting: true),
          throwsA(isA<DataSecurityException>()));
    }
    expect(store.value, before);
  });
}
