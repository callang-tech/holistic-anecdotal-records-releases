import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:holistic_anecdotal_records/services/sync_context_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Database db;
  late SyncContextService context;
  late SharedPreferences prefs;
  const legacy = 'sync_last_synced_LEARNERS_Table';
  const pushed = 'sync_last_pushed_LEARNERS_Table';
  const pulled = 'sync_last_pulled_LEARNERS_Table';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    context = SyncContextService(database: () => db);
    await context.activeSpreadsheetId();
    await db.execute(
        'CREATE TABLE UserRecords (ID INTEGER PRIMARY KEY, Value TEXT)');
    await db.insert('UserRecords', {'ID': 1, 'Value': 'Keep me'});
  });

  tearDown(() async {
    expect(await db.query('UserRecords'), [
      {'ID': 1, 'Value': 'Keep me'}
    ]);
    await db.close();
  });

  Future<void> seedState() async {
    await db.insert(SyncContextService.stateTable, {
      'TableName': 'LEARNERS_Table',
      'SyncID': 'learner-1',
      'SyncedVersion': 4,
      'SyncedUpdatedAt': '2026-09-20T00:00:00Z',
    });
    for (final key in [legacy, pushed, pulled]) {
      await prefs.setString(key, '2026-09-20T00:00:00Z');
    }
    await prefs.setInt('sync_last_conflict_count', 2);
    await prefs.setString('unrelated_setting', 'preserve');
  }

  Future<void> expectCleared(String? owner) async {
    expect(await context.activeSpreadsheetId(), owner);
    expect(await db.query(SyncContextService.stateTable), isEmpty);
    for (final key in [legacy, pushed, pulled]) {
      expect(prefs.containsKey(key), isFalse);
    }
    expect(prefs.getInt('sync_last_conflict_count'), 0);
    expect(prefs.getString(SyncContextService.spreadsheetIdKey), owner);
    expect(prefs.getString('unrelated_setting'), 'preserve');
  }

  test('first synchronization claims A only when there is no legacy state',
      () async {
    await prefs.setString(SyncContextService.spreadsheetIdKey, 'A');
    await context.verifyOwner(await context.activeSpreadsheetId());
    final rows = await db.query(SyncContextService.contextTable);
    expect(rows.single['SpreadsheetID'], 'A');
    expect(await db.query(SyncContextService.stateTable), isEmpty);
  });

  test('reconnecting to A preserves baselines and watermarks', () async {
    await context.activate('A');
    await seedState();
    final original = await db.query(SyncContextService.stateTable);
    await context.activate(' A ');
    await context.verifyOwner('A');
    expect(await db.query(SyncContextService.stateTable), original);
    for (final key in [legacy, pushed, pulled]) {
      expect(prefs.getString(key), '2026-09-20T00:00:00Z');
    }
    expect(prefs.getInt('sync_last_conflict_count'), 2);
  });

  test('switching A to B clears only sync state', () async {
    await context.activate('A');
    await seedState();
    await context.activate('B');
    await context.verifyOwner('B');
    await expectCleared('B');
    await expectLater(context.verifyOwner('A'), throwsStateError);
  });

  test('unowned legacy baselines block automatic use until explicit activation',
      () async {
    await prefs.setString(SyncContextService.spreadsheetIdKey, 'A');
    await seedState();
    expect(await context.activeSpreadsheetId(), 'A');
    await expectLater(context.verifyOwner('A'), throwsStateError);
    expect(await db.query(SyncContextService.contextTable), isEmpty);
    expect(await db.query(SyncContextService.stateTable), hasLength(1));
    expect(prefs.getString(legacy), isNotNull);
    await context.activate('A');
    await expectCleared('A');
  });

  test('legacy preference-only watermarks also block automatic adoption',
      () async {
    await prefs.setString(legacy, 'old');
    await expectLater(context.verifyOwner('A'), throwsStateError);
    expect(await db.query(SyncContextService.contextTable), isEmpty);
  });

  test('clear removes SQLite and preference state while retaining owner',
      () async {
    await context.activate('A');
    await seedState();
    await context.clear();
    await expectCleared('A');
  });

  test(
      'SQLite owner repairs a stale preference mirror without losing baselines',
      () async {
    await context.activate('A');
    await seedState();
    await prefs.setString(SyncContextService.spreadsheetIdKey, 'B');
    final restarted = SyncContextService(database: () => db);
    expect(await restarted.activeSpreadsheetId(), 'A');
    expect(prefs.getString(SyncContextService.spreadsheetIdKey), 'A');
    expect(await db.query(SyncContextService.stateTable), hasLength(1));
    expect(prefs.getString(legacy), isNull);
  });

  test('failed ownership commit rolls back baseline deletion', () async {
    await context.activate('A');
    await seedState();
    await db.execute('''
      CREATE TRIGGER reject_b BEFORE INSERT ON SYNC_CONTEXT_Table
      WHEN NEW.SpreadsheetID = 'B'
      BEGIN SELECT RAISE(ABORT, 'simulated activation failure'); END
    ''');
    await expectLater(context.activate('B'), throwsA(isA<DatabaseException>()));
    expect(await context.activeSpreadsheetId(), 'A');
    expect(await db.query(SyncContextService.stateTable), hasLength(1));
    expect(prefs.getString(legacy), isNotNull);
  });

  test('interrupted activation completes preference cleanup on restart',
      () async {
    await context.activate('A');
    await seedState();
    // Simulate process exit after the SQLite commit, before preference writes.
    await db.transaction((txn) async {
      await txn.delete(SyncContextService.stateTable);
      await txn.update(
          SyncContextService.contextTable,
          {
            'SpreadsheetID': 'B',
            'PreferencesPending': 1,
          },
          where: 'ID = 1');
    });
    context = SyncContextService(database: () => db);
    await expectCleared('B');
    final rows = await db.query(SyncContextService.contextTable);
    expect(rows.single['PreferencesPending'], 0);
  });

  test('activation waits until an in-flight synchronization finishes',
      () async {
    await context.activate('A');
    final entered = Completer<void>();
    final release = Completer<void>();
    final operation = context.exclusive(() async {
      await context.verifyOwner('A'); // Nested calls must not deadlock.
      entered.complete();
      await release.future;
      await context.verifyOwner('A');
    });
    await entered.future;
    var switched = false;
    final activation = context.activate('B').then((_) => switched = true);
    await Future<void>.delayed(Duration.zero);
    expect(switched, isFalse);
    release.complete();
    await operation;
    await activation;
    expect(await context.activeSpreadsheetId(), 'B');
  });

  test('failed operation releases the activation guard', () async {
    await expectLater(context.exclusive<void>(() async {
      throw StateError('simulated failure');
    }), throwsStateError);
    await context.activate('B');
    await context.verifyOwner('B');
  });
}
