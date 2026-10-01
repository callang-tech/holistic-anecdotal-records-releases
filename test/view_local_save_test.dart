import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:holistic_anecdotal_records/database/app_database.dart';
import 'package:holistic_anecdotal_records/models/sync_record_state.dart';
import 'package:holistic_anecdotal_records/services/google_sheets_service.dart';
import 'package:holistic_anecdotal_records/services/sync_context_service.dart';
import 'package:holistic_anecdotal_records/services/sync_service.dart';

import 'conflict_safe_sync_test.dart' show MemorySheets;
import 'package:holistic_anecdotal_records/services/post_save_sync.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('all ten ViewScreen handlers use upload-only post-save helper', () {
    final source = File('lib/screens/view_screen.dart').readAsStringSync();
    expect(
        RegExp(r'await _autoSyncAfterLocalChange\(\)')
            .allMatches(source)
            .length,
        10);
    expect(source, contains('attemptPostSaveUpload('));
    expect(source, contains('SyncService.instance.syncPendingToGoogleSheets'));
    expect(source, isNot(contains('applyRemoteChangesToLocal')));
  });

  group('local learner save followed by automatic upload', () {
    const table = SyncService.learnersTable;
    const title = GoogleSheetsService.learnersSheet;
    const id = 'test-learner';
    late Directory directory;
    late AppDatabase app;
    late SyncService sync;
    late MemorySheets remote;
    late bool inMemory;
    late bool savedCredentials;
    late bool restorationThrows;
    late List<String> authEvents;

    Future<Map<String, Object?>> local() async =>
        (await app.database.query(table)).single;
    Future<Map<String, Object?>> baseline() async =>
        (await app.database.query(SyncContextService.stateTable)).single;
    Map<String, Object?> remoteRow() => remote.records[title]!.single;

    // Model the SQLite write made by Save, including its normal revision
    // metadata. The UI-boundary test verifies the post-save upload wiring.
    Future<void> saveLocal() async {
      await app.database.update(
          table,
          {
            'NotesDetails': 'LOCAL TEST',
            'Version': 2,
            'UpdatedAt': '2026-09-21T02:00:00.000Z',
          },
          where: 'SyncID = ?',
          whereArgs: [id]);
    }

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      inMemory = false;
      savedCredentials = true;
      restorationThrows = false;
      authEvents = [];
      directory = await Directory.systemTemp.createTemp('view_local_save_');
      app = AppDatabase.forTesting('${directory.path}/test.db');
      await app.initialize();
      final context = SyncContextService(database: () => app.database);
      await context.activate('A');
      await app.database.insert(table, {
        'SyncID': id,
        'FirstName': 'Juan',
        'LastName': 'Test',
        'Sex': 'Male',
        'NotesDetails': 'BASELINE',
        'CreatedAt': '2026-09-20T00:00:00.000Z',
        'UpdatedAt': '2026-09-20T00:00:00.000Z',
        'DeviceID': 'windows',
        'Version': 1,
        'Deleted': 0,
      });
      await context.exclusive(() => app.database.transaction((txn) =>
          context.replaceImportedStateInTransaction(txn, spreadsheetId: 'A')));
      await context.activeSpreadsheetId();
      remote = MemorySheets(context);
      remote.records[title] = [Map.of(await local())];
      sync = SyncService.forTesting(
          database: app,
          sheets: remote,
          context: context,
          hasCredentials: () {
            authEvents.add('check memory');
            return inMemory;
          },
          restoreCredentials: () async {
            authEvents.add('silent sign-in');
            if (restorationThrows) {
              throw StateError('credential restoration failed');
            }
            inMemory = savedCredentials;
            return inMemory;
          },
          authenticated: () async {
            authEvents.add('authenticated client');
            // Fail if production orchestration asks for a client too early.
            expect(inMemory, isTrue);
            return inMemory;
          });
    });

    tearDown(() async {
      await app.database.close();
      await directory.delete(recursive: true);
    });

    test('cold start restores saved credentials before automatic upload',
        () async {
      final originalBaseline = await baseline();
      final originalRemote = Map.of(remoteRow());
      await saveLocal();
      expect((await local())['Version'], 2);
      expect((await local())['UpdatedAt'], '2026-09-21T02:00:00.000Z');
      expect(await sync.getTotalPendingCount(), 1);
      expect(remote.writes, 0);
      expect(remoteRow(), originalRemote);
      expect(await baseline(), originalBaseline);

      expect(await attemptPostSaveUpload(sync.syncPendingToGoogleSheets),
          'Saved and synchronized.');
      expect(authEvents,
          ['check memory', 'silent sign-in', 'authenticated client']);
      expect(remote.writes, 1);
      expect(remoteRow()['NotesDetails'], 'LOCAL TEST');
      expect((await baseline())['SyncedFingerprint'],
          SyncRecordState.fingerprint(await local()));
      expect(await sync.getTotalPendingCount(), 0);
    });

    test('already authenticated skips silent sign-in', () async {
      inMemory = true;
      await saveLocal();
      expect(await attemptPostSaveUpload(sync.syncPendingToGoogleSheets),
          'Saved and synchronized.');
      expect(authEvents, ['check memory', 'authenticated client']);
      expect(remoteRow()['NotesDetails'], 'LOCAL TEST');
    });

    for (final throwsOnRestore in [false, true]) {
      test(
          throwsOnRestore
              ? 'silent sign-in failure preserves saved data and baseline'
              : 'no saved credentials preserves saved data and baseline',
          () async {
        savedCredentials = false;
        restorationThrows = throwsOnRestore;
        final before = await baseline();
        final beforeRemote = Map.of(remoteRow());
        await saveLocal();
        final message =
            await attemptPostSaveUpload(sync.syncPendingToGoogleSheets);
        expect(message, contains('Saved locally'));
        expect(message, contains('Please sign in with Google first'));
        expect(authEvents, ['check memory', 'silent sign-in']);
        expect((await local())['NotesDetails'], 'LOCAL TEST');
        expect(await baseline(), before);
        expect(remoteRow(), beforeRemote);
        expect(remote.writes, 0);
        expect(await sync.getTotalPendingCount(), 1);
      });
    }

    test('upload unavailable preserves successful local save and baseline',
        () async {
      final before = await baseline();
      await saveLocal();
      remote.failWrites = true;
      final message =
          await attemptPostSaveUpload(sync.syncPendingToGoogleSheets);
      expect(message, contains('Saved locally'));
      expect(message, contains('synchronization pending'));
      expect((await local())['NotesDetails'], 'LOCAL TEST');
      expect(remoteRow()['NotesDetails'], 'BASELINE');
      expect(await baseline(), before);
      expect(await sync.getTotalPendingCount(), 1);
    });

    test(
        'remote-only divergence is detected but never applied by automatic upload',
        () async {
      final before = await baseline();
      final original = await local();
      remoteRow()['NotesDetails'] = 'REMOTE TEST';
      final message =
          await attemptPostSaveUpload(sync.syncPendingToGoogleSheets);
      expect(message, contains('Remote changes require Download/Apply'));
      expect(authEvents,
          ['check memory', 'silent sign-in', 'authenticated client']);
      expect(await local(), original);
      expect(remote.writes, 0);
      expect(
          (await baseline())['SyncedFingerprint'], before['SyncedFingerprint']);
    });

    test('timeout reports ongoing sync and permits eventual successful upload',
        () async {
      await saveLocal();
      final entered = Completer<void>();
      final release = Completer<void>();
      final finished = Completer<void>();
      remote.beforeWrite = () async {
        entered.complete();
        await release.future;
      };
      final messageFuture = attemptPostSaveUpload(() async {
        try {
          return await sync.syncPendingToGoogleSheets();
        } finally {
          finished.complete();
        }
      }, waitLimit: const Duration(milliseconds: 50));
      await entered.future;
      final message = await messageFuture;
      expect(message, contains('Saved locally'));
      expect(message, contains('may still be running'));
      expect(message, contains('was not cancelled'));
      expect((await local())['NotesDetails'], 'LOCAL TEST');
      expect(remote.writes, 0);
      release.complete();
      await finished.future;
      expect(remoteRow()['NotesDetails'], 'LOCAL TEST');
      expect(await sync.getTotalPendingCount(), 0);
    });

    test('thrown upload failure cannot turn a local save into a failure',
        () async {
      await saveLocal();
      final message =
          await attemptPostSaveUpload(() async => throw StateError('offline'));
      expect(message, contains('Saved locally'));
      expect(message, contains('unavailable or failed'));
      expect((await local())['NotesDetails'], 'LOCAL TEST');
      expect(await sync.getTotalPendingCount(), 1);
    });

    test('independent remote edit requires explicit conflict resolution',
        () async {
      final originalBaseline = await baseline();
      final originalRemote = Map.of(remoteRow());
      await saveLocal();
      expect(remoteRow(), originalRemote);
      expect(remote.writes, 0);
      expect(await baseline(), originalBaseline);
      expect(await sync.getTotalPendingCount(), 1);

      // Manual Sheet edit deliberately leaves Version/UpdatedAt unchanged.
      remoteRow()['NotesDetails'] = 'REMOTE TEST';
      final editedRemote = Map.of(remoteRow());
      final editedLocal = await local();
      final message =
          await attemptPostSaveUpload(sync.syncPendingToGoogleSheets);
      expect(message, contains('Saved locally'));
      expect(message, contains('conflict review required'));
      expect(authEvents,
          ['check memory', 'silent sign-in', 'authenticated client']);
      expect((await sync.compareRemoteWithLocal()).conflictCount, 1);
      final applied = await sync.applyRemoteChangesToLocal();
      expect(applied.conflicts, 1);
      expect(await local(), editedLocal);
      expect(remoteRow(), editedRemote);
      expect(remote.writes, 0);
      final unresolved = await baseline();
      for (final field in [
        'SyncedFingerprint',
        'SyncedVersion',
        'SyncedUpdatedAt'
      ]) {
        expect(unresolved[field], originalBaseline[field]);
      }
      expect(unresolved['NeedsReview'], 1);
      expect(await sync.getTotalPendingCount(), 1);

      // Only an explicit choice is allowed to replace L with R.
      expect(
          (await sync.resolveConflictUseRemote(tableName: table, syncId: id))
              .success,
          isTrue);
      expect((await local())['NotesDetails'], 'REMOTE TEST');
      expect(remoteRow(), editedRemote);
      expect((await sync.compareRemoteWithLocal()).conflictCount, 0);
      expect(await sync.getTotalPendingCount(), 0);
    });
  });
}
