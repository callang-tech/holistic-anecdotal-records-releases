import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:holistic_anecdotal_records/database/app_database.dart';
import 'package:holistic_anecdotal_records/services/sync_context_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const coreTables = [
    'TEACHERS_Table',
    'SECTIONS_Table',
    'LEARNERS_Table',
    'SCHOOL_HISTORY_Table',
    'INCIDENTS_Table',
  ];
  const stamp = '2026-09-20T00:00:00.000Z';
  late Directory directory;
  late AppDatabase app;
  late SyncContextService context;
  late SharedPreferences prefs;

  Map<String, List<Map<String, Object?>>> dataset(String prefix) {
    Map<String, Object?> metadata(String type) => {
          'SyncID': '$prefix-$type',
          'CreatedAt': stamp,
          'UpdatedAt': stamp,
          'DeviceID': 'source-device',
          'Version': 7,
          'Deleted': 0,
        };
    return {
      'TEACHERS_Table': [
        {...metadata('teacher'), 'TeacherName': '$prefix Teacher'}
      ],
      'SECTIONS_Table': [
        {
          ...metadata('section'),
          'SchoolYear': '2026-2027',
          'GradeLevel': '8',
          'SectionName': '$prefix Section',
          'Adviser': '$prefix Teacher'
        }
      ],
      'LEARNERS_Table': [
        {
          ...metadata('learner'),
          'LearnerID': 999,
          'LastName': prefix,
          'FirstName': 'Learner',
          'Sex': 'Female'
        }
      ],
      'SCHOOL_HISTORY_Table': [
        {
          ...metadata('history'),
          'LearnerID': 999,
          'LearnerSyncID': '$prefix-learner',
          'SchoolYear': '2026-2027',
          'Grade': '8',
          'School': '$prefix School'
        }
      ],
      'INCIDENTS_Table': [
        {
          ...metadata('incident'),
          'LearnerID': 999,
          'LearnerSyncID': '$prefix-learner',
          'IncidentDate': '2026-09-20',
          'BehaviorProblem': 'Observation'
        }
      ],
    };
  }

  Future<DatabaseImportResult> replace(
    Map<String, List<Map<String, Object?>>> data, {
    String owner = 'B',
  }) =>
      context.exclusive(() => app.replaceSyncedTables(
            teachers: data['TEACHERS_Table']!,
            sections: data['SECTIONS_Table']!,
            learners: data['LEARNERS_Table']!,
            schoolHistory: data['SCHOOL_HISTORY_Table']!,
            incidents: data['INCIDENTS_Table']!,
            establishSyncState: (txn) =>
                context.replaceImportedStateInTransaction(
              txn,
              spreadsheetId: owner,
            ),
          ));

  Future<Map<String, Object?>> snapshot() async => {
        for (final table in [
          ...coreTables,
          SyncContextService.stateTable,
          SyncContextService.contextTable,
          'sqlite_sequence',
        ])
          table: await app.database.query(table),
        'preferences': {for (final key in prefs.getKeys()) key: prefs.get(key)},
      };

  setUp(() async {
    SharedPreferences.setMockInitialValues({'unrelated_setting': 'keep'});
    prefs = await SharedPreferences.getInstance();
    directory = await Directory.systemTemp.createTemp('holistic_restore_test_');
    app = AppDatabase.forTesting('${directory.path}/test.db');
    await app.initialize();
    // Exercise both deletion and insertion order under actual FK enforcement.
    await app.database.execute('PRAGMA foreign_keys = ON');
    context = SyncContextService(database: () => app.database);
    await replace(dataset('old'), owner: 'A');
    await context.activeSpreadsheetId();
    for (final table in coreTables) {
      for (final prefix in [
        'sync_last_synced_',
        'sync_last_pushed_',
        'sync_last_pulled_'
      ]) {
        await prefs.setString('$prefix$table', stamp);
      }
    }
  });

  tearDown(() async {
    await app.database.close();
    await directory.delete(recursive: true);
  });

  test(
      'normal A to B restore commits all records, baselines and owner together',
      () async {
    final result = await replace(dataset('new'));
    expect(result.total, 5);
    final learner = (await app.database.query('LEARNERS_Table')).single;
    expect(learner['SyncID'], 'new-learner');
    expect(learner['LearnerID'], isNot(999));
    for (final table in ['SCHOOL_HISTORY_Table', 'INCIDENTS_Table']) {
      final row = (await app.database.query(table)).single;
      expect(row['LearnerID'], learner['LearnerID']);
    }
    final baselines = await app.database.query(SyncContextService.stateTable);
    expect(baselines, hasLength(5));
    for (final state in baselines) {
      expect(state['SyncID'], startsWith('new-'));
      expect(state['SyncedVersion'], 7);
      expect(state['SyncedUpdatedAt'], stamp);
    }
    final owner =
        (await app.database.query(SyncContextService.contextTable)).single;
    expect(owner['SpreadsheetID'], 'B');
    expect(owner['PreferencesPending'], 1);
    // Preference writes have not happened inside the transaction.
    expect(prefs.getString(SyncContextService.spreadsheetIdKey), 'A');
    expect(await context.activeSpreadsheetId(), 'B');
    expect(prefs.getString(SyncContextService.spreadsheetIdKey), 'B');
    expect(prefs.getString('unrelated_setting'), 'keep');
    expect(await app.database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });

  test(
      'missing required import field rolls back records, baselines and A owner',
      () async {
    final before = await snapshot();
    final data = dataset('new');
    data['LEARNERS_Table']!.single.remove('LastName');
    await expectLater(replace(data), throwsStateError);
    expect(await snapshot(), before);
  });

  test('duplicate SyncID rolls back the complete replacement', () async {
    final before = await snapshot();
    final data = dataset('new');
    data['LEARNERS_Table']!.add(Map.of(data['LEARNERS_Table']!.single));
    await expectLater(replace(data), throwsA(isA<DatabaseException>()));
    expect(await snapshot(), before);
  });

  for (final table in ['SCHOOL_HISTORY_Table', 'INCIDENTS_Table']) {
    for (final badSyncId in ['', 'missing-learner']) {
      test(
          '$table rejects LearnerSyncID "$badSyncId" even with a numeric LearnerID',
          () async {
        final before = await snapshot();
        final oldLearner = (await app.database.query('LEARNERS_Table')).single;
        final data = dataset('new');
        data[table]!.single['LearnerSyncID'] = badSyncId;
        data[table]!.single['LearnerID'] = oldLearner['LearnerID'];
        await expectLater(replace(data), throwsStateError);
        expect(await snapshot(), before);
      });
    }
  }

  test('missing record SyncID cannot silently generate a different identity',
      () async {
    final before = await snapshot();
    final data = dataset('new');
    data['TEACHERS_Table']!.single['SyncID'] = '';
    await expectLater(replace(data), throwsStateError);
    expect(await snapshot(), before);
  });

  test(
      'valid empty restore removes data and baselines without fabricated watermarks',
      () async {
    final result = await replace({for (final table in coreTables) table: []});
    expect(result.total, 0);
    for (final table in [...coreTables, SyncContextService.stateTable]) {
      expect(await app.database.query(table), isEmpty);
    }
    expect(await context.activeSpreadsheetId(), 'B');
    expect(
        prefs.getKeys().where((key) =>
            key.startsWith('sync_last_synced_') ||
            key.startsWith('sync_last_pushed_') ||
            key.startsWith('sync_last_pulled_')),
        isEmpty);
  });

  test('baseline write failure rolls back core import and ownership', () async {
    final before = await snapshot();
    await app.database.execute('''
      CREATE TRIGGER reject_baseline BEFORE INSERT ON SYNC_STATE_Table
      WHEN NEW.SyncID = 'new-incident'
      BEGIN SELECT RAISE(ABORT, 'simulated baseline failure'); END
    ''');
    await expectLater(
        replace(dataset('new')), throwsA(isA<DatabaseException>()));
    expect(await snapshot(), before);
  });

  test('ownership write failure rolls back core import and new baselines',
      () async {
    final before = await snapshot();
    await app.database.execute('''
      CREATE TRIGGER reject_owner BEFORE INSERT ON SYNC_CONTEXT_Table
      WHEN NEW.SpreadsheetID = 'B'
      BEGIN SELECT RAISE(ABORT, 'simulated ownership failure'); END
    ''');
    await expectLater(
        replace(dataset('new')), throwsA(isA<DatabaseException>()));
    expect(await snapshot(), before);
  });

  test('restore to the same A replaces its old baseline set', () async {
    await replace(dataset('new'), owner: 'A');
    expect(await context.activeSpreadsheetId(), 'A');
    final baselines = await app.database.query(SyncContextService.stateTable);
    expect(baselines, hasLength(5));
    expect(
        baselines.every((row) => row['SyncID'].toString().startsWith('new-')),
        isTrue);
  });

  test('committed restore recovers mirror after close and reopen', () async {
    await replace(dataset('new'));
    final path = app.database.path;
    await app.database.close();
    app = AppDatabase.forTesting(path);
    await app.initialize();
    context = SyncContextService(database: () => app.database);
    expect(prefs.getString(SyncContextService.spreadsheetIdKey), 'A');
    expect(await context.activeSpreadsheetId(), 'B');
    expect(
        await app.database.query(SyncContextService.stateTable), hasLength(5));
    expect((await app.database.query('LEARNERS_Table')).single['SyncID'],
        'new-learner');
  });

  test('failed preference mirror write leaves committed B intact and retries',
      () async {
    final failing = _FailingPreferences(prefs);
    context = SyncContextService(
      database: () => app.database,
      preferences: () async => failing,
    );
    await replace(dataset('new'));
    await expectLater(context.activeSpreadsheetId(), throwsStateError);
    final owner =
        (await app.database.query(SyncContextService.contextTable)).single;
    expect(owner['SpreadsheetID'], 'B');
    expect(owner['PreferencesPending'], 1);
    expect(prefs.getString(SyncContextService.spreadsheetIdKey), 'A');
    expect(
        await app.database.query(SyncContextService.stateTable), hasLength(5));
    expect((await app.database.query('LEARNERS_Table')).single['SyncID'],
        'new-learner');
    failing.failWrites = false;
    expect(await context.activeSpreadsheetId(), 'B');
    expect(prefs.getString(SyncContextService.spreadsheetIdKey), 'B');
    expect(
        (await app.database.query(SyncContextService.contextTable))
            .single['PreferencesPending'],
        0);
  });

  test(
      'Start Fresh still resets data independently and keeps configured spreadsheet',
      () async {
    await app.resetDatabase();
    await context.clear();
    for (final table in [...coreTables, SyncContextService.stateTable]) {
      expect(await app.database.query(table), isEmpty);
    }
    expect(await context.activeSpreadsheetId(), 'A');
    expect(prefs.getString('unrelated_setting'), 'keep');
  });
}

class _FailingPreferences extends Fake implements SharedPreferences {
  _FailingPreferences(this.delegate);
  final SharedPreferences delegate;
  bool failWrites = true;

  @override
  bool containsKey(String key) => delegate.containsKey(key);
  @override
  String? getString(String key) => delegate.getString(key);
  @override
  Future<bool> remove(String key) => delegate.remove(key);
  @override
  Future<bool> setInt(String key, int value) => delegate.setInt(key, value);
  @override
  Future<bool> setString(String key, String value) async {
    if (failWrites && key == SyncContextService.spreadsheetIdKey) return false;
    return delegate.setString(key, value);
  }
}
