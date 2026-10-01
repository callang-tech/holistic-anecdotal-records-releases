import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:holistic_anecdotal_records/services/dataset_key_service.dart';
import 'package:holistic_anecdotal_records/services/sheets_encryption_codec.dart';
import 'package:holistic_anecdotal_records/services/sync_context_service.dart';
import 'support/encrypted_sheets_fixture.dart';

void main() {
  const phrase = 'Synthetic shared cloud passphrase 2026!';
  late List<DatasetKeyService> devices;
  late List<MemoryKeyStore> stores;
  late DatasetKey wrongKey;
  DatasetKeyService service(MemoryKeyStore store) => DatasetKeyService(
      store: store,
      context: SyncContextService(
          database: () => throw StateError('No real database allowed')));

  setUpAll(() async {
    stores = List.generate(4, (_) => MemoryKeyStore());
    devices = stores.map(service).toList();
    await Future.wait(devices.map((d) => d.setUpWithPassphrase(phrase)));
    wrongKey = await CloudPassphraseKey.deriveInBackground('$phrase wrong');
  });

  test('four independent devices reproduce the key without storing passphrase',
      () async {
    final first = await devices.first.requireKey();
    for (var i = 0; i < devices.length; i++) {
      expect((await devices[i].requireKey()).encode(), first.encode());
      expect(stores[i].value!.contains(phrase), isFalse);
      expect(stores[i].writes, 1);
    }
    await devices.first.setUpWithPassphrase(phrase);
    expect(stores.first.writes, 1);
    await expectLater(devices.first.setUpWithPassphrase('$phrase wrong'),
        throwsA(isA<DataSecurityException>()));
    expect((await devices.first.requireKey()).encode(), first.encode());
  });

  test('same-passphrase devices synchronize multiple rows in every table',
      () async {
    final sender = SheetsEncryptionCodec(devices[0]);
    final remote = EncryptedMemorySheets(
        SyncContextService(database: () => throw StateError('No database')),
        sender);
    for (final entry in EncryptedMemorySheets.headers.entries) {
      final table = entry.key;
      final expected = List.generate(
          3,
          (i) => <String, Object?>{
                for (final c in entry.value) c: null,
                'SyncID': 'synthetic-$table-$i',
                if (entry.value.contains('LearnerSyncID'))
                  'LearnerSyncID': 'parent-$i',
                'CreatedAt': '2026-10-02',
                'UpdatedAt': '2026-10-02',
                'DeviceID': 'synthetic',
                'Version': 1,
                'Deleted': 0,
                for (final c in SheetsEncryptionCodec.protectedFields[table]!)
                  c: i == 0
                      ? null
                      : i == 1
                          ? ''
                          : 'Synthetic $c\nUnicode: \u00f1',
              });
      await remote.upsertRowsBySyncId(
          sheetTitle: table,
          headers: entry.value,
          rows: expected
              .map((r) => entry.value.map((c) => r[c]).toList())
              .toList());
      for (final wire in remote.records[table]!) {
        for (final c in SheetsEncryptionCodec.protectedFields[table]!) {
          expect(wire[c], startsWith('ENC:v1:'));
        }
        expect(wire['Version'], 1);
      }
      for (final device in devices.skip(1)) {
        final reader = EncryptedMemorySheets(
            remote.context, SheetsEncryptionCodec(device));
        reader.records[table] = remote.records[table]!;
        expect(
            await reader.downloadTable(
                sheetTitle: table, expectedHeaders: entry.value),
            expected);
      }
    }
    expect(remote.writes, 15);
  });

  test('wrong passphrase and modified ciphertext reject the entire batch',
      () async {
    final codec = SheetsEncryptionCodec(devices.first);
    final rows = [
      for (var i = 0; i < 2; i++)
        await codec.encode('TEACHERS', {
          'SyncID': 'synthetic-$i',
          'Deleted': 0,
          'TeacherName': 'Synthetic teacher',
        })
    ];
    final wrongStore = MemoryKeyStore()..value = wrongKey.encode();
    await expectLater(
        SheetsEncryptionCodec(service(wrongStore)).decodeRows('TEACHERS', rows),
        throwsA(isA<DataSecurityException>()));
    final parts = (rows.last['TeacherName'] as String).split(':');
    final packed = base64Url.decode(parts[3]);
    packed[13] ^= 1;
    rows.last['TeacherName'] =
        '${parts.take(3).join(':')}:${base64UrlEncode(packed)}';
    await expectLater(codec.decodeRows('TEACHERS', rows),
        throwsA(isA<DataSecurityException>()));
  });

  test('weak passphrase and secure-store failure never write a key', () async {
    final store = MemoryKeyStore();
    await expectLater(service(store).setUpWithPassphrase('short'),
        throwsA(isA<DataSecurityException>()));
    expect(store.writes, 0);
    store.failRead = true;
    await expectLater(service(store).setUpWithPassphrase(phrase),
        throwsA(isA<DataSecurityException>()));
    expect(store.writes, 0);
  });
}
