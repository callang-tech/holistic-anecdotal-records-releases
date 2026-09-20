import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:holistic_anecdotal_records/database/app_database.dart';
import 'package:holistic_anecdotal_records/models/sync_comparison.dart';
import 'package:holistic_anecdotal_records/models/sync_record_state.dart';
import 'package:holistic_anecdotal_records/services/google_sheets_service.dart';
import 'package:holistic_anecdotal_records/services/sync_context_service.dart';
import 'package:holistic_anecdotal_records/services/sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const table = SyncService.teachersTable;
  const title = GoogleSheetsService.teachersSheet;
  const stamp = '2026-01-01T00:00:00.000Z';
  late Directory directory;
  late AppDatabase app;
  late SyncContextService context;
  late MemorySheets remote;
  late SyncService sync;

  Future<Map<String, Object?>> local() async =>
      (await app.database.query(table)).single;
  Future<Map<String, Object?>> baseline() async =>
      (await app.database.query(SyncContextService.stateTable,
              where: 'TableName = ?', whereArgs: [table]))
          .single;
  Future<void> editLocal(String name, {int? deleted}) async {
    await app.database.update(table, {
      'TeacherName': name,
      'Version': 2,
      'UpdatedAt': '2026-02-01T00:00:00.000Z',
      if (deleted != null) 'Deleted': deleted,
    });
  }

  Map<String, Object?> remoteRow() => remote.records[title]!.single;
  Future<void> seedBaseline() async {
    await context.exclusive(() => app.database.transaction((txn) =>
        context.replaceImportedStateInTransaction(txn, spreadsheetId: 'A')));
    await context.activeSpreadsheetId();
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('conflict_safe_sync_');
    app = AppDatabase.forTesting('${directory.path}/test.db');
    await app.initialize();
    context = SyncContextService(database: () => app.database);
    await context.activate('A');
    await app.database.insert(table, {
      'SyncID': 'teacher-1',
      'TeacherName': 'Original',
      'Status': 'Active',
      'CreatedAt': stamp,
      'UpdatedAt': stamp,
      'DeviceID': 'windows',
      'Version': 1,
      'Deleted': 0,
    });
    await seedBaseline();
    remote = MemorySheets(context);
    remote.records[title] = [Map.of(await local())];
    sync = SyncService.forTesting(
        database: app,
        sheets: remote,
        context: context,
        authenticated: () async => true);
  });

  tearDown(() async {
    await app.database.close();
    await directory.delete(recursive: true);
  });

  test('local-only change uploads and advances the exact baseline', () async {
    final old = await baseline();
    await editLocal('Local edit');
    final result = await sync.syncPendingToGoogleSheets();
    expect(result.success, isTrue);
    expect(remote.writes, 1);
    expect(remoteRow()['TeacherName'], 'Local edit');
    expect((await baseline())['SyncedFingerprint'],
        SyncRecordState.fingerprint(await local()));
    expect((await baseline())['SyncedFingerprint'],
        isNot(old['SyncedFingerprint']));
    expect(await sync.getTotalPendingCount(), 0);
  });

  test('remote-only change is not overwritten and existing pull accepts it',
      () async {
    remoteRow()['TeacherName'] = 'Remote edit';
    remoteRow()['Version'] = 2;
    final result = await sync.syncPendingToGoogleSheets();
    expect(result.success, isFalse);
    expect(result.requiresRemoteApply, isTrue);
    expect(remote.writes, 0);
    expect((await local())['TeacherName'], 'Original');
    final applied = await sync.applyRemoteChangesToLocal();
    expect(applied.success, isTrue);
    expect((await local())['TeacherName'], 'Remote edit');
    expect(await sync.getTotalPendingCount(), 0);
  });

  test('divergent changes preserve both sides and remain pending', () async {
    final before = await baseline();
    await editLocal('Local edit');
    remoteRow()['TeacherName'] = 'Remote edit';
    remoteRow()['Version'] = 99;
    final result = await sync.syncPendingToGoogleSheets();
    expect(result.success, isFalse);
    expect(result.message, contains('conflict review required'));
    expect(result.requiresRemoteApply, isFalse);
    expect(result.totalPending, 1);
    expect(remote.writes, 0);
    expect((await local())['TeacherName'], 'Local edit');
    expect(remoteRow()['TeacherName'], 'Remote edit');
    expect(
        (await baseline())['SyncedFingerprint'], before['SyncedFingerprint']);
    expect((await sync.compareRemoteWithLocal()).conflictCount, 1);
  });

  test('independent equivalent changes reconcile without upload', () async {
    await editLocal(' Same edit ');
    remoteRow()['TeacherName'] = 'same EDIT';
    remoteRow()['Version'] = 7;
    remoteRow()['UpdatedAt'] = '2026-03-01T00:00:00.000Z';
    final result = await sync.syncPendingToGoogleSheets();
    expect(result.success, isTrue);
    expect(remote.writes, 0);
    expect(await sync.getTotalPendingCount(), 0);
    expect((await baseline())['SyncedFingerprint'],
        SyncRecordState.fingerprint(await local()));
  });

  test('manual Sheet edit with unchanged version and timestamp is detected',
      () async {
    await editLocal('Local edit');
    remoteRow()['TeacherName'] = 'Manual Sheet edit';
    expect(remoteRow()['Version'], 1);
    expect(remoteRow()['UpdatedAt'], stamp);
    expect((await sync.syncPendingToGoogleSheets()).success, isFalse);
    expect(remote.writes, 0);
    expect((await sync.compareRemoteWithLocal()).conflictCount, 1);
  });

  test('legacy baseline does not infer trust from matching metadata', () async {
    await app.database
        .update(SyncContextService.stateTable, {'SyncedFingerprint': null});
    remoteRow()['TeacherName'] = 'Manual edit';
    final result = await sync.syncPendingToGoogleSheets();
    expect(result.success, isFalse);
    expect(remote.writes, 0);
    expect((await baseline())['SyncedFingerprint'], isNull);
    expect(await sync.getTotalPendingCount(), 1);
  });

  test('legacy baseline upgrades only after equivalent sides are observed',
      () async {
    await app.database
        .update(SyncContextService.stateTable, {'SyncedFingerprint': null});
    expect((await sync.syncPendingToGoogleSheets()).success, isTrue);
    expect((await baseline())['SyncedFingerprint'],
        SyncRecordState.fingerprint(await local()));
    expect(remote.writes, 0);
  });

  for (final deleted in [1, 2, 3]) {
    test('local Deleted=$deleted versus remote edit conflicts', () async {
      await editLocal('Original', deleted: deleted);
      remoteRow()['TeacherName'] = 'Remote edit';
      expect((await sync.syncPendingToGoogleSheets()).success, isFalse);
      expect(remote.writes, 0);
      expect((await local())['Deleted'], deleted);
      expect((await sync.compareRemoteWithLocal()).conflictCount, 1);
      expect(await sync.getTotalPendingCount(), 1);
    });
  }

  for (final deleted in [1, 2]) {
    test('remote Deleted=$deleted cannot overwrite a pending local edit',
        () async {
      await editLocal('Local edit');
      remoteRow()['Deleted'] = deleted;
      remoteRow()['Version'] = 99;
      final result = await sync.applyRemoteChangesToLocal();
      expect(result.conflicts, 1);
      expect((await local())['TeacherName'], 'Local edit');
      expect((await local())['Deleted'], 0);
      expect(await sync.getTotalPendingCount(), 1);
    });
  }

  test(
      'physical remote removal does not resurrect or destroy pending local edit',
      () async {
    await editLocal('Local edit');
    remote.records[title]!.clear();
    expect((await sync.syncPendingToGoogleSheets()).success, isFalse);
    await sync.applyRemoteChangesToLocal();
    expect(remote.writes, 0);
    expect((await local())['TeacherName'], 'Local edit');
    expect(await sync.getTotalPendingCount(), 1);
  });

  test('failed upload leaves the baseline unchanged and row pending', () async {
    final before = await baseline();
    await editLocal('Local edit');
    remote.failWrites = true;
    expect((await sync.syncPendingToGoogleSheets()).success, isFalse);
    expect(await baseline(), before);
    expect(await sync.getTotalPendingCount(), 1);
    expect(remoteRow()['TeacherName'], 'Original');
  });

  test('late remote edit is rechecked by the actual Sheets writer', () async {
    final before = await baseline();
    await editLocal('Local edit');
    remote.beforeRead = () async {
      remoteRow()['TeacherName'] = 'Late edit';
    };
    final result = await sync.syncPendingToGoogleSheets();
    expect(result.success, isFalse);
    expect(remote.writes, 0);
    expect(remoteRow()['TeacherName'], 'Late edit');
    expect(
        (await baseline())['SyncedFingerprint'], before['SyncedFingerprint']);
    expect(await sync.getTotalPendingCount(), 1);
  });

  test('Keep Local uploads explicit choice and establishes new baseline',
      () async {
    await editLocal('Local edit');
    remoteRow()['TeacherName'] = 'Remote edit';
    remoteRow()['Version'] = 8;
    final result = await sync.resolveConflictKeepLocal(
        tableName: table, syncId: 'teacher-1');
    expect(result.success, isTrue);
    expect(remoteRow()['TeacherName'], 'Local edit');
    expect(remoteRow()['Version'], 9);
    expect((await baseline())['SyncedFingerprint'],
        SyncRecordState.fingerprint(remoteRow()));
    expect(await sync.getTotalPendingCount(), 0);
  });

  test('Use Remote applies explicit choice and establishes new baseline',
      () async {
    await editLocal('Local edit');
    remoteRow()['TeacherName'] = 'Remote edit';
    final result = await sync.resolveConflictUseRemote(
        tableName: table, syncId: 'teacher-1');
    expect(result.success, isTrue);
    expect((await local())['TeacherName'], 'Remote edit');
    expect((await baseline())['SyncedFingerprint'],
        SyncRecordState.fingerprint(remoteRow()));
    expect(await sync.getTotalPendingCount(), 0);
  });

  test('Keep Local failure does not advance baseline', () async {
    final before = await baseline();
    await editLocal('Local edit');
    remoteRow()['TeacherName'] = 'Remote edit';
    remote.failWrites = true;
    expect(
        (await sync.resolveConflictKeepLocal(
                tableName: table, syncId: 'teacher-1'))
            .success,
        isFalse);
    expect(await baseline(), before);
    expect(await sync.getTotalPendingCount(), 1);
  });

  test('automatic sync success flag stays false for a conflict', () async {
    await editLocal('Local edit');
    remoteRow()['TeacherName'] = 'Remote edit';
    // ViewScreen uses this shared result.success for its automatic-sync message.
    final automaticResult = await sync.syncPendingToGoogleSheets();
    expect(automaticResult.success, isFalse);
    expect(automaticResult.message, contains('Saved locally'));
    expect(automaticResult.message, contains('conflict review required'));
  });

  test('local edit during upload remains pending after the uploaded snapshot',
      () async {
    await editLocal('First edit');
    remote.beforeWrite = () => editLocal('Later edit');
    final result = await sync.syncPendingToGoogleSheets();
    expect(result.success, isFalse);
    expect(remoteRow()['TeacherName'], 'First edit');
    expect((await local())['TeacherName'], 'Later edit');
    expect((await baseline())['SyncedFingerprint'],
        SyncRecordState.fingerprint(remoteRow()));
    expect(await sync.getTotalPendingCount(), 1);
  });

  test('new record with no baseline appends safely', () async {
    await app.database.delete(SyncContextService.stateTable);
    remote.records[title]!.clear();
    expect((await sync.syncPendingToGoogleSheets()).success, isTrue);
    expect(remote.writes, 1);
    expect(await sync.getTotalPendingCount(), 0);
  });

  test('duplicate remote identity is a conflict, not an arbitrary winner',
      () async {
    await editLocal('Local edit');
    remote.records[title]!.add(Map.of(remoteRow()));
    expect((await sync.syncPendingToGoogleSheets()).success, isFalse);
    expect(remote.writes, 0);
  });

  test('target activation waits for the whole guarded synchronization',
      () async {
    await editLocal('Local edit');
    final entered = Completer<void>();
    final release = Completer<void>();
    remote.beforeWrite = () async {
      entered.complete();
      await release.future;
    };
    final operation = sync.syncPendingToGoogleSheets();
    await entered.future;
    var activated = false;
    final activation = context.activate('B').then((_) => activated = true);
    await Future<void>.delayed(Duration.zero);
    expect(activated, isFalse);
    release.complete();
    expect((await operation).success, isTrue);
    await activation;
    expect(await context.activeSpreadsheetId(), 'B');
  });

  test(
      'fingerprints normalize representations but retain relationships and deletion',
      () {
    final a = {
      'SyncID': 'child',
      'LearnerSyncID': 'parent',
      'LearnerID': 10,
      'NotesDetails': ' Hello ',
      'Version': 1,
      'UpdatedAt': stamp,
      'Deleted': 0
    };
    final b = {
      ...a,
      'LearnerID': 900,
      'NotesDetails': 'hello',
      'Version': 5,
      'UpdatedAt': 'other',
      'Deleted': '0',
      'Remarks': null
    };
    expect(SyncRecordState.fingerprint(a), SyncRecordState.fingerprint(b));
    expect(SyncRecordState.fingerprint(a),
        isNot(SyncRecordState.fingerprint({...b, 'LearnerSyncID': 'other'})));
    expect(SyncRecordState.fingerprint(a),
        isNot(SyncRecordState.fingerprint({...b, 'Deleted': 2})));
    expect(SyncRecordState.compare(local: a, remote: b, baseline: null),
        SyncComparisonStatus.same);
  });

  test('existing SQLite schema migrates without inventing a fingerprint',
      () async {
    final before = await baseline();
    await app.database.execute('DROP TABLE SYNC_STATE_Table');
    await app.database.execute('''CREATE TABLE SYNC_STATE_Table (
      TableName TEXT NOT NULL, SyncID TEXT NOT NULL,
      SyncedVersion INTEGER NOT NULL DEFAULT 1,
      SyncedUpdatedAt TEXT NOT NULL DEFAULT '', PRIMARY KEY(TableName, SyncID))''');
    await app.database.insert(SyncContextService.stateTable, {
      for (final key in [
        'TableName',
        'SyncID',
        'SyncedVersion',
        'SyncedUpdatedAt'
      ])
        key: before[key],
    });
    await context.activeSpreadsheetId();
    expect((await baseline())['SyncedFingerprint'], isNull);
    expect((await baseline())['SyncedVersion'], before['SyncedVersion']);
    remoteRow()['TeacherName'] = 'Manual edit';
    expect((await sync.syncPendingToGoogleSheets()).success, isFalse);
    expect(remote.writes, 0);
  });

  test('pull rechecks a local edit arriving after its comparison', () async {
    remoteRow()['TeacherName'] = 'Remote edit';
    final guarded = AfterComparisonSync(
        database: app,
        sheets: remote,
        context: context,
        afterComparison: () => editLocal('Concurrent local edit'));
    final before = await baseline();
    final result = await guarded.applyRemoteChangesToLocal();
    expect(result.skipped, 1);
    expect((await local())['TeacherName'], 'Concurrent local edit');
    expect(await baseline(), before);
    expect(await sync.getTotalPendingCount(), 1);
  });

  test('Use Remote rechecks a local edit arriving during resolution', () async {
    await editLocal('Local edit');
    remoteRow()['TeacherName'] = 'Remote edit';
    final guarded = AfterComparisonSync(
        database: app,
        sheets: remote,
        context: context,
        afterComparison: () => editLocal('Concurrent local edit'));
    final before = await baseline();
    expect(
        (await guarded.resolveConflictUseRemote(
                tableName: table, syncId: 'teacher-1'))
            .success,
        isFalse);
    expect((await local())['TeacherName'], 'Concurrent local edit');
    expect(await baseline(), before);
  });

  test('failed Use Remote rolls back record and baseline', () async {
    await editLocal('Local edit');
    remoteRow()['TeacherName'] = 'Remote edit';
    final before = await baseline();
    await app.database.execute('''
      CREATE TRIGGER reject_baseline BEFORE INSERT ON SYNC_STATE_Table
      BEGIN SELECT RAISE(ABORT, 'simulated baseline failure'); END
    ''');
    expect(
        (await sync.resolveConflictUseRemote(
                tableName: table, syncId: 'teacher-1'))
            .success,
        isFalse);
    expect((await local())['TeacherName'], 'Local edit');
    expect(await baseline(), before);
  });

  test('child restore fingerprints include stable learner identity', () async {
    for (final id in ['parent-a', 'parent-b']) {
      await app.database.insert(SyncService.learnersTable, {
        'SyncID': id,
        'LastName': id,
        'FirstName': 'Learner',
        'Sex': 'Female',
        'CreatedAt': stamp,
        'UpdatedAt': stamp,
        'Version': 1,
        'DeviceID': 'windows',
        'Deleted': 0,
      });
    }
    final parents = await app.database.query(SyncService.learnersTable);
    for (final childTable in [
      SyncService.schoolHistoryTable,
      SyncService.incidentsTable
    ]) {
      await app.database.insert(childTable, {
        'SyncID': 'child-$childTable',
        'LearnerID': parents.first['LearnerID'],
        'CreatedAt': stamp,
        'UpdatedAt': stamp,
        'Version': 1,
        'DeviceID': 'windows',
        'Deleted': 0,
        if (childTable == SyncService.schoolHistoryTable)
          'SchoolYear': '2026-2027',
        if (childTable == SyncService.schoolHistoryTable) 'Grade': '8',
        if (childTable == SyncService.schoolHistoryTable) 'School': 'School',
        if (childTable == SyncService.incidentsTable)
          'IncidentDate': '2026-01-01',
        if (childTable == SyncService.incidentsTable)
          'BehaviorProblem': 'Observation',
      });
    }
    await seedBaseline();
    remote.records[GoogleSheetsService.learnersSheet] =
        parents.map((r) => Map<String, Object?>.of(r)).toList();
    for (final entry in {
      SyncService.schoolHistoryTable: GoogleSheetsService.schoolHistorySheet,
      SyncService.incidentsTable: GoogleSheetsService.incidentsSheet,
    }.entries) {
      final row = (await app.database.query(entry.key)).single;
      final joined = {...row, 'LearnerSyncID': 'parent-a'};
      final state = (await app.database.query(SyncContextService.stateTable,
              where: 'TableName = ?', whereArgs: [entry.key]))
          .single;
      expect(state['SyncedFingerprint'], SyncRecordState.fingerprint(joined));
      remote.records[entry.value] = [
        {...joined, 'LearnerID': 999}
      ];
    }
    expect((await sync.syncPendingToGoogleSheets()).success, isTrue);
    expect(remote.writes, 0);
    await app.database
        .update(SyncService.schoolHistoryTable, {'School': 'Local school'});
    remote.records[GoogleSheetsService.schoolHistorySheet]!
        .single['LearnerSyncID'] = 'parent-b';
    expect((await sync.syncPendingToGoogleSheets()).success, isFalse);
    expect(remote.writes, 0);
    expect((await sync.compareRemoteWithLocal()).conflictCount, 1);
  });

  test('restore waits for in-flight synchronization before changing ownership',
      () async {
    await editLocal('Local edit');
    final entered = Completer<void>();
    final release = Completer<void>();
    remote.beforeWrite = () async {
      entered.complete();
      await release.future;
    };
    final operation = sync.syncPendingToGoogleSheets();
    await entered.future;
    var restored = false;
    final restore =
        sync.restoreFromSpreadsheet('B').then((_) => restored = true);
    await Future<void>.delayed(Duration.zero);
    expect(restored, isFalse);
    release.complete();
    expect((await operation).success, isTrue);
    await restore;
    expect(await context.activeSpreadsheetId(), 'B');
    expect((await local())['TeacherName'], 'Local edit');
  });
}

class AfterComparisonSync extends SyncService {
  AfterComparisonSync(
      {required super.database,
      required super.sheets,
      required super.context,
      required this.afterComparison})
      : super.forTesting(authenticated: () async => true);
  final Future<void> Function() afterComparison;
  @override
  Future<SyncComparisonResult> compareRemoteWithLocal() async {
    final result = await super.compareRemoteWithLocal();
    await afterComparison();
    return result;
  }
}

/// Uses the production upsert/recheck algorithm, replacing only network I/O.
class MemorySheets extends GoogleSheetsService {
  MemorySheets(this.context) : super.forTesting();
  final SyncContextService context;
  final records = <String, List<Map<String, Object?>>>{
    for (final title in GoogleSheetsService.requiredSheets) title: [],
  };
  static const headersByTitle = {
    GoogleSheetsService.learnersSheet: GoogleSheetsService.learnerHeaders,
    GoogleSheetsService.teachersSheet: GoogleSheetsService.teacherHeaders,
    GoogleSheetsService.sectionsSheet: GoogleSheetsService.sectionHeaders,
    GoogleSheetsService.schoolHistorySheet:
        GoogleSheetsService.schoolHistoryHeaders,
    GoogleSheetsService.incidentsSheet: GoogleSheetsService.incidentHeaders,
  };
  String? activeId;
  int writes = 0;
  bool failWrites = false;
  Future<void> Function()? beforeRead;
  Future<void> Function()? beforeWrite;

  @override
  String? get spreadsheetId => activeId;
  @override
  Future<void> initialize() async {
    activeId = await context.activeSpreadsheetId();
  }

  @override
  Future<sheets.Spreadsheet> validateSpreadsheet(String input) async =>
      sheets.Spreadsheet(spreadsheetId: input);
  @override
  Future<GoogleSheetsDownload> downloadAllTables(
      {String? spreadsheetId}) async {
    List<Map<String, Object?>> copy(String title) =>
        records[title]!.map((r) => Map<String, Object?>.of(r)).toList();
    return GoogleSheetsDownload(
        learners: copy(GoogleSheetsService.learnersSheet),
        teachers: copy(GoogleSheetsService.teachersSheet),
        sections: copy(GoogleSheetsService.sectionsSheet),
        schoolHistory: copy(GoogleSheetsService.schoolHistorySheet),
        incidents: copy(GoogleSheetsService.incidentsSheet));
  }

  @override
  Future<List<List<Object?>>> readRange(
      {required String sheetTitle,
      String range = 'A:ZZ',
      String? spreadsheetId}) async {
    final hook = beforeRead;
    beforeRead = null;
    await hook?.call();
    final headers = headersByTitle[sheetTitle]!;
    return [
      headers,
      for (final row in records[sheetTitle]!)
        [for (final key in headers) row[key]]
    ];
  }

  @override
  Future<void> updateRange(
      {required String sheetTitle,
      required String range,
      required List<List<Object?>> values}) async {
    if (failWrites) throw StateError('Simulated network failure');
    await beforeWrite?.call();
    final index =
        int.parse(RegExp(r'^A(\d+)').firstMatch(range)!.group(1)!) - 2;
    final headers = headersByTitle[sheetTitle]!;
    records[sheetTitle]![index] = {
      for (var i = 0; i < headers.length; i++) headers[i]: values.single[i]
    };
    writes++;
  }

  @override
  Future<void> appendRows(
      {required String sheetTitle, required List<List<Object?>> rows}) async {
    if (failWrites) throw StateError('Simulated network failure');
    await beforeWrite?.call();
    final headers = headersByTitle[sheetTitle]!;
    for (final row in rows) {
      records[sheetTitle]!
          .add({for (var i = 0; i < headers.length; i++) headers[i]: row[i]});
      writes++;
    }
  }
}
