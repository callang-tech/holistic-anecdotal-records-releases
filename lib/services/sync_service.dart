import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../database/app_database.dart';
import '../models/sync_apply_result.dart';
import '../models/sync_comparison.dart';
import '../models/sync_result.dart';
import '../models/sync_record_state.dart';
import 'google_auth_service.dart';
import 'google_sheets_service.dart';
import 'sync_context_service.dart';

enum _ApplyAction {
  inserted,
  updated,
  deleted,
  skipped,
}

class SyncService {
  SyncService._()
      : _database = AppDatabase.instance,
        _sheets = GoogleSheetsService.instance,
        _context = SyncContextService.instance,
        _authenticated = null,
        _hasCredentials = null,
        _restoreCredentials = null;

  @visibleForTesting
  SyncService.forTesting({
    required AppDatabase database,
    required GoogleSheetsService sheets,
    required SyncContextService context,
    required Future<bool> Function() authenticated,
    bool Function()? hasCredentials,
    Future<bool> Function()? restoreCredentials,
  })  : _database = database,
        _sheets = sheets,
        _context = context,
        _authenticated = authenticated,
        _hasCredentials = hasCredentials,
        _restoreCredentials = restoreCredentials;

  static final SyncService instance = SyncService._();

  final AppDatabase _database;

  final GoogleAuthService _auth = GoogleAuthService.instance;

  final GoogleSheetsService _sheets;

  static const String learnersTable = 'LEARNERS_Table';

  static const String teachersTable = 'TEACHERS_Table';

  static const String sectionsTable = 'SECTIONS_Table';

  static const String schoolHistoryTable = 'SCHOOL_HISTORY_Table';

  static const String incidentsTable = 'INCIDENTS_Table';

  static const List<String> syncTables = [
    learnersTable,
    teachersTable,
    sectionsTable,
    schoolHistoryTable,
    incidentsTable,
  ];

  final SyncContextService _context;
  final Future<bool> Function()? _authenticated;
  final bool Function()? _hasCredentials;
  final Future<bool> Function()? _restoreCredentials;

  Future<void> _verifyOwnership() async {
    await _sheets.initialize();
    await _context.verifyOwner(_sheets.spreadsheetId);
  }

  String get deviceId => 'windows';

  // ============================================================
  // PHASE 8A — SEPARATE PUSH/PULL WATERMARKS + PER-RECORD STATE
  // ============================================================

  static const String _legacyLastSyncedPrefix = 'sync_last_synced_';

  static const String _lastPushedPrefix = 'sync_last_pushed_';

  static const String _lastPulledPrefix = 'sync_last_pulled_';

  static const String _syncStateTable = 'SYNC_STATE_Table';

  static const String _lastConflictCountKey = 'sync_last_conflict_count';

  String _legacyLastSyncedKey(String table) => '$_legacyLastSyncedPrefix$table';

  String _lastPushedKey(String table) => '$_lastPushedPrefix$table';

  String _lastPulledKey(String table) => '$_lastPulledPrefix$table';

  Future<void> _ensureSyncStateTable() =>
      SyncContextService.ensureStateTable(_database.database);

  Future<int> getLastKnownConflictCount() {
    return _context.exclusive(() => _getLastKnownConflictCount());
  }

  Future<int> _getLastKnownConflictCount() async {
    await _verifyOwnership();
    final prefs = await SharedPreferences.getInstance();

    return prefs.getInt(
          _lastConflictCountKey,
        ) ??
        0;
  }

  Future<void> _setLastKnownConflictCount(
    int count,
  ) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setInt(
      _lastConflictCountKey,
      count,
    );
  }

  Future<String?> getLastPushedAt(
    String table,
  ) {
    return _context.exclusive(() => _getLastPushedAt(table));
  }

  Future<String?> _getLastPushedAt(
    String table,
  ) async {
    await _verifyOwnership();
    final prefs = await SharedPreferences.getInstance();

    final current = prefs.getString(
      _lastPushedKey(table),
    );

    if (current != null && current.trim().isNotEmpty) {
      return current;
    }

    return prefs.getString(
      _legacyLastSyncedKey(table),
    );
  }

  Future<void> _setLastPushedAt(
    String table,
    String value,
  ) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      _lastPushedKey(table),
      value,
    );
  }

  Future<String?> getLastPulledAt(
    String table,
  ) {
    return _context.exclusive(() => _getLastPulledAt(table));
  }

  Future<String?> _getLastPulledAt(
    String table,
  ) async {
    await _verifyOwnership();
    final prefs = await SharedPreferences.getInstance();

    return prefs.getString(
      _lastPulledKey(table),
    );
  }

  Future<void> _setLastPulledAt(
    String table,
    String value,
  ) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      _lastPulledKey(table),
      value,
    );
  }

  // Backward-compatible API used by the existing SyncScreen.
  // It now reports the PUSH watermark, not the pull watermark.
  Future<String?> getLastSyncedAt(
    String table,
  ) async {
    return getLastPushedAt(table);
  }

  Future<void> _setRecordSyncState(
    String table,
    Map<String, Object?> row,
  ) async {
    final syncId = _syncId(row);

    if (syncId.isEmpty) {
      return;
    }

    await _ensureSyncStateTable();

    await _database.database.insert(
      _syncStateTable,
      {
        'TableName': table,
        'SyncID': syncId,
        'SyncedVersion': _asInt(row['Version']) ?? 1,
        'SyncedUpdatedAt': row['UpdatedAt']?.toString() ?? '',
        'SyncedFingerprint': SyncRecordState.fingerprint(row),
        'NeedsReview': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _setRecordSyncStateInTransaction(
    DatabaseExecutor txn,
    String table,
    Map<String, Object?> row,
  ) async {
    final syncId = _syncId(row);

    if (syncId.isEmpty) {
      return;
    }

    await txn.insert(
      _syncStateTable,
      {
        'TableName': table,
        'SyncID': syncId,
        'SyncedVersion': _asInt(row['Version']) ?? 1,
        'SyncedUpdatedAt': row['UpdatedAt']?.toString() ?? '',
        'SyncedFingerprint': SyncRecordState.fingerprint(row),
        'NeedsReview': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ============================================================
  // DATABASE PROVISIONING / RESET
  //
  // These methods are deliberately separate from the validated
  // synchronization algorithm.
  //
  // clearSyncState()
  //     Used after "Start Fresh Database".
  //
  // restoreFromSpreadsheet()
  //     Replaces local records, baselines and ownership atomically.
  // ============================================================

  /// Clears SQLite baselines, synchronization watermarks and the remembered
  /// conflict count while retaining the configured spreadsheet.
  ///
  /// This is used after the local database has been completely
  /// reset.
  ///
  /// It does NOT modify Google Sheets.
  Future<void> clearSyncState() async {
    await _context.clear();
  }

  Future<String?> legacyUnownedSpreadsheetId() =>
      _context.legacyUnownedSpreadsheetId();

  /// User-confirmed migration only. Validation precedes metadata changes;
  /// activation discards unowned tracking, never either dataset. Keep the
  /// target check, activation and comparison under the same operation guard.
  Future<LegacyReconnectResult> reconnectCurrentSpreadsheet({
    required String expectedSpreadsheetId,
  }) =>
      _context.exclusive(() async {
        Future<void> checkCandidate() async {
          final candidate = await _context.legacyUnownedSpreadsheetId();
          if (candidate == null || candidate != expectedSpreadsheetId) {
            throw StateError(
              'The spreadsheet or ownership state changed. Refresh and review '
              'the current configuration before reconnecting.',
            );
          }
        }

        await checkCandidate();
        if (!await _isGoogleAuthenticated()) {
          throw StateError('Please sign in with Google first.');
        }
        final validated =
            await _sheets.validateSpreadsheet(expectedSpreadsheetId);
        if (validated.spreadsheetId != expectedSpreadsheetId) {
          throw StateError('Google returned an unexpected spreadsheet ID.');
        }
        await _sheets.verifyEncryptionReady(
            spreadsheetId: expectedSpreadsheetId);
        await checkCandidate();
        await _context.activate(expectedSpreadsheetId);

        // A failed download after activation must not be reported as a failed
        // metadata transaction. Comparison can be retried from the existing UI.
        try {
          final comparison = await compareRemoteWithLocal();
          await _database.database.transaction((txn) async {
            for (final item in comparison.comparisons) {
              if (item.status != SyncComparisonStatus.same ||
                  item.remoteRecord == null ||
                  item.localRecord == null) {
                continue;
              }
              final current =
                  await _localRecord(txn, item.tableName, item.syncId);
              if (current != null &&
                  SyncRecordState.same(current, item.remoteRecord)) {
                await _setRecordSyncStateInTransaction(
                    txn, item.tableName, current);
              }
            }
          });
          return LegacyReconnectResult(comparison: comparison);
        } catch (e) {
          return LegacyReconnectResult(comparisonError: e.toString());
        }
      });

  /// Candidate reads do not activate a target. Core data, baselines and owner
  /// commit together; only then is the recoverable preference mirror updated.
  Future<SpreadsheetRestoreResult> restoreFromSpreadsheet(String input) {
    return _context.exclusive(() async {
      final candidate = await _sheets.validateSpreadsheet(input);
      final spreadsheetId = candidate.spreadsheetId!;
      final downloaded = await _sheets.downloadAllTables(
        spreadsheetId: spreadsheetId,
      );
      final imported = await _database.replaceSyncedTables(
        teachers: downloaded.teachers,
        sections: downloaded.sections,
        learners: downloaded.learners,
        schoolHistory: downloaded.schoolHistory,
        incidents: downloaded.incidents,
        establishSyncState: (txn) => _context.replaceImportedStateInTransaction(
          txn,
          spreadsheetId: spreadsheetId,
        ),
      );

      var preferencesPending = false;
      try {
        await _sheets.initialize();
      } catch (_) {
        // The SQLite commit succeeded. Do not report a rolled-back restore:
        // PreferencesPending remains durable and reconciliation retries later.
        preferencesPending = true;
      }
      return SpreadsheetRestoreResult(
        imported: imported,
        spreadsheetId: spreadsheetId,
        preferencesPending: preferencesPending,
      );
    });
  }

  // ============================================================
  // GOOGLE AUTHENTICATION CHECK
  // ============================================================

  // Upload callers can arrive directly from Save after a fresh app launch.
  // Restore credentials before requesting a client: the package signs out
  // (including deleting stored tokens) if its client getter sees no credentials.
  Future<bool> _ensureUploadAuthentication() async {
    // Existing service tests may supply a complete authentication check.
    if (_authenticated != null && _hasCredentials == null) {
      return _isGoogleAuthenticated();
    }
    if (!(_hasCredentials?.call() ?? _auth.isSignedIn)) {
      try {
        final restored = _restoreCredentials != null
            ? await _restoreCredentials()
            : await _auth.silentSignIn() != null;
        if (!restored) return false;
      } catch (_) {
        return false;
      }
    }
    return _isGoogleAuthenticated();
  }

  Future<bool> _isGoogleAuthenticated() async {
    if (_authenticated != null) return _authenticated();
    final client = await _auth.authenticatedClient;

    return client != null;
  }

  // ============================================================
  // PENDING RECORDS
  // ============================================================

  Future<List<Map<String, Object?>>> _localRows(String table,
      {DatabaseExecutor? executor, String? syncId}) {
    if (!syncTables.contains(table)) throw ArgumentError('Unknown table');
    final db = executor ?? _database.database;
    if (table == schoolHistoryTable || table == incidentsTable) {
      return db.rawQuery('''
        SELECT child.*, parent.SyncID AS LearnerSyncID
        FROM $table child LEFT JOIN LEARNERS_Table parent
        ON child.LearnerID = parent.LearnerID
        ${syncId == null ? '' : 'WHERE child.SyncID = ?'}
      ''', syncId == null ? [] : [syncId]);
    }
    return db.query(table,
        where: syncId == null ? null : 'SyncID = ?',
        whereArgs: syncId == null ? null : [syncId]);
  }

  Future<Map<String, Object?>?> _localRecord(
    DatabaseExecutor db,
    String table,
    String syncId,
  ) async {
    final rows = await _localRows(table, executor: db, syncId: syncId);
    for (final row in rows) {
      if (_syncId(row) == syncId) return row;
    }
    return null;
  }

  Future<Map<String, Object?>?> _baseline(
    DatabaseExecutor db,
    String table,
    String syncId,
  ) async {
    final rows = await db.query(_syncStateTable,
        where: 'TableName = ? AND SyncID = ?', whereArgs: [table, syncId]);
    return rows.isEmpty ? null : rows.single;
  }

  Future<void> _markReview(String table, Map<String, Object?> row) async {
    // Do not replace or advance the baseline on a skipped write.
    await _database.database.rawInsert('''
      INSERT OR IGNORE INTO $_syncStateTable (TableName, SyncID, NeedsReview)
      VALUES (?, ?, 1)
    ''', [table, _syncId(row)]);
    await _database.database.update(_syncStateTable, {'NeedsReview': 1},
        where: 'TableName = ? AND SyncID = ?',
        whereArgs: [table, _syncId(row)]);
  }

  Future<List<Map<String, Object?>>> _getPendingRows(
    String table,
  ) async {
    await _ensureSyncStateTable();
    final rows = await _localRows(table);
    final states = await _database.database
        .query(_syncStateTable, where: 'TableName = ?', whereArgs: [table]);
    final byId = {for (final state in states) state['SyncID']: state};
    return rows.where((row) {
      final state = byId[_syncId(row)];
      // A table watermark or legacy version/timestamp cannot prove equality.
      return state == null ||
          state['NeedsReview'] == 1 ||
          state['SyncedFingerprint'] != SyncRecordState.fingerprint(row);
    }).toList();
  }

  Future<bool> _canApplyRemote(
      DatabaseExecutor txn, String table, Map<String, Object?> remote) async {
    final local = await _localRecord(txn, table, _syncId(remote));
    final baseline = await _baseline(txn, table, _syncId(remote));
    final status = SyncRecordState.compare(
        local: local, remote: remote, baseline: baseline);
    return status == SyncComparisonStatus.newRemote ||
        status == SyncComparisonStatus.remoteNewer ||
        status == SyncComparisonStatus.same;
  }
  // ============================================================
  // PENDING COUNT
  // ============================================================

  Future<int> _getPendingCount(
    String table,
  ) async {
    final rows = await _getPendingRows(
      table,
    );

    return rows.length;
  }

  // ============================================================
  // PENDING COUNTS
  // ============================================================

  Future<Map<String, int>> getPendingCounts() {
    return _context.exclusive(() => _getPendingCounts());
  }

  Future<Map<String, int>> _getPendingCounts() async {
    await _verifyOwnership();
    final counts = <String, int>{};

    for (final table in syncTables) {
      counts[table] = await _getPendingCount(
        table,
      );
    }

    return counts;
  }

  // ============================================================
  // TOTAL PENDING
  // ============================================================

  Future<int> getTotalPendingCount() async {
    final counts = await getPendingCounts();

    return counts.values.fold<int>(
      0,
      (sum, value) => sum + value,
    );
  }

  // ============================================================
  // LOCAL STATUS
  // ============================================================

  Future<SyncResult> inspectPendingChanges() async {
    try {
      final counts = await getPendingCounts();

      final total = counts.values.fold<int>(
        0,
        (sum, value) => sum + value,
      );

      return SyncResult(
        success: true,
        message: total == 0
            ? 'No pending changes.'
            : '$total pending change(s) found.',
        learners: counts[learnersTable] ?? 0,
        teachers: counts[teachersTable] ?? 0,
        sections: counts[sectionsTable] ?? 0,
        schoolHistory: counts[schoolHistoryTable] ?? 0,
        incidents: counts[incidentsTable] ?? 0,
        totalPending: total,
      );
    } catch (e) {
      return SyncResult(
        success: false,
        message: 'Unable to inspect pending changes.\n$e',
        learners: 0,
        teachers: 0,
        sections: 0,
        schoolHistory: 0,
        incidents: 0,
        totalPending: 0,
      );
    }
  }

  // ============================================================
  // 6.5C — APPLY REMOTE CHANGES TO SQLITE
  //
  // This method:
  //   1. Downloads Google Sheets.
  //   2. Compares remote and local records.
  //   3. Applies ONLY:
  //        - newRemote
  //        - remoteNewer
  //   4. Leaves localNewer and conflicts untouched.
  //   5. Uses a SQLite transaction.
  //   6. Resolves child LearnerID values through LearnerSyncID.
  // ============================================================

  Future<SyncApplyResult> applyRemoteChangesToLocal() {
    return _context.exclusive(() => _applyRemoteChangesToLocal());
  }

  Future<SyncApplyResult> _applyRemoteChangesToLocal() async {
    try {
      await _verifyOwnership();
      // ----------------------------------------------------------
      // Authentication
      // ----------------------------------------------------------

      final authenticated = await _isGoogleAuthenticated();

      if (!authenticated) {
        return _applyFailure(
          'Please sign in with Google first.',
        );
      }

      await _sheets.initialize();

      final spreadsheetId = _sheets.spreadsheetId;

      if (spreadsheetId == null || spreadsheetId.trim().isEmpty) {
        return _applyFailure(
          'No Google synchronization spreadsheet has been configured.',
        );
      }

      // ----------------------------------------------------------
      // Get comparison first.
      // ----------------------------------------------------------

      final comparison = await compareRemoteWithLocal();

      final applyable = comparison.comparisons.where(
        (item) =>
            item.status == SyncComparisonStatus.newRemote ||
            item.status == SyncComparisonStatus.remoteNewer,
      );

      // ----------------------------------------------------------
      // Count conflicts and skipped records.
      // ----------------------------------------------------------

      final conflictCount = comparison.conflictCount;

      final skippedCount = comparison.localOnlyCount +
          comparison.localNewerCount +
          comparison.sameCount;

      // ----------------------------------------------------------
      // If there is nothing to apply, still report success.
      // ----------------------------------------------------------

      if (applyable.isEmpty) {
        return SyncApplyResult(
          success: true,
          message: 'No remote changes need to be applied.\n\n'
              'Conflicts: $conflictCount\n'
              'Skipped: $skippedCount',
          learnersInserted: 0,
          learnersUpdated: 0,
          learnersDeleted: 0,
          teachersInserted: 0,
          teachersUpdated: 0,
          teachersDeleted: 0,
          sectionsInserted: 0,
          sectionsUpdated: 0,
          sectionsDeleted: 0,
          schoolHistoryInserted: 0,
          schoolHistoryUpdated: 0,
          schoolHistoryDeleted: 0,
          incidentsInserted: 0,
          incidentsUpdated: 0,
          incidentsDeleted: 0,
          skipped: skippedCount,
          conflicts: conflictCount,
        );
      }

      // ----------------------------------------------------------
      // Counters
      // ----------------------------------------------------------

      var learnersInserted = 0;
      var learnersUpdated = 0;
      var learnersDeleted = 0;

      var teachersInserted = 0;
      var teachersUpdated = 0;
      var teachersDeleted = 0;

      var sectionsInserted = 0;
      var sectionsUpdated = 0;
      var sectionsDeleted = 0;

      var schoolHistoryInserted = 0;
      var schoolHistoryUpdated = 0;
      var schoolHistoryDeleted = 0;

      var incidentsInserted = 0;
      var incidentsUpdated = 0;
      var incidentsDeleted = 0;

      var skipped = skippedCount;

      // ----------------------------------------------------------
      // One transaction.
      // ----------------------------------------------------------

      await _database.database.transaction(
        (txn) async {
          // ======================================================
          // STEP 1 — LEARNERS
          // ======================================================

          final learnerChanges = applyable.where(
            (item) => item.tableName == learnersTable,
          );

          for (final change in learnerChanges) {
            final remote = change.remoteRecord;

            if (remote == null ||
                !await _canApplyRemote(txn, learnersTable, remote)) {
              skipped++;
              continue;
            }

            final action = await _applyLearnerChange(
              txn,
              remote,
            );

            if (action != _ApplyAction.skipped) {
              await _setRecordSyncStateInTransaction(
                txn,
                learnersTable,
                remote,
              );
            }

            switch (action) {
              case _ApplyAction.inserted:
                learnersInserted++;
                break;

              case _ApplyAction.updated:
                learnersUpdated++;
                break;

              case _ApplyAction.deleted:
                learnersDeleted++;
                break;

              case _ApplyAction.skipped:
                skipped++;
                break;
            }
          }

          // ======================================================
          // STEP 2 — TEACHERS
          // ======================================================

          final teacherChanges = applyable.where(
            (item) => item.tableName == teachersTable,
          );

          for (final change in teacherChanges) {
            final remote = change.remoteRecord;

            if (remote == null ||
                !await _canApplyRemote(txn, teachersTable, remote)) {
              skipped++;
              continue;
            }

            final action = await _applyTeacherChange(
              txn,
              remote,
            );

            if (action != _ApplyAction.skipped) {
              await _setRecordSyncStateInTransaction(
                txn,
                teachersTable,
                remote,
              );
            }

            switch (action) {
              case _ApplyAction.inserted:
                teachersInserted++;
                break;

              case _ApplyAction.updated:
                teachersUpdated++;
                break;

              case _ApplyAction.deleted:
                teachersDeleted++;
                break;

              case _ApplyAction.skipped:
                skipped++;
                break;
            }
          }

          // ======================================================
          // STEP 3 — SECTIONS
          // ======================================================

          final sectionChanges = applyable.where(
            (item) => item.tableName == sectionsTable,
          );

          for (final change in sectionChanges) {
            final remote = change.remoteRecord;

            if (remote == null ||
                !await _canApplyRemote(txn, sectionsTable, remote)) {
              skipped++;
              continue;
            }

            final action = await _applySectionChange(
              txn,
              remote,
            );

            if (action != _ApplyAction.skipped) {
              await _setRecordSyncStateInTransaction(
                txn,
                sectionsTable,
                remote,
              );
            }

            switch (action) {
              case _ApplyAction.inserted:
                sectionsInserted++;
                break;

              case _ApplyAction.updated:
                sectionsUpdated++;
                break;

              case _ApplyAction.deleted:
                sectionsDeleted++;
                break;

              case _ApplyAction.skipped:
                skipped++;
                break;
            }
          }

          // ======================================================
          // STEP 4 — SCHOOL HISTORY
          // ======================================================

          final historyChanges = applyable.where(
            (item) => item.tableName == schoolHistoryTable,
          );

          for (final change in historyChanges) {
            final remote = change.remoteRecord;

            if (remote == null ||
                !await _canApplyRemote(txn, schoolHistoryTable, remote)) {
              skipped++;
              continue;
            }

            final action = await _applySchoolHistoryChange(
              txn,
              remote,
            );

            if (action != _ApplyAction.skipped) {
              await _setRecordSyncStateInTransaction(
                txn,
                schoolHistoryTable,
                remote,
              );
            }

            switch (action) {
              case _ApplyAction.inserted:
                schoolHistoryInserted++;
                break;

              case _ApplyAction.updated:
                schoolHistoryUpdated++;
                break;

              case _ApplyAction.deleted:
                schoolHistoryDeleted++;
                break;

              case _ApplyAction.skipped:
                skipped++;
                break;
            }
          }

          // ======================================================
          // STEP 5 — INCIDENTS
          // ======================================================

          final incidentChanges = applyable.where(
            (item) => item.tableName == incidentsTable,
          );

          for (final change in incidentChanges) {
            final remote = change.remoteRecord;

            if (remote == null ||
                !await _canApplyRemote(txn, incidentsTable, remote)) {
              skipped++;
              continue;
            }

            final action = await _applyIncidentChange(
              txn,
              remote,
            );

            if (action != _ApplyAction.skipped) {
              await _setRecordSyncStateInTransaction(
                txn,
                incidentsTable,
                remote,
              );
            }

            switch (action) {
              case _ApplyAction.inserted:
                incidentsInserted++;
                break;

              case _ApplyAction.updated:
                incidentsUpdated++;
                break;

              case _ApplyAction.deleted:
                incidentsDeleted++;
                break;

              case _ApplyAction.skipped:
                skipped++;
                break;
            }
          }
        },
      );

      // ----------------------------------------------------------
      // Successful pull.
      // ----------------------------------------------------------

      final pulledAt = DateTime.now().toUtc().toIso8601String();

      for (final table in syncTables) {
        await _setLastPulledAt(
          table,
          pulledAt,
        );
      }

      return SyncApplyResult(
        success: true,
        message: 'Remote changes applied successfully.\n\n'
            'Inserted: ${learnersInserted + teachersInserted + sectionsInserted + schoolHistoryInserted + incidentsInserted}\n'
            'Updated: ${learnersUpdated + teachersUpdated + sectionsUpdated + schoolHistoryUpdated + incidentsUpdated}\n'
            'Deleted: ${learnersDeleted + teachersDeleted + sectionsDeleted + schoolHistoryDeleted + incidentsDeleted}\n'
            'Skipped: $skipped\n'
            'Conflicts: $conflictCount',
        learnersInserted: learnersInserted,
        learnersUpdated: learnersUpdated,
        learnersDeleted: learnersDeleted,
        teachersInserted: teachersInserted,
        teachersUpdated: teachersUpdated,
        teachersDeleted: teachersDeleted,
        sectionsInserted: sectionsInserted,
        sectionsUpdated: sectionsUpdated,
        sectionsDeleted: sectionsDeleted,
        schoolHistoryInserted: schoolHistoryInserted,
        schoolHistoryUpdated: schoolHistoryUpdated,
        schoolHistoryDeleted: schoolHistoryDeleted,
        incidentsInserted: incidentsInserted,
        incidentsUpdated: incidentsUpdated,
        incidentsDeleted: incidentsDeleted,
        skipped: skipped,
        conflicts: conflictCount,
      );
    } catch (e) {
      return _applyFailure(
        'Unable to apply remote changes.\n$e',
      );
    }
  }

  // ============================================================
  // LOCAL SYNC TEST
  // ============================================================

  Future<String> runLocalSyncTest() async {
    try {
      final counts = await getPendingCounts();

      final buffer = StringBuffer();

      buffer.writeln(
        'LOCAL SYNC FOUNDATION TEST',
      );

      buffer.writeln();

      buffer.writeln(
        'Device ID: $deviceId',
      );

      buffer.writeln();

      for (final table in syncTables) {
        final count = counts[table] ?? 0;

        final lastSynced = await getLastSyncedAt(
          table,
        );

        buffer.writeln(
          table,
        );

        buffer.writeln(
          '  Pending: $count',
        );

        buffer.writeln(
          '  Last synced: '
          '${lastSynced ?? 'Never'}',
        );

        buffer.writeln();
      }

      final total = counts.values.fold<int>(
        0,
        (sum, value) => sum + value,
      );

      buffer.writeln(
        'TOTAL PENDING: $total',
      );

      return buffer.toString();
    } catch (e) {
      return '''
LOCAL SYNC FOUNDATION TEST FAILED

$e
''';
    }
  }

  // ============================================================
  // 6.4C — SQLITE → GOOGLE SHEETS
  // ============================================================

  Future<SyncResult> syncPendingToGoogleSheets() {
    return _context.exclusive(() => _syncPendingToGoogleSheets());
  }

  Future<SyncResult> _syncPendingToGoogleSheets() async {
    try {
      await _verifyOwnership();
      if (!await _ensureUploadAuthentication()) {
        return _failure('Please sign in with Google first.');
      }
      final id = _sheets.spreadsheetId;
      if (id == null || id.isEmpty) {
        return _failure(
            'No Google synchronization spreadsheet has been configured.');
      }
      // Validate, never rewrite headers before deciding whether a write is safe.
      await _sheets.validateSpreadsheet(id);
      final comparison = await compareRemoteWithLocal();
      var inserted = 0;
      var updated = 0;
      var conflicts = 0;
      var awaitingPull = 0;
      for (final item in comparison.comparisons) {
        final table = item.tableName;
        // Local edits need not acquire the sync guard. Re-read before deciding.
        final local =
            await _localRecord(_database.database, table, item.syncId);
        final baseline =
            await _baseline(_database.database, table, item.syncId);
        final status = item.status == SyncComparisonStatus.conflict
            ? item.status
            : SyncRecordState.compare(
                local: local, remote: item.remoteRecord, baseline: baseline);
        if (status == SyncComparisonStatus.conflict) {
          conflicts++;
          if (local != null) await _markReview(table, local);
          continue;
        }
        if (status == SyncComparisonStatus.remoteNewer ||
            status == SyncComparisonStatus.newRemote) {
          awaitingPull++;
          if (local != null) await _markReview(table, local);
          continue; // Existing Download/Apply flow accepts remote-only changes.
        }
        if (local == null) continue;
        if (_syncId(local).isEmpty) {
          throw StateError('Cannot synchronize an empty SyncID.');
        }
        if (status == SyncComparisonStatus.same) {
          // Only equality of BOTH sides can upgrade a legacy baseline.
          await _setRecordSyncState(table, local);
          continue;
        }
        try {
          final result = await _sheets.upsertRowsBySyncId(
            sheetTitle: _sheetTitleForTable(table),
            headers: _headersForTable(table),
            rows: [_buildSheetRowForTable(table, local)!],
            expectedRecords: {item.syncId: item.remoteRecord},
          );
          inserted += result.inserted;
          updated += result.updated;
          // Capture exactly what was uploaded, not a later local edit.
          await _setRecordSyncState(table, local);
          await _setLastPushedAt(
              table, DateTime.now().toUtc().toIso8601String());
        } on RemoteRecordChanged {
          conflicts++;
          await _markReview(table, local);
        }
      }
      await _setLastKnownConflictCount(conflicts);
      final counts = await getPendingCounts();
      final remaining = counts.values.fold<int>(0, (sum, count) => sum + count);
      return SyncResult(
        success: conflicts == 0 && awaitingPull == 0 && remaining == 0,
        conflictCount: conflicts,
        requiresRemoteApply: conflicts == 0 && awaitingPull > 0,
        message: conflicts > 0
            ? 'Saved locally; conflict review required. Conflicts: $conflicts. Pending: $remaining.'
            : awaitingPull > 0
                ? 'Remote changes require Download/Apply. Local changes are preserved. Pending: $remaining.'
                : remaining > 0
                    ? 'Google Sheets synchronization incomplete. Inserted: $inserted. Updated: $updated. Remaining pending: $remaining.'
                    : 'Google Sheets synchronization completed. Inserted: $inserted. Updated: $updated. Remaining pending: $remaining.',
        learners: counts[learnersTable]!,
        teachers: counts[teachersTable]!,
        sections: counts[sectionsTable]!,
        schoolHistory: counts[schoolHistoryTable]!,
        incidents: counts[incidentsTable]!,
        totalPending: remaining,
      );
    } catch (e) {
      return _failure('Google Sheets synchronization failed.\n$e');
    }
  }

  Future<SyncComparisonResult> compareRemoteWithLocal() {
    return _context.exclusive(() => _compareRemoteWithLocal());
  }

  Future<SyncComparisonResult> _compareRemoteWithLocal() async {
    await _verifyOwnership();
    if (_sheets.spreadsheetId == null) {
      throw StateError('No synchronization spreadsheet configured.');
    }
    final remote = await _sheets.downloadAllTables();
    await _ensureSyncStateTable();
    final states = await _database.database.query(_syncStateTable);
    final byKey = {
      for (final row in states) '${row['TableName']}|${row['SyncID']}': row
    };
    final remoteTables = {
      learnersTable: remote.learners,
      teachersTable: remote.teachers,
      sectionsTable: remote.sections,
      schoolHistoryTable: remote.schoolHistory,
      incidentsTable: remote.incidents,
    };
    final comparisons = <SyncComparison>[];
    for (final table in syncTables) {
      comparisons.addAll(await _compareTable(
          tableName: table,
          localRows: await _localRows(table),
          remoteRows: remoteTables[table]!,
          baselineByKey: byKey));
    }
    final result = SyncComparisonResult(comparisons: comparisons);
    await _setLastKnownConflictCount(result.conflictCount);
    return result;
  }

  Future<List<SyncComparison>> _compareTable({
    required String tableName,
    required List<Map<String, Object?>> localRows,
    required List<Map<String, Object?>> remoteRows,
    required Map<String, Map<String, Object?>> baselineByKey,
  }) async {
    final localBySyncId = <String, Map<String, Object?>>{};

    final remoteBySyncId = <String, Map<String, Object?>>{};

    // ----------------------------------------------------------
    // Index local records
    // ----------------------------------------------------------

    for (final row in localRows) {
      final syncId = _syncId(row);

      if (syncId.isEmpty) {
        continue;
      }

      localBySyncId[syncId] = row;
    }

    // ----------------------------------------------------------
    // Index remote records
    // ----------------------------------------------------------

    for (final row in remoteRows) {
      final syncId = _syncId(row);

      if (syncId.isEmpty) {
        continue;
      }

      remoteBySyncId[syncId] = row;
    }

    final allSyncIds = <String>{
      ...localBySyncId.keys,
      ...remoteBySyncId.keys,
    };

    final comparisons = <SyncComparison>[];

    for (final syncId in allSyncIds) {
      final local = localBySyncId[syncId];

      final remote = remoteBySyncId[syncId];

      final duplicates =
          remoteRows.where((row) => _syncId(row) == syncId).length > 1;
      final status = duplicates
          ? SyncComparisonStatus.conflict
          : SyncRecordState.compare(
              local: local,
              remote: remote,
              baseline: baselineByKey['$tableName|$syncId']);
      comparisons.add(
        SyncComparison(
          tableName: tableName,
          syncId: syncId,
          status: status,
          localRecord: local,
          remoteRecord: remote,
        ),
      );
    }

    // Stable ordering makes the test results easier to read.
    comparisons.sort(
      (a, b) {
        final tableCompare = a.tableName.compareTo(
          b.tableName,
        );

        if (tableCompare != 0) {
          return tableCompare;
        }

        return a.syncId.compareTo(
          b.syncId,
        );
      },
    );

    return comparisons;
  }

  String _syncId(
    Map<String, Object?> row,
  ) {
    return row['SyncID']?.toString().trim() ?? '';
  }

  // ============================================================
  // INTEGER
  // ============================================================

  int? _asInt(
    Object? value,
  ) {
    if (value is int) {
      return value;
    }

    return int.tryParse(
      value?.toString() ?? '',
    );
  }

  // ============================================================
  // DATE
  // ============================================================

  List<Object?> _learnerToSheetRow(
    Map<String, Object?> row,
  ) {
    return [
      row['SyncID'],
      row['LearnerID'],
      row['LearnerReferenceNumber'],
      row['LastName'],
      row['FirstName'],
      row['MiddleName'],
      row['Sex'],
      row['BirthDate'],
      row['Age'],
      row['PersonalContactNumber'],
      row['RegionCode'],
      row['Region'],
      row['ProvinceCode'],
      row['Province'],
      row['CityMunicipalityCode'],
      row['TownMunicipality'],
      row['BarangayCode'],
      row['Barangay'],
      row['Purok'],
      row['Street'],
      row['HouseNo'],
      row['Parents'],
      row['Guardian'],
      row['RelationshipToGuardian'],
      row['ParentsContactNumber'],
      row['NotesDetails'],
      row['CreatedAt'],
      row['UpdatedAt'],
      row['DeviceID'],
      row['Version'],
      row['Deleted'],
    ];
  }

  // ============================================================
  // TEACHER → GOOGLE SHEETS
  // ============================================================

  List<Object?> _teacherToSheetRow(
    Map<String, Object?> row,
  ) {
    return [
      row['SyncID'],
      row['TeacherID'],
      row['TeacherName'],
      row['MobileNumber'],
      row['Status'],
      row['CreatedAt'],
      row['UpdatedAt'],
      row['DeviceID'],
      row['Version'],
      row['Deleted'],
    ];
  }

  // ============================================================
  // SECTION → GOOGLE SHEETS
  // ============================================================

  List<Object?> _sectionToSheetRow(
    Map<String, Object?> row,
  ) {
    return [
      row['SyncID'],
      row['SectionID'],
      row['SchoolYear'],
      row['GradeLevel'],
      row['SectionName'],
      row['Adviser'],
      row['CreatedAt'],
      row['UpdatedAt'],
      row['DeviceID'],
      row['Version'],
      row['Deleted'],
    ];
  }

  // ============================================================
  // SCHOOL HISTORY → GOOGLE SHEETS
  // ============================================================

  List<Object?> _schoolHistoryToSheetRow(
    Map<String, Object?> row,
  ) {
    return [
      row['SyncID'],
      row['SchoolHistoryID'],
      row['LearnerID'],
      row['LearnerSyncID'],
      row['SchoolYear'],
      row['Grade'],
      row['School'],
      row['Section'],
      row['Adviser'],
      row['NotesDetails'],
      row['CreatedAt'],
      row['UpdatedAt'],
      row['DeviceID'],
      row['Version'],
      row['Deleted'],
    ];
  }

  // ============================================================
  // INCIDENT → GOOGLE SHEETS
  // ============================================================

  List<Object?> _incidentToSheetRow(
    Map<String, Object?> row,
  ) {
    return [
      row['SyncID'],
      row['IncidentID'],
      row['LearnerID'],
      row['LearnerSyncID'],
      row['IncidentDate'],
      row['IncidentTime'],
      row['Observer'],
      row['BehaviorProblem'],
      row['ObservationDetails'],
      row['Intervention'],
      row['ActionTaken'],
      row['Remarks'],
      row['Details'],
      row['CreatedAt'],
      row['UpdatedAt'],
      row['DeviceID'],
      row['Version'],
      row['Deleted'],
    ];
  }

  // ============================================================
  // APPLY LEARNER CHANGE
  // ============================================================

  Future<_ApplyAction> _applyLearnerChange(
    DatabaseExecutor txn,
    Map<String, Object?> remote,
  ) async {
    final syncId = _syncId(remote);

    if (syncId.isEmpty) {
      return _ApplyAction.skipped;
    }

    final existing = await txn.query(
      learnersTable,
      where: 'SyncID = ?',
      whereArgs: [syncId],
      limit: 1,
    );

    final values = <String, Object?>{
      'SyncID': syncId,
      'LearnerReferenceNumber': remote['LearnerReferenceNumber'],
      'LastName': remote['LastName']?.toString() ?? '',
      'FirstName': remote['FirstName']?.toString() ?? '',
      'MiddleName': remote['MiddleName'],
      'Sex': remote['Sex']?.toString() ?? '',
      'BirthDate': remote['BirthDate'],
      'Age': _asInt(remote['Age']),
      'PersonalContactNumber': remote['PersonalContactNumber'],
      'RegionCode': remote['RegionCode'],
      'Region': remote['Region'],
      'ProvinceCode': remote['ProvinceCode'],
      'Province': remote['Province'],
      'CityMunicipalityCode': remote['CityMunicipalityCode'],
      'TownMunicipality': remote['TownMunicipality'],
      'BarangayCode': remote['BarangayCode'],
      'Barangay': remote['Barangay'],
      'Purok': remote['Purok'],
      'Street': remote['Street'],
      'HouseNo': remote['HouseNo'],
      'Parents': remote['Parents'],
      'Guardian': remote['Guardian'],
      'RelationshipToGuardian': remote['RelationshipToGuardian'],
      'ParentsContactNumber': remote['ParentsContactNumber'],
      'NotesDetails': remote['NotesDetails'],
      'CreatedAt': remote['CreatedAt']?.toString() ??
          DateTime.now().toUtc().toIso8601String(),
      'UpdatedAt': remote['UpdatedAt']?.toString() ??
          DateTime.now().toUtc().toIso8601String(),
      'DeviceID': remote['DeviceID']?.toString() ?? 'google-sheets',
      'Version': _asInt(remote['Version']) ?? 1,
      'Deleted': _asInt(remote['Deleted']) ?? 0,
    };

    if (existing.isEmpty) {
      await txn.insert(
        learnersTable,
        values,
      );

      return values['Deleted'] == 1
          ? _ApplyAction.deleted
          : _ApplyAction.inserted;
    }

    final localId = existing.first['LearnerID'];

    await txn.update(
      learnersTable,
      values,
      where: 'LearnerID = ?',
      whereArgs: [localId],
    );

    return values['Deleted'] == 1 ? _ApplyAction.deleted : _ApplyAction.updated;
  }

  // ============================================================
  // APPLY TEACHER CHANGE
  // ============================================================

  Future<_ApplyAction> _applyTeacherChange(
    DatabaseExecutor txn,
    Map<String, Object?> remote,
  ) async {
    final syncId = _syncId(remote);

    if (syncId.isEmpty) {
      return _ApplyAction.skipped;
    }

    final existing = await txn.query(
      teachersTable,
      where: 'SyncID = ?',
      whereArgs: [syncId],
      limit: 1,
    );

    final values = <String, Object?>{
      'SyncID': syncId,
      'TeacherName': remote['TeacherName']?.toString() ?? '',
      'MobileNumber': remote['MobileNumber'],
      'Status': remote['Status']?.toString() ?? 'Active',
      'CreatedAt': remote['CreatedAt']?.toString() ??
          DateTime.now().toUtc().toIso8601String(),
      'UpdatedAt': remote['UpdatedAt']?.toString() ??
          DateTime.now().toUtc().toIso8601String(),
      'DeviceID': remote['DeviceID']?.toString() ?? 'google-sheets',
      'Version': _asInt(remote['Version']) ?? 1,
      'Deleted': _asInt(remote['Deleted']) ?? 0,
    };

    if (existing.isEmpty) {
      await txn.insert(
        teachersTable,
        values,
      );

      return values['Deleted'] == 1
          ? _ApplyAction.deleted
          : _ApplyAction.inserted;
    }

    await txn.update(
      teachersTable,
      values,
      where: 'TeacherID = ?',
      whereArgs: [
        existing.first['TeacherID'],
      ],
    );

    return values['Deleted'] == 1 ? _ApplyAction.deleted : _ApplyAction.updated;
  }

  // ============================================================
  // APPLY SECTION CHANGE
  // ============================================================

  Future<_ApplyAction> _applySectionChange(
    DatabaseExecutor txn,
    Map<String, Object?> remote,
  ) async {
    final syncId = _syncId(remote);

    if (syncId.isEmpty) {
      return _ApplyAction.skipped;
    }

    final existing = await txn.query(
      sectionsTable,
      where: 'SyncID = ?',
      whereArgs: [syncId],
      limit: 1,
    );

    final values = <String, Object?>{
      'SyncID': syncId,
      'SchoolYear': remote['SchoolYear']?.toString() ?? '',
      'GradeLevel': remote['GradeLevel']?.toString() ?? '',
      'SectionName': remote['SectionName']?.toString() ?? '',
      'Adviser': remote['Adviser']?.toString() ?? '',
      'CreatedAt': remote['CreatedAt']?.toString() ??
          DateTime.now().toUtc().toIso8601String(),
      'UpdatedAt': remote['UpdatedAt']?.toString() ??
          DateTime.now().toUtc().toIso8601String(),
      'DeviceID': remote['DeviceID']?.toString() ?? 'google-sheets',
      'Version': _asInt(remote['Version']) ?? 1,
      'Deleted': _asInt(remote['Deleted']) ?? 0,
    };

    if (existing.isEmpty) {
      await txn.insert(
        sectionsTable,
        values,
      );

      return values['Deleted'] == 1
          ? _ApplyAction.deleted
          : _ApplyAction.inserted;
    }

    await txn.update(
      sectionsTable,
      values,
      where: 'SectionID = ?',
      whereArgs: [
        existing.first['SectionID'],
      ],
    );

    return values['Deleted'] == 1 ? _ApplyAction.deleted : _ApplyAction.updated;
  }

  // ============================================================
  // FIND LOCAL LEARNER BY SYNC ID
  // ============================================================

  Future<int?> _findLocalLearnerIdBySyncId(
    DatabaseExecutor txn,
    Object? learnerSyncId,
  ) async {
    final syncId = learnerSyncId?.toString().trim() ?? '';

    if (syncId.isEmpty) {
      return null;
    }

    final rows = await txn.query(
      learnersTable,
      columns: ['LearnerID'],
      where: 'SyncID = ?',
      whereArgs: [syncId],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return _asInt(
      rows.first['LearnerID'],
    );
  }

  // ============================================================
  // APPLY SCHOOL HISTORY CHANGE
  // ============================================================

  Future<_ApplyAction> _applySchoolHistoryChange(
    DatabaseExecutor txn,
    Map<String, Object?> remote,
  ) async {
    final syncId = _syncId(remote);

    if (syncId.isEmpty) {
      return _ApplyAction.skipped;
    }

    final learnerId = await _findLocalLearnerIdBySyncId(
      txn,
      remote['LearnerSyncID'],
    );

    // Do NOT use remote LearnerID.
    if (learnerId == null) {
      return _ApplyAction.skipped;
    }

    final existing = await txn.query(
      schoolHistoryTable,
      where: 'SyncID = ?',
      whereArgs: [syncId],
      limit: 1,
    );

    final values = <String, Object?>{
      'SyncID': syncId,
      'LearnerID': learnerId,
      'SchoolYear': remote['SchoolYear']?.toString() ?? '',
      'Grade': remote['Grade']?.toString() ?? '',
      'School': remote['School']?.toString() ?? '',
      'Section': remote['Section'],
      'Adviser': remote['Adviser'],
      'NotesDetails': remote['NotesDetails'],
      'CreatedAt': remote['CreatedAt']?.toString() ??
          DateTime.now().toUtc().toIso8601String(),
      'UpdatedAt': remote['UpdatedAt']?.toString() ??
          DateTime.now().toUtc().toIso8601String(),
      'DeviceID': remote['DeviceID']?.toString() ?? 'google-sheets',
      'Version': _asInt(remote['Version']) ?? 1,
      'Deleted': _asInt(remote['Deleted']) ?? 0,
    };

    if (existing.isEmpty) {
      await txn.insert(
        schoolHistoryTable,
        values,
      );

      return values['Deleted'] == 1
          ? _ApplyAction.deleted
          : _ApplyAction.inserted;
    }

    await txn.update(
      schoolHistoryTable,
      values,
      where: 'SchoolHistoryID = ?',
      whereArgs: [
        existing.first['SchoolHistoryID'],
      ],
    );

    return values['Deleted'] == 1 ? _ApplyAction.deleted : _ApplyAction.updated;
  }

  // ============================================================
  // APPLY INCIDENT CHANGE
  // ============================================================

  Future<_ApplyAction> _applyIncidentChange(
    DatabaseExecutor txn,
    Map<String, Object?> remote,
  ) async {
    final syncId = _syncId(remote);

    if (syncId.isEmpty) {
      return _ApplyAction.skipped;
    }

    final learnerId = await _findLocalLearnerIdBySyncId(
      txn,
      remote['LearnerSyncID'],
    );

    // Never use another device's local LearnerID.
    if (learnerId == null) {
      return _ApplyAction.skipped;
    }

    final existing = await txn.query(
      incidentsTable,
      where: 'SyncID = ?',
      whereArgs: [syncId],
      limit: 1,
    );

    final values = <String, Object?>{
      'SyncID': syncId,
      'LearnerID': learnerId,
      'IncidentDate': remote['IncidentDate']?.toString() ?? '',
      'IncidentTime': remote['IncidentTime'],
      'Observer': remote['Observer'],
      'BehaviorProblem': remote['BehaviorProblem']?.toString() ?? '',
      'ObservationDetails': remote['ObservationDetails'],
      'Intervention': remote['Intervention'],
      'ActionTaken': remote['ActionTaken'],
      'Remarks': remote['Remarks'],
      'Details': remote['Details'],
      'CreatedAt': remote['CreatedAt']?.toString() ??
          DateTime.now().toUtc().toIso8601String(),
      'UpdatedAt': remote['UpdatedAt']?.toString() ??
          DateTime.now().toUtc().toIso8601String(),
      'DeviceID': remote['DeviceID']?.toString() ?? 'google-sheets',
      'Version': _asInt(remote['Version']) ?? 1,
      'Deleted': _asInt(remote['Deleted']) ?? 0,
    };

    if (existing.isEmpty) {
      await txn.insert(
        incidentsTable,
        values,
      );

      return values['Deleted'] == 1
          ? _ApplyAction.deleted
          : _ApplyAction.inserted;
    }

    await txn.update(
      incidentsTable,
      values,
      where: 'IncidentID = ?',
      whereArgs: [
        existing.first['IncidentID'],
      ],
    );

    return values['Deleted'] == 1 ? _ApplyAction.deleted : _ApplyAction.updated;
  }

  // ============================================================
  // KEEP LOCAL
  // ============================================================

  Future<SyncResult> resolveConflictKeepLocal({
    required String tableName,
    required String syncId,
  }) {
    return _context.exclusive(() => _resolveConflictKeepLocal(
          tableName: tableName,
          syncId: syncId,
        ));
  }

  Future<SyncResult> _resolveConflictKeepLocal({
    required String tableName,
    required String syncId,
  }) async {
    try {
      await _verifyOwnership();
      // ----------------------------------------------------------
      // Authentication
      // ----------------------------------------------------------

      final authenticated = await _isGoogleAuthenticated();

      if (!authenticated) {
        return _failure(
          'Please sign in with Google first.',
        );
      }

      // ----------------------------------------------------------
      // Initialize Google Sheets
      // ----------------------------------------------------------

      await _sheets.initialize();

      final spreadsheetId = _sheets.spreadsheetId;

      if (spreadsheetId == null || spreadsheetId.trim().isEmpty) {
        return _failure(
          'No Google synchronization spreadsheet has been configured.',
        );
      }

      // ----------------------------------------------------------
      // Re-check comparison immediately before resolving.
      // ----------------------------------------------------------

      final comparison = await compareRemoteWithLocal();

      final matches = comparison.comparisons
          .where(
            (item) => item.tableName == tableName && item.syncId == syncId,
          )
          .toList();

      if (matches.isEmpty) {
        return _failure(
          'The specified synchronization record was not found.',
        );
      }

      final item = matches.first;

      // ----------------------------------------------------------
      // The record must still be a conflict.
      // ----------------------------------------------------------

      if (item.status != SyncComparisonStatus.conflict) {
        return _failure(
          'The record is no longer in conflict.\n\n'
          'Current status: ${item.status.name}',
        );
      }

      final local = item.localRecord;

      if (local == null) {
        return _failure(
          'The local record no longer exists.',
        );
      }

      // ----------------------------------------------------------
      // Keep Local creates a new local revision.
      // ----------------------------------------------------------

      final localVersion = _asInt(local['Version']) ?? 1;

      final remoteVersion = _asInt(
            item.remoteRecord?['Version'],
          ) ??
          1;

      final resolvedVersion =
          (localVersion > remoteVersion ? localVersion : remoteVersion) + 1;

      final resolvedUpdatedAt = DateTime.now().toUtc().toIso8601String();

      final resolvedLocal = Map<String, Object?>.from(local)
        ..['Version'] = resolvedVersion
        ..['UpdatedAt'] = resolvedUpdatedAt
        ..['DeviceID'] = deviceId;

      await _database.database.transaction((txn) async {
        final current = await _localRecord(txn, tableName, syncId);
        if (!SyncRecordState.same(current, local)) {
          throw StateError(
              'Local record changed during review. Retry conflict resolution.');
        }
        await txn.update(
            tableName,
            {
              'Version': resolvedVersion,
              'UpdatedAt': resolvedUpdatedAt,
              'DeviceID': deviceId,
            },
            where: 'SyncID = ?',
            whereArgs: [syncId]);
      });
      // ----------------------------------------------------------
      // Convert resolved local record to sheet row.
      // ----------------------------------------------------------

      final row = _buildSheetRowForTable(
        tableName,
        resolvedLocal,
      );

      if (row == null) {
        return _failure(
          'Unable to prepare the local record for Google Sheets.',
        );
      }

      // ----------------------------------------------------------
      // Upload local record.
      // ----------------------------------------------------------

      final result = await _sheets.upsertRowsBySyncId(
        sheetTitle: _sheetTitleForTable(
          tableName,
        ),
        headers: _headersForTable(
          tableName,
        ),
        rows: [row],
        expectedRecords: {syncId: item.remoteRecord},
      );

      // ----------------------------------------------------------
      // Mark this table as synced.
      // ----------------------------------------------------------

      final pushedAt = DateTime.now().toUtc().toIso8601String();

      await _setRecordSyncState(
        tableName,
        resolvedLocal,
      );

      await _setLastPushedAt(
        tableName,
        pushedAt,
      );

      return SyncResult(
        success: true,
        message: 'Conflict resolved by keeping the local record.\n\n'
            'Table: $tableName\n'
            'SyncID: $syncId\n'
            'Google Sheets inserted: ${result.inserted}\n'
            'Google Sheets updated: ${result.updated}',
        learners: 0,
        teachers: 0,
        sections: 0,
        schoolHistory: 0,
        incidents: 0,
        totalPending: await getTotalPendingCount(),
      );
    } catch (e) {
      return _failure(
        'Unable to keep the local record.\n$e',
      );
    }
  }

  // ============================================================
  // USE REMOTE
  // ============================================================

  Future<SyncApplyResult> resolveConflictUseRemote({
    required String tableName,
    required String syncId,
  }) {
    return _context.exclusive(() => _resolveConflictUseRemote(
          tableName: tableName,
          syncId: syncId,
        ));
  }

  Future<SyncApplyResult> _resolveConflictUseRemote({
    required String tableName,
    required String syncId,
  }) async {
    try {
      await _verifyOwnership();
      // ----------------------------------------------------------
      // Authentication
      // ----------------------------------------------------------

      final authenticated = await _isGoogleAuthenticated();

      if (!authenticated) {
        return _applyFailure(
          'Please sign in with Google first.',
        );
      }

      // ----------------------------------------------------------
      // Initialize Google Sheets
      // ----------------------------------------------------------

      await _sheets.initialize();

      final spreadsheetId = _sheets.spreadsheetId;

      if (spreadsheetId == null || spreadsheetId.trim().isEmpty) {
        return _applyFailure(
          'No Google synchronization spreadsheet has been configured.',
        );
      }

      // ----------------------------------------------------------
      // Re-check comparison immediately before resolving.
      // ----------------------------------------------------------

      final comparison = await compareRemoteWithLocal();

      final matches = comparison.comparisons
          .where(
            (item) => item.tableName == tableName && item.syncId == syncId,
          )
          .toList();

      if (matches.isEmpty) {
        return _applyFailure(
          'The specified synchronization record was not found.',
        );
      }

      final item = matches.first;

      // ----------------------------------------------------------
      // The record must still be a conflict.
      // ----------------------------------------------------------

      if (item.status != SyncComparisonStatus.conflict) {
        return _applyFailure(
          'The record is no longer in conflict.\n\n'
          'Current status: ${item.status.name}',
        );
      }

      final remote = item.remoteRecord;

      if (remote == null) {
        return _applyFailure(
          'The remote record no longer exists.',
        );
      }

      // ----------------------------------------------------------
      // Apply exactly this one remote record.
      // ----------------------------------------------------------

      return await _applySingleRemoteRecord(
        tableName: tableName,
        remote: remote,
        expectedLocal: item.localRecord,
      );
    } catch (e) {
      return _applyFailure(
        'Unable to use the remote record.\n$e',
      );
    }
  }

  // ============================================================
  // BUILD A SHEET ROW FOR ONE TABLE
  // ============================================================

  List<Object?>? _buildSheetRowForTable(
    String tableName,
    Map<String, Object?> row,
  ) {
    switch (tableName) {
      case learnersTable:
        return _learnerToSheetRow(row);

      case teachersTable:
        return _teacherToSheetRow(row);

      case sectionsTable:
        return _sectionToSheetRow(row);

      case schoolHistoryTable:
        return _schoolHistoryToSheetRow(row);

      case incidentsTable:
        return _incidentToSheetRow(row);

      default:
        return null;
    }
  }

  // ============================================================
  // SHEET TITLE
  // ============================================================

  String _sheetTitleForTable(
    String tableName,
  ) {
    switch (tableName) {
      case learnersTable:
        return GoogleSheetsService.learnersSheet;

      case teachersTable:
        return GoogleSheetsService.teachersSheet;

      case sectionsTable:
        return GoogleSheetsService.sectionsSheet;

      case schoolHistoryTable:
        return GoogleSheetsService.schoolHistorySheet;

      case incidentsTable:
        return GoogleSheetsService.incidentsSheet;

      default:
        throw ArgumentError(
          'Unknown synchronization table: $tableName',
        );
    }
  }

  // ============================================================
  // HEADERS
  // ============================================================

  List<String> _headersForTable(
    String tableName,
  ) {
    switch (tableName) {
      case learnersTable:
        return GoogleSheetsService.learnerHeaders;

      case teachersTable:
        return GoogleSheetsService.teacherHeaders;

      case sectionsTable:
        return GoogleSheetsService.sectionHeaders;

      case schoolHistoryTable:
        return GoogleSheetsService.schoolHistoryHeaders;

      case incidentsTable:
        return GoogleSheetsService.incidentHeaders;

      default:
        throw ArgumentError(
          'Unknown synchronization table: $tableName',
        );
    }
  }

  // ============================================================
  // APPLY ONE REMOTE RECORD
  // ============================================================

  Future<SyncApplyResult> _applySingleRemoteRecord({
    required String tableName,
    required Map<String, Object?> remote,
    required Map<String, Object?>? expectedLocal,
  }) async {
    try {
      var inserted = 0;
      var updated = 0;
      var deleted = 0;
      var skipped = 0;

      await _database.database.transaction(
        (txn) async {
          final current = await _localRecord(txn, tableName, _syncId(remote));
          if (!SyncRecordState.same(current, expectedLocal)) {
            throw StateError(
                'Local record changed during review. Retry conflict resolution.');
          }
          late _ApplyAction action;

          switch (tableName) {
            case learnersTable:
              action = await _applyLearnerChange(
                txn,
                remote,
              );
              break;

            case teachersTable:
              action = await _applyTeacherChange(
                txn,
                remote,
              );
              break;

            case sectionsTable:
              action = await _applySectionChange(
                txn,
                remote,
              );
              break;

            case schoolHistoryTable:
              action = await _applySchoolHistoryChange(
                txn,
                remote,
              );
              break;

            case incidentsTable:
              action = await _applyIncidentChange(
                txn,
                remote,
              );
              break;

            default:
              action = _ApplyAction.skipped;
          }

          switch (action) {
            case _ApplyAction.inserted:
              inserted++;
              break;

            case _ApplyAction.updated:
              updated++;
              break;

            case _ApplyAction.deleted:
              deleted++;
              break;

            case _ApplyAction.skipped:
              skipped++;
              break;
          }

          if (action != _ApplyAction.skipped) {
            await _setRecordSyncStateInTransaction(
              txn,
              tableName,
              remote,
            );
          }
        },
      );

      await _setLastPulledAt(
        tableName,
        DateTime.now().toUtc().toIso8601String(),
      );

      return SyncApplyResult(
        success: skipped == 0,
        message: 'Remote record application completed.\n\n'
            'Table: $tableName\n'
            'SyncID: ${_syncId(remote)}\n'
            'Inserted: $inserted\n'
            'Updated: $updated\n'
            'Deleted: $deleted\n'
            'Skipped: $skipped',
        learnersInserted: tableName == learnersTable ? inserted : 0,
        learnersUpdated: tableName == learnersTable ? updated : 0,
        learnersDeleted: tableName == learnersTable ? deleted : 0,
        teachersInserted: tableName == teachersTable ? inserted : 0,
        teachersUpdated: tableName == teachersTable ? updated : 0,
        teachersDeleted: tableName == teachersTable ? deleted : 0,
        sectionsInserted: tableName == sectionsTable ? inserted : 0,
        sectionsUpdated: tableName == sectionsTable ? updated : 0,
        sectionsDeleted: tableName == sectionsTable ? deleted : 0,
        schoolHistoryInserted: tableName == schoolHistoryTable ? inserted : 0,
        schoolHistoryUpdated: tableName == schoolHistoryTable ? updated : 0,
        schoolHistoryDeleted: tableName == schoolHistoryTable ? deleted : 0,
        incidentsInserted: tableName == incidentsTable ? inserted : 0,
        incidentsUpdated: tableName == incidentsTable ? updated : 0,
        incidentsDeleted: tableName == incidentsTable ? deleted : 0,
        skipped: skipped,
        conflicts: 0,
      );
    } catch (e) {
      return _applyFailure(
        'Unable to apply remote record.\n$e',
      );
    }
  }

  // ============================================================
  // FAILURE RESULT
  // ============================================================

  SyncResult _failure(
    String message,
  ) {
    return SyncResult(
      success: false,
      message: message,
      learners: 0,
      teachers: 0,
      sections: 0,
      schoolHistory: 0,
      incidents: 0,
      totalPending: 0,
    );
  }

  SyncApplyResult _applyFailure(
    String message,
  ) {
    return SyncApplyResult(
      success: false,
      message: message,
      learnersInserted: 0,
      learnersUpdated: 0,
      learnersDeleted: 0,
      teachersInserted: 0,
      teachersUpdated: 0,
      teachersDeleted: 0,
      sectionsInserted: 0,
      sectionsUpdated: 0,
      sectionsDeleted: 0,
      schoolHistoryInserted: 0,
      schoolHistoryUpdated: 0,
      schoolHistoryDeleted: 0,
      incidentsInserted: 0,
      incidentsUpdated: 0,
      incidentsDeleted: 0,
      skipped: 0,
      conflicts: 0,
    );
  }
}

class LegacyReconnectResult {
  const LegacyReconnectResult({this.comparison, this.comparisonError});

  final SyncComparisonResult? comparison;
  final String? comparisonError;
}

class SpreadsheetRestoreResult {
  const SpreadsheetRestoreResult({
    required this.imported,
    required this.spreadsheetId,
    required this.preferencesPending,
  });

  final DatabaseImportResult imported;
  final String spreadsheetId;
  final bool preferencesPending;

  int get total => imported.total;

  String get message => 'The Google Spreadsheet was restored successfully.\n\n'
      'Imported records: $total.'
      '${preferencesPending ? '\n\nSynchronization settings could not be refreshed. '
          'The local restore is complete; settings recovery will retry on the next synchronization.' : ''}';
}
