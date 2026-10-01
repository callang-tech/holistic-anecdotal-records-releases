import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:holistic_anecdotal_records/database/app_database.dart';
import 'package:holistic_anecdotal_records/models/sync_record_state.dart';
import 'package:holistic_anecdotal_records/services/google_sheets_service.dart';
import 'package:holistic_anecdotal_records/services/sync_context_service.dart';
import 'package:holistic_anecdotal_records/services/sync_service.dart';

import 'conflict_safe_sync_test.dart' show MemorySheets;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late AppDatabase app;
  late SyncContextService context;
  late MigrationSheets remote;
  late SyncService sync;
  late SharedPreferences prefs;
  const stamp = '2026-01-01T00:00:00.000Z';
  const teacherTable = SyncService.teachersTable;
  const teacherSheet = GoogleSheetsService.teachersSheet;
  final watermarks = [
    for (final table in SyncService.syncTables)
      for (final prefix in [
        'sync_last_synced_',
        'sync_last_pushed_',
        'sync_last_pulled_'
      ])
        '$prefix$table',
  ];

  Future<Map<String, Object?>> coreSnapshot() async => {
        for (final table in [...SyncService.syncTables, 'sqlite_sequence'])
          table: await app.database.query(table),
      };
  Future<Map<String, Object?>> legacySnapshot() async => {
        'core': await coreSnapshot(),
        'schema': await app.database
            .rawQuery('SELECT name, sql FROM sqlite_master ORDER BY name'),
        'states': await app.database.query(SyncContextService.stateTable),
        'preferences': {for (final key in prefs.getKeys()) key: prefs.get(key)},
      };
  Future<LegacyReconnectResult> reconnect() =>
      sync.reconnectCurrentSpreadsheet(expectedSpreadsheetId: 'A');

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      SyncContextService.spreadsheetIdKey: 'A',
      'unrelated_setting': 'keep',
      'sync_last_conflict_count': 12,
      for (final key in watermarks) key: stamp,
    });
    prefs = await SharedPreferences.getInstance();
    directory = await Directory.systemTemp.createTemp('legacy_reconnect_');
    app = AppDatabase.forTesting('${directory.path}/test.db');
    await app.initialize();
    Map<String, Object?> metadata(String id) => {
          'SyncID': id,
          'CreatedAt': stamp,
          'UpdatedAt': stamp,
          'DeviceID': 'windows',
          'Version': 1,
          'Deleted': 0,
        };
    await app.importSyncedTables(
      teachers: [
        {...metadata('teacher'), 'TeacherName': 'Teacher'}
      ],
      sections: [
        {
          ...metadata('section'),
          'SchoolYear': '2026',
          'GradeLevel': '8',
          'SectionName': 'Section',
          'Adviser': 'Teacher'
        }
      ],
      learners: [
        {
          ...metadata('learner'),
          'LastName': 'Learner',
          'FirstName': 'First',
          'Sex': 'Female'
        }
      ],
      schoolHistory: [
        {
          ...metadata('history'),
          'LearnerSyncID': 'learner',
          'SchoolYear': '2026',
          'Grade': '8',
          'School': 'School'
        }
      ],
      incidents: [
        {
          ...metadata('incident'),
          'LearnerSyncID': 'learner',
          'IncidentDate': '2026-01-01',
          'BehaviorProblem': 'Observation'
        }
      ],
    );
    // Actual pre-ownership schema: neither fingerprint columns nor context table.
    await app.database.execute('''CREATE TABLE SYNC_STATE_Table (
      TableName TEXT NOT NULL, SyncID TEXT NOT NULL,
      SyncedVersion INTEGER NOT NULL DEFAULT 1,
      SyncedUpdatedAt TEXT NOT NULL DEFAULT '', PRIMARY KEY(TableName, SyncID))''');
    await app.database.insert(SyncContextService.stateTable, {
      'TableName': teacherTable,
      'SyncID': 'legacy-stale',
      'SyncedVersion': 9,
      'SyncedUpdatedAt': stamp,
    });
    context = SyncContextService(database: () => app.database);
    remote = MigrationSheets(context);
    sync = SyncService.forTesting(
        database: app,
        sheets: remote,
        context: context,
        authenticated: () async => true);
  });

  tearDown(() async {
    expect(remote.writes, 0,
        reason: 'Reconnect must never write remote records.');
    await app.database.close();
    await directory.delete(recursive: true);
  });

  test('detects legacy state without changing schema, baselines or preferences',
      () async {
    final before = await legacySnapshot();
    expect(await sync.legacyUnownedSpreadsheetId(), 'A');
    expect(await legacySnapshot(), before);
  });

  test('reconnect preserves all five tables, removes old tracking and owns A',
      () async {
    final before = await coreSnapshot();
    expect(await sync.legacyUnownedSpreadsheetId(), 'A');
    final result = await reconnect();
    expect(remote.validations, ['A']);
    expect(result.comparison, isNotNull);
    expect(result.comparisonError, isNull);
    expect(await coreSnapshot(), before);
    expect(await app.database.query(SyncContextService.stateTable), isEmpty);
    expect(watermarks.where(prefs.containsKey), isEmpty);
    expect(prefs.getInt('sync_last_conflict_count'), 0);
    expect(prefs.getString('unrelated_setting'), 'keep');
    final owner =
        (await app.database.query(SyncContextService.contextTable)).single;
    expect(owner['SpreadsheetID'], 'A');
    expect(owner['PreferencesPending'], 0);
    await context.verifyOwner('A');
    expect(await sync.legacyUnownedSpreadsheetId(), isNull);
    expect(remote.records.values.every((rows) => rows.isEmpty), isTrue);
  });

  test('equivalent local and remote records establish fresh baseline only',
      () async {
    final local = (await app.database.query(teacherTable)).single;
    remote.records[teacherSheet] = [
      {...local, 'TeacherName': ' TEACHER ', 'TeacherID': 900}
    ];
    final before = await coreSnapshot();
    final result = await reconnect();
    expect(result.comparison!.sameCount, 1);
    final state =
        (await app.database.query(SyncContextService.stateTable)).single;
    expect(state['SyncID'], 'teacher');
    expect(state['SyncedFingerprint'], SyncRecordState.fingerprint(local));
    expect(await coreSnapshot(), before);
    expect(remote.records[teacherSheet]!.single['TeacherName'], ' TEACHER ');
  });

  test('different records on both sides become conflicts without transfer',
      () async {
    final local = (await app.database.query(teacherTable)).single;
    remote.records[teacherSheet] = [
      {...local, 'TeacherName': 'Remote teacher', 'Version': 99}
    ];
    final before = await coreSnapshot();
    final result = await reconnect();
    expect(result.comparison!.conflictCount, 1);
    expect(await app.database.query(SyncContextService.stateTable), isEmpty);
    expect(await coreSnapshot(), before);
    expect(
        remote.records[teacherSheet]!.single['TeacherName'], 'Remote teacher');
    expect(await sync.getTotalPendingCount(), 5);
  });

  test('local-only records are neither uploaded nor interpreted as deletions',
      () async {
    final before = await coreSnapshot();
    final result = await reconnect();
    expect(result.comparison!.localOnlyCount, 5);
    expect(result.comparison!.conflictCount, 0);
    expect(await coreSnapshot(), before);
    expect(remote.records.values.every((rows) => rows.isEmpty), isTrue);
  });

  test('remote-only record remains remote and is not imported or deleted',
      () async {
    remote.records[teacherSheet] = [
      {'SyncID': 'remote-only', 'TeacherName': 'Remote'}
    ];
    final before = await coreSnapshot();
    final result = await reconnect();
    expect(result.comparison!.newRemoteCount, 1);
    expect(await coreSnapshot(), before);
    expect(remote.records[teacherSheet]!.single['SyncID'], 'remote-only');
  });

  test('validation failure leaves original legacy schema and data untouched',
      () async {
    remote.failValidation = true;
    final before = await legacySnapshot();
    await expectLater(reconnect(), throwsStateError);
    expect(await legacySnapshot(), before);
    expect(remote.downloads, 0);
  });

  test(
      'already-owned installation needs no migration and cannot be reset by it',
      () async {
    await context.activate('A');
    await app.database.insert(SyncContextService.stateTable, {
      'TableName': teacherTable,
      'SyncID': 'owned-state',
      'SyncedVersion': 4,
    });
    final before = await legacySnapshot();
    expect(await sync.legacyUnownedSpreadsheetId(), isNull);
    await expectLater(reconnect(), throwsStateError);
    expect(await legacySnapshot(), before);
    expect(remote.validations, isEmpty);
  });

  test('preference-watermark-only legacy installation can reconnect', () async {
    await app.database.execute('DROP TABLE SYNC_STATE_Table');
    expect(await sync.legacyUnownedSpreadsheetId(), 'A');
    expect((await reconnect()).comparison, isNotNull);
    expect(await context.activeSpreadsheetId(), 'A');
  });

  test('installation with no legacy tracking does not need migration',
      () async {
    await app.database.delete(SyncContextService.stateTable);
    for (final key in watermarks) {
      await prefs.remove(key);
    }
    expect(await sync.legacyUnownedSpreadsheetId(), isNull);
    await expectLater(reconnect(), throwsStateError);
    expect(remote.validations, isEmpty);
  });

  test('confirmed target mismatch does not validate or change metadata',
      () async {
    final before = await legacySnapshot();
    await expectLater(
        sync.reconnectCurrentSpreadsheet(expectedSpreadsheetId: 'B'),
        throwsStateError);
    expect(await legacySnapshot(), before);
    expect(remote.validations, isEmpty);
  });

  test('target change during validation is rechecked before activation',
      () async {
    remote.duringValidation = () async {
      await prefs.setString(SyncContextService.spreadsheetIdKey, 'B');
    };
    final before = await app.database.query(SyncContextService.stateTable);
    await expectLater(reconnect(), throwsStateError);
    expect(await app.database.query(SyncContextService.stateTable), before);
    expect(watermarks.every(prefs.containsKey), isTrue);
    expect(await sync.legacyUnownedSpreadsheetId(), 'B');
  });

  test('comparison failure reports completed activation without data transfer',
      () async {
    final before = await coreSnapshot();
    remote.failDownload = true;
    final result = await reconnect();
    expect(result.comparison, isNull);
    expect(result.comparisonError, contains('Simulated download failure'));
    expect(await context.activeSpreadsheetId(), 'A');
    expect(await coreSnapshot(), before);
    expect(await app.database.query(SyncContextService.stateTable), isEmpty);
    remote.failDownload = false;
    expect((await sync.compareRemoteWithLocal()).localOnlyCount, 5);
  });

  test('target switching waits until reconnect and comparison finish',
      () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    remote.duringValidation = () async {
      entered.complete();
      await release.future;
    };
    final operation = reconnect();
    await entered.future;
    var switched = false;
    final switching = context.activate('B').then((_) => switched = true);
    await Future<void>.delayed(Duration.zero);
    expect(switched, isFalse);
    release.complete();
    expect((await operation).comparison, isNotNull);
    await switching;
    expect(await context.activeSpreadsheetId(), 'B');
  });
}

class MigrationSheets extends MemorySheets {
  MigrationSheets(super.context);
  final validations = <String>[];
  int downloads = 0;
  bool failValidation = false;
  bool failDownload = false;
  Future<void> Function()? duringValidation;

  @override
  Future<sheets.Spreadsheet> validateSpreadsheet(String input) async {
    validations.add(input);
    await duringValidation?.call();
    if (failValidation) throw StateError('Simulated validation failure');
    return sheets.Spreadsheet(spreadsheetId: input);
  }

  @override
  Future<GoogleSheetsDownload> downloadAllTables(
      {String? spreadsheetId}) async {
    downloads++;
    if (failDownload) throw StateError('Simulated download failure');
    return super.downloadAllTables(spreadsheetId: spreadsheetId);
  }
}
