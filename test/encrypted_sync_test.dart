import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:holistic_anecdotal_records/database/app_database.dart';
import 'package:holistic_anecdotal_records/database/database_repository.dart';
import 'package:holistic_anecdotal_records/services/dataset_key_service.dart';
import 'package:holistic_anecdotal_records/services/sheets_encryption_codec.dart';
import 'package:holistic_anecdotal_records/services/sync_context_service.dart';
import 'package:holistic_anecdotal_records/services/sync_service.dart';
import 'support/encrypted_sheets_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late AppDatabase app;
  late DatabaseRepository repo;
  late SyncContextService context;
  late MemoryKeyStore store;
  late DatasetKeyService keys;
  late SheetsEncryptionCodec codec;
  late EncryptedMemorySheets remote;
  late SyncService sync;
  late int learner;

  Future<Map<String, Object?>> local(String table) async =>
      (await app.database.query('${table}_Table')).single;
  Future<Map<String, Object?>> snapshot() async => {
        for (final table in [
          ...SyncService.syncTables,
          SyncContextService.stateTable,
          SyncContextService.contextTable,
          'sqlite_sequence'
        ])
          table: await app.database.query(table),
        'prefs': {
          for (final k in (await SharedPreferences.getInstance()).getKeys())
            k: (await SharedPreferences.getInstance()).get(k)
        },
      };
  Future<void> upload() async {
    final result = await sync.syncPendingToGoogleSheets();
    expect(result.success, isTrue, reason: result.message);
  }

  Future<void> editTeacher(String name) => app.database.update(
      'TEACHERS_Table', {'TeacherName': name, 'Version': 2}).then((_) {});

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('encrypted_sync_');
    app = AppDatabase.forTesting('${temp.path}/test.db');
    await app.initialize();
    repo = DatabaseRepository.forTesting(app);
    context = SyncContextService(database: () => app.database);
    await context.activate('synthetic-A');
    store = MemoryKeyStore();
    keys = DatasetKeyService(store: store, context: context);
    await keys.setUp();
    codec = SheetsEncryptionCodec(keys);
    remote = EncryptedMemorySheets(context, codec);
    sync = SyncService.forTesting(
        database: app,
        sheets: remote,
        context: context,
        authenticated: () async => true);
    await repo.addTeacher(
        teacherName: 'Teacher Peña', mobileNumber: '09123456789');
    await repo.addSection(
        schoolYear: '2026–2027',
        gradeLevel: '8',
        sectionName: 'Blue',
        adviser: 'Teacher Peña');
    learner = await repo.addLearner(
        lastName: 'Dela-Peña',
        firstName: "Niño O'Neil",
        sex: 'Male',
        age: 13,
        lrn: '00123',
        regionCode: '01',
        notes: 'Una\nIkalawa');
    await repo.addSchoolHistory(
        learnerId: learner,
        schoolYear: '2026–2027',
        grade: '8',
        school: 'Synthetic School',
        section: 'Blue',
        adviser: 'Teacher Peña');
    await repo.addIncident(
        learnerId: learner,
        incidentDate: '2026-09-26',
        observer: 'Teacher Peña',
        behaviorProblem: 'Late',
        details: 'Synthetic private notes');
  });
  tearDown(() async {
    await app.database.close();
    await temp.delete(recursive: true);
  });

  test('normal upload all tables, plaintext headers and normal/find downloads',
      () async {
    await upload();
    expect(remote.writes, 5);
    for (final table in EncryptedMemorySheets.headers.keys) {
      final wire = remote.records[table]!.single;
      for (final c in SheetsEncryptionCodec.protectedFields[table]!) {
        expect(wire[c], startsWith('ENC:v1:'));
      }
      expect((await remote.readRange(sheetTitle: table)).first,
          EncryptedMemorySheets.headers[table]);
      final decoded =
          (await remote.downloadSheetRows(sheetTitle: table)).single;
      expect(
          await remote.findRemoteRecordBySyncId(
              sheetTitle: table, syncId: wire['SyncID'] as String),
          decoded);
    }
    final data = await remote.downloadAllTables();
    expect(data.learners.single['FirstName'], "Niño O'Neil");
    expect(data.learners.single['RegionCode'], '01');
    expect(data.learners.single['Age'], 13);
    expect((await local('LEARNERS'))['LastName'], 'Dela-Peña');
    expect((await sync.compareRemoteWithLocal()).sameCount, 5);
  });

  test(
      'random ciphertext, unchanged sync and final reread compare logical content',
      () async {
    await upload();
    final oldCipher = remote.records['TEACHERS']!.single['TeacherName'];
    await remote.edit('TEACHERS', {});
    expect(remote.records['TEACHERS']!.single['TeacherName'], isNot(oldCipher));
    final writes = remote.writes;
    await upload();
    expect(remote.writes, writes);
    await editTeacher('Local only');
    // The writer receives a differently encrypted but logically identical remote
    // snapshot during its final reread.
    var reads = 0;
    remote.beforeRead = (table) async {
      if (table == 'TEACHERS' && ++reads == 2) await remote.edit(table, {});
    };
    await upload();
    expect((await remote.logical('TEACHERS'))['TeacherName'], 'Local only');
    expect(await sync.getTotalPendingCount(), 0);
  });

  test(
      'late logical edit fails final reread and preserves pending local change',
      () async {
    await upload();
    await editTeacher('Local edit');
    var reads = 0;
    remote.beforeRead = (table) async {
      if (table == 'TEACHERS' && ++reads == 2) {
        await remote.edit(table, {'TeacherName': 'Late remote'});
      }
    };
    final result = await sync.syncPendingToGoogleSheets();
    expect(result.success, isFalse);
    expect(result.conflictCount, 1);
    expect((await local('TEACHERS'))['TeacherName'], 'Local edit');
    expect((await remote.logical('TEACHERS'))['TeacherName'], 'Late remote');
  });

  test(
      'remote-only, equivalent and divergent changes; Keep Local and Use Remote',
      () async {
    await upload();
    await remote.edit('TEACHERS', {'TeacherName': 'Remote only'});
    expect(
        (await sync.syncPendingToGoogleSheets()).requiresRemoteApply, isTrue);
    expect((await sync.applyRemoteChangesToLocal()).success, isTrue);
    expect((await local('TEACHERS'))['TeacherName'], 'Remote only');
    await editTeacher('Equivalent');
    await remote.edit('TEACHERS', {'TeacherName': 'Equivalent'});
    final writes = remote.writes;
    await upload();
    expect(remote.writes, writes);
    await editTeacher('Local choice');
    await remote.edit('TEACHERS', {'TeacherName': 'Remote choice'});
    expect((await sync.compareRemoteWithLocal()).conflictCount, 1);
    final id = (await local('TEACHERS'))['SyncID'] as String;
    expect(
        (await sync.resolveConflictKeepLocal(
                tableName: 'TEACHERS_Table', syncId: id))
            .success,
        isTrue);
    expect((await remote.logical('TEACHERS'))['TeacherName'], 'Local choice');
    await editTeacher('Another local');
    await remote.edit('TEACHERS', {'TeacherName': 'Accept remote'});
    expect(
        (await sync.resolveConflictUseRemote(
                tableName: 'TEACHERS_Table', syncId: id))
            .success,
        isTrue);
    expect((await local('TEACHERS'))['TeacherName'], 'Accept remote');
  });

  test('duplicate SyncID remains a conflict; new remote row applies plaintext',
      () async {
    await upload();
    remote.records['TEACHERS']!.add(Map.of(remote.records['TEACHERS']!.single));
    expect((await sync.compareRemoteWithLocal()).conflictCount, 1);
    remote.records['TEACHERS']!.removeLast();
    final row = {
      ...await remote.logical('TEACHERS'),
      'SyncID': 'new-teacher',
      'TeacherName': 'New remote'
    };
    remote.records['TEACHERS']!.add(await codec.encode('TEACHERS', row));
    expect((await sync.compareRemoteWithLocal()).newRemoteCount, 1);
    expect((await sync.applyRemoteChangesToLocal()).success, isTrue);
    expect((await repo.getTeachers()).length, 2);
  });

  for (final deleted in [0, 1, 2]) {
    test('Deleted=$deleted preserves encrypted child relations and applies',
        () async {
      await upload();
      await remote
          .edit('LEARNERS', {'Deleted': deleted, 'NotesDetails': 'Changed'});
      expect((await sync.applyRemoteChangesToLocal()).success, isTrue);
      expect((await local('LEARNERS'))['Deleted'], deleted);
      expect((await local('SCHOOL_HISTORY'))['LearnerID'], learner);
      expect((await local('INCIDENTS'))['LearnerID'], learner);
      await app.database.update(
          'LEARNERS_Table', {'Deleted': 0, 'NotesDetails': 'Locally restored'});
      await upload();
      expect(remote.records['LEARNERS']!.single['Deleted'], 0);
    });
  }

  test(
      'encrypted full restore remaps IDs and preserves school/personnel/search mechanics',
      () async {
    await upload();
    final remoteId = remote.records['LEARNERS']!.single['LearnerID'];
    // Change irrelevant remote numeric ID; authenticated stable parent survives.
    remote.records['LEARNERS']!.single['LearnerID'] = 9876;
    final restored = await sync.restoreFromSpreadsheet('synthetic-B');
    expect(restored.total, 5);
    final id = (await local('LEARNERS'))['LearnerID'] as int;
    expect(id, isNot(remoteId));
    expect(id, isNot(9876));
    expect((await local('SCHOOL_HISTORY'))['LearnerID'], id);
    expect((await local('INCIDENTS'))['LearnerID'], id);
    expect(await context.activeSpreadsheetId(), 'synthetic-B');
    expect((await sync.compareRemoteWithLocal()).sameCount, 5);
    expect(await repo.addTeacher(teacherName: ' teacher   PEÑA '),
        (await local('TEACHERS'))['TeacherID']);
    expect(
        await repo.addSection(
            schoolYear: '2026-2027',
            gradeLevel: 'Grade 8',
            sectionName: ' blue ',
            adviser: ''),
        (await local('SECTIONS'))['SectionID']);
    expect(
        (await repo.getSections(schoolYear: '2026-2027', gradeLevel: '8'))
            .single['Adviser'],
        'Teacher Peña');
    final matches = await repo.searchIncidentRecords(
        lastName: 'Dela-Peña',
        incidentGradeLevel: '8',
        schoolYearLastEnrolled: '2026-2027',
        section: 'Blue',
        observer: 'Teacher Peña');
    expect(matches.length, 1);
    expect(matches.single['LearnerID'], id);
  });

  for (final failure in [
    'wrong key',
    'corrupt cell',
    'cleared cell',
    'legacy',
    'missing key',
    'storage'
  ]) {
    test('$failure blocks restore/download/upload without changing local state',
        () async {
      await upload();
      final before = await snapshot();
      if (failure == 'wrong key') {
        final key = await keys.requireKey();
        store.value = DatasetKey(
                id: key.id,
                datasetId: key.datasetId,
                bytes: securityRandomBytes(32))
            .encode();
      } else if (failure == 'missing key') {
        store.value = null;
      } else if (failure == 'storage') {
        store.failRead = true;
      } else {
        remote.records['INCIDENTS']!.single['Details'] = failure == 'legacy'
            ? 'sensitive legacy'
            : failure == 'cleared cell'
                ? null
                : 'ENC:v1:broken:AAAA';
      }
      final writes = remote.writes;
      await expectLater(sync.restoreFromSpreadsheet('synthetic-B'),
          throwsA(isA<DataSecurityException>()));
      expect(await snapshot(), before);
      expect((await sync.applyRemoteChangesToLocal()).success, isFalse);
      expect(await snapshot(), before);
      expect((await sync.syncPendingToGoogleSheets()).success, isFalse);
      expect(await snapshot(), before);
      expect(remote.writes, writes);
    });
  }

  test('transport failure leaves pending row and baseline intact', () async {
    await upload();
    await editTeacher('Pending');
    final before = await app.database
        .query(SyncContextService.stateTable, orderBy: 'TableName, SyncID');
    remote.failWrites = true;
    expect((await sync.syncPendingToGoogleSheets()).success, isFalse);
    expect(
        await app.database
            .query(SyncContextService.stateTable, orderBy: 'TableName, SyncID'),
        before);
    expect(await sync.getTotalPendingCount(), greaterThan(0));
  });

  for (final corrupt in [false, true]) {
    test(
        'encrypted reconnect authenticates before ownership change (corrupt=$corrupt)',
        () async {
      await upload();
      await app.database
          .execute('DROP TABLE ${SyncContextService.contextTable}');
      final before = await app.database
          .query(SyncContextService.stateTable, orderBy: 'TableName');
      final writes = remote.writes;
      if (corrupt) remote.records['INCIDENTS']!.single['Details'] = 'legacy';
      if (corrupt) {
        await expectLater(
            sync.reconnectCurrentSpreadsheet(
                expectedSpreadsheetId: 'synthetic-A'),
            throwsA(isA<DataSecurityException>()));
        expect(
            await app.database
                .query(SyncContextService.stateTable, orderBy: 'TableName'),
            before);
        expect(await sync.legacyUnownedSpreadsheetId(), 'synthetic-A');
      } else {
        final result = await sync.reconnectCurrentSpreadsheet(
            expectedSpreadsheetId: 'synthetic-A');
        expect(result.comparisonError, isNull);
        expect(result.comparison!.sameCount, 5);
        expect(await context.activeSpreadsheetId(), 'synthetic-A');
      }
      expect(remote.writes, writes);
    });
  }
}
