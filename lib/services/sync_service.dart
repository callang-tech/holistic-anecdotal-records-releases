import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../database/app_database.dart';
import '../models/sync_apply_result.dart';
import '../models/sync_comparison.dart';
import '../models/sync_result.dart';
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
  SyncService._();

  static final SyncService instance =
      SyncService._();

  final AppDatabase _database =
      AppDatabase.instance;

  final GoogleAuthService _auth =
      GoogleAuthService.instance;

  final GoogleSheetsService _sheets =
      GoogleSheetsService.instance;

  static const String learnersTable =
      'LEARNERS_Table';

  static const String teachersTable =
      'TEACHERS_Table';

  static const String sectionsTable =
      'SECTIONS_Table';

  static const String schoolHistoryTable =
      'SCHOOL_HISTORY_Table';

  static const String incidentsTable =
      'INCIDENTS_Table';

  static const List<String> syncTables = [
    learnersTable,
    teachersTable,
    sectionsTable,
    schoolHistoryTable,
    incidentsTable,
  ];

  final SyncContextService _context = SyncContextService.instance;

  Future<void> _verifyOwnership() async {
    await _sheets.initialize();
    await _context.verifyOwner(_sheets.spreadsheetId);
  }

  String get deviceId => 'windows';

  // ============================================================
  // PHASE 8A — SEPARATE PUSH/PULL WATERMARKS + PER-RECORD STATE
  // ============================================================

  static const String _legacyLastSyncedPrefix =
      'sync_last_synced_';

  static const String _lastPushedPrefix =
      'sync_last_pushed_';

  static const String _lastPulledPrefix =
      'sync_last_pulled_';

  static const String _syncStateTable =
      'SYNC_STATE_Table';

  static const String _lastConflictCountKey =
      'sync_last_conflict_count';

  String _legacyLastSyncedKey(String table) =>
      '$_legacyLastSyncedPrefix$table';

  String _lastPushedKey(String table) =>
      '$_lastPushedPrefix$table';

  String _lastPulledKey(String table) =>
      '$_lastPulledPrefix$table';

  Future<void> _ensureSyncStateTable() async {
    await _database.database.execute('''
      CREATE TABLE IF NOT EXISTS $_syncStateTable (
        TableName TEXT NOT NULL,
        SyncID TEXT NOT NULL,
        SyncedVersion INTEGER NOT NULL DEFAULT 1,
        SyncedUpdatedAt TEXT NOT NULL DEFAULT '',
        PRIMARY KEY (TableName, SyncID)
      )
    ''');
  }

  Future<int> getLastKnownConflictCount() {
    return _context.exclusive(() => _getLastKnownConflictCount());
  }

  Future<int> _getLastKnownConflictCount() async {
    await _verifyOwnership();
    final prefs =
        await SharedPreferences.getInstance();

    return prefs.getInt(
          _lastConflictCountKey,
        ) ??
        0;
  }

  Future<void> _setLastKnownConflictCount(
    int count,
  ) async {
    final prefs =
        await SharedPreferences.getInstance();

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
    final prefs =
        await SharedPreferences.getInstance();

    final current =
        prefs.getString(
      _lastPushedKey(table),
    );

    if (current != null &&
        current.trim().isNotEmpty) {
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
    final prefs =
        await SharedPreferences.getInstance();

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
    final prefs =
        await SharedPreferences.getInstance();

    return prefs.getString(
      _lastPulledKey(table),
    );
  }

  Future<void> _setLastPulledAt(
    String table,
    String value,
  ) async {
    final prefs =
        await SharedPreferences.getInstance();

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
    final syncId =
        _syncId(row);

    if (syncId.isEmpty) {
      return;
    }

    await _ensureSyncStateTable();

    await _database.database.insert(
      _syncStateTable,
      {
        'TableName': table,
        'SyncID': syncId,
        'SyncedVersion':
            _asInt(row['Version']) ?? 1,
        'SyncedUpdatedAt':
            row['UpdatedAt']?.toString() ?? '',
      },
      conflictAlgorithm:
          ConflictAlgorithm.replace,
    );
  }

  Future<void> _setRecordSyncStateInTransaction(
    DatabaseExecutor txn,
    String table,
    Map<String, Object?> row,
  ) async {
    final syncId =
        _syncId(row);

    if (syncId.isEmpty) {
      return;
    }

    await txn.insert(
      _syncStateTable,
      {
        'TableName': table,
        'SyncID': syncId,
        'SyncedVersion':
            _asInt(row['Version']) ?? 1,
        'SyncedUpdatedAt':
            row['UpdatedAt']?.toString() ?? '',
      },
      conflictAlgorithm:
          ConflictAlgorithm.replace,
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
          txn, spreadsheetId: spreadsheetId,
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

  Future<bool> _isGoogleAuthenticated() async {
    final client =
        await _auth.authenticatedClient;

    return client != null;
  }

  // ============================================================
  // PENDING RECORDS
  // ============================================================

  Future<List<Map<String, Object?>>> _getPendingRows(
    String table, {
    required String cutoff,
  }) async {
    await _ensureSyncStateTable();

    final db =
        _database.database;

    final legacyWatermark =
        await _getLegacyLastSyncedAt(
      table,
    );

    final rows =
        await db.query(
      table,
      where: 'UpdatedAt <= ?',
      whereArgs: [cutoff],
      orderBy: 'UpdatedAt ASC',
    );

    final states =
        await db.query(
      _syncStateTable,
      columns: [
        'SyncID',
        'SyncedVersion',
        'SyncedUpdatedAt',
      ],
      where: 'TableName = ?',
      whereArgs: [table],
    );

    final stateBySyncId =
        <String, Map<String, Object?>>{};

    for (final state in states) {
      final id =
          state['SyncID']
                  ?.toString()
                  .trim() ??
              '';

      if (id.isNotEmpty) {
        stateBySyncId[id] = state;
      }
    }

    final pending =
        <Map<String, Object?>>[];

    for (final row in rows) {
      final syncId =
          _syncId(row);

      if (syncId.isEmpty) {
        pending.add(row);
        continue;
      }

      final state =
          stateBySyncId[syncId];

      if (state != null) {
        final localVersion =
            _asInt(row['Version']) ?? 1;

        final syncedVersion =
            _asInt(
                  state['SyncedVersion'],
                ) ??
                1;

        final localUpdatedAt =
            row['UpdatedAt']?.toString() ?? '';

        final syncedUpdatedAt =
            state['SyncedUpdatedAt']
                    ?.toString() ??
                '';

        if (localVersion !=
                syncedVersion ||
            localUpdatedAt !=
                syncedUpdatedAt) {
          pending.add(row);
        }

        continue;
      }

      // Compatibility with the old Phase 7 table-level watermark.
      // Existing records at/before that watermark remain
      // considered synchronized until they are changed.
      // Newer records are pending.
      if (legacyWatermark == null ||
          legacyWatermark.trim().isEmpty ||
          _isAfterWatermark(
            row['UpdatedAt'],
            legacyWatermark,
          )) {
        pending.add(row);
      }
    }

    return pending;
  }

  Future<String?> _getLegacyLastSyncedAt(
    String table,
  ) async {
    final prefs =
        await SharedPreferences.getInstance();

    return prefs.getString(
      _legacyLastSyncedKey(table),
    );
  }

  bool _isAfterWatermark(
    Object? updatedAt,
    String watermark,
  ) {
    final rowDate =
        _parseSyncDate(updatedAt);

    final watermarkDate =
        _parseSyncDate(watermark);

    if (rowDate == null ||
        watermarkDate == null) {
      return true;
    }

    return rowDate.isAfter(
      watermarkDate,
    );
  }

  // ============================================================
  // PENDING COUNT
  // ============================================================

  Future<int> _getPendingCount(
    String table,
  ) async {
    final cutoff =
        DateTime.now()
            .toUtc()
            .toIso8601String();

    final rows =
        await _getPendingRows(
      table,
      cutoff: cutoff,
    );

    return rows.length;
  }

  // ============================================================
  // PENDING COUNTS
  // ============================================================

  Future<Map<String, int>>
      getPendingCounts() {
    return _context.exclusive(() => _getPendingCounts());
  }

  Future<Map<String, int>>
      _getPendingCounts() async {
    await _verifyOwnership();
    final counts =
        <String, int>{};

    for (final table in syncTables) {
      counts[table] =
          await _getPendingCount(
        table,
      );
    }

    return counts;
  }

  // ============================================================
  // TOTAL PENDING
  // ============================================================

  Future<int>
      getTotalPendingCount() async {
    final counts =
        await getPendingCounts();

    return counts.values.fold<int>(
      0,
      (sum, value) => sum + value,
    );
  }

  // ============================================================
  // LOCAL STATUS
  // ============================================================

  Future<SyncResult>
      inspectPendingChanges() async {
    try {
      final counts =
          await getPendingCounts();

      final total =
          counts.values.fold<int>(
        0,
        (sum, value) => sum + value,
      );

      return SyncResult(
        success: true,
        message:
            total == 0
                ? 'No pending changes.'
                : '$total pending change(s) found.',
        learners:
            counts[learnersTable] ?? 0,
        teachers:
            counts[teachersTable] ?? 0,
        sections:
            counts[sectionsTable] ?? 0,
        schoolHistory:
            counts[schoolHistoryTable] ?? 0,
        incidents:
            counts[incidentsTable] ?? 0,
        totalPending:
            total,
      );
    } catch (e) {
      return SyncResult(
        success: false,
        message:
            'Unable to inspect pending changes.\n$e',
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

  Future<SyncApplyResult>
      applyRemoteChangesToLocal() {
    return _context.exclusive(() => _applyRemoteChangesToLocal());
  }

  Future<SyncApplyResult>
      _applyRemoteChangesToLocal() async {
    try {
      await _verifyOwnership();
      // ----------------------------------------------------------
      // Authentication
      // ----------------------------------------------------------

      final authenticated =
          await _isGoogleAuthenticated();

      if (!authenticated) {
        return _applyFailure(
          'Please sign in with Google first.',
        );
      }

      await _sheets.initialize();

      final spreadsheetId =
          _sheets.spreadsheetId;

      if (spreadsheetId == null ||
          spreadsheetId.trim().isEmpty) {
        return _applyFailure(
          'No Google synchronization spreadsheet has been configured.',
        );
      }

      // ----------------------------------------------------------
      // Get comparison first.
      // ----------------------------------------------------------

      final comparison =
          await compareRemoteWithLocal();

      final applyable =
          comparison.comparisons.where(
        (item) =>
            item.status ==
                SyncComparisonStatus.newRemote ||
            item.status ==
                SyncComparisonStatus.remoteNewer,
      );

      // ----------------------------------------------------------
      // Count conflicts and skipped records.
      // ----------------------------------------------------------

      final conflictCount =
          comparison.conflictCount;

      final skippedCount =
          comparison.localOnlyCount +
          comparison.localNewerCount +
          comparison.sameCount;

      // ----------------------------------------------------------
      // If there is nothing to apply, still report success.
      // ----------------------------------------------------------

      if (applyable.isEmpty) {
        return SyncApplyResult(
          success: true,
          message:
              'No remote changes need to be applied.\n\n'
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

          final learnerChanges =
              applyable.where(
            (item) =>
                item.tableName ==
                learnersTable,
          );

          for (final change in learnerChanges) {
            final remote =
                change.remoteRecord;

            if (remote == null) {
              skipped++;
              continue;
            }

            final action =
                await _applyLearnerChange(
              txn,
              remote,
            );

            if (action !=
                _ApplyAction.skipped) {
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

          final teacherChanges =
              applyable.where(
            (item) =>
                item.tableName ==
                teachersTable,
          );

          for (final change in teacherChanges) {
            final remote =
                change.remoteRecord;

            if (remote == null) {
              skipped++;
              continue;
            }

            final action =
                await _applyTeacherChange(
              txn,
              remote,
            );

            if (action !=
                _ApplyAction.skipped) {
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

          final sectionChanges =
              applyable.where(
            (item) =>
                item.tableName ==
                sectionsTable,
          );

          for (final change in sectionChanges) {
            final remote =
                change.remoteRecord;

            if (remote == null) {
              skipped++;
              continue;
            }

            final action =
                await _applySectionChange(
              txn,
              remote,
            );

            if (action !=
                _ApplyAction.skipped) {
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

          final historyChanges =
              applyable.where(
            (item) =>
                item.tableName ==
                schoolHistoryTable,
          );

          for (final change in historyChanges) {
            final remote =
                change.remoteRecord;

            if (remote == null) {
              skipped++;
              continue;
            }

            final action =
                await _applySchoolHistoryChange(
              txn,
              remote,
            );

            if (action !=
                _ApplyAction.skipped) {
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

          final incidentChanges =
              applyable.where(
            (item) =>
                item.tableName ==
                incidentsTable,
          );

          for (final change in incidentChanges) {
            final remote =
                change.remoteRecord;

            if (remote == null) {
              skipped++;
              continue;
            }

            final action =
                await _applyIncidentChange(
              txn,
              remote,
            );

            if (action !=
                _ApplyAction.skipped) {
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

      final pulledAt =
          DateTime.now()
              .toUtc()
              .toIso8601String();

      for (final table in syncTables) {
        await _setLastPulledAt(
          table,
          pulledAt,
        );
      }

      return SyncApplyResult(
        success: true,
        message:
            'Remote changes applied successfully.\n\n'
            'Inserted: ${learnersInserted + teachersInserted + sectionsInserted + schoolHistoryInserted + incidentsInserted}\n'
            'Updated: ${learnersUpdated + teachersUpdated + sectionsUpdated + schoolHistoryUpdated + incidentsUpdated}\n'
            'Deleted: ${learnersDeleted + teachersDeleted + sectionsDeleted + schoolHistoryDeleted + incidentsDeleted}\n'
            'Skipped: $skipped\n'
            'Conflicts: $conflictCount',
        learnersInserted:
            learnersInserted,
        learnersUpdated:
            learnersUpdated,
        learnersDeleted:
            learnersDeleted,
        teachersInserted:
            teachersInserted,
        teachersUpdated:
            teachersUpdated,
        teachersDeleted:
            teachersDeleted,
        sectionsInserted:
            sectionsInserted,
        sectionsUpdated:
            sectionsUpdated,
        sectionsDeleted:
            sectionsDeleted,
        schoolHistoryInserted:
            schoolHistoryInserted,
        schoolHistoryUpdated:
            schoolHistoryUpdated,
        schoolHistoryDeleted:
            schoolHistoryDeleted,
        incidentsInserted:
            incidentsInserted,
        incidentsUpdated:
            incidentsUpdated,
        incidentsDeleted:
            incidentsDeleted,
        skipped:
            skipped,
        conflicts:
            conflictCount,
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

  Future<String>
      runLocalSyncTest() async {
    try {
      final counts =
          await getPendingCounts();

      final buffer =
          StringBuffer();

      buffer.writeln(
        'LOCAL SYNC FOUNDATION TEST',
      );

      buffer.writeln();

      buffer.writeln(
        'Device ID: $deviceId',
      );

      buffer.writeln();

      for (final table in syncTables) {
        final count =
            counts[table] ?? 0;

        final lastSynced =
            await getLastSyncedAt(
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

      final total =
          counts.values.fold<int>(
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

  Future<SyncResult>
      syncPendingToGoogleSheets() {
    return _context.exclusive(() => _syncPendingToGoogleSheets());
  }

  Future<SyncResult>
      _syncPendingToGoogleSheets() async {
    try {
      await _verifyOwnership();
      // --------------------------------------------------------
      // Authentication
      // --------------------------------------------------------

      final authenticated =
          await _isGoogleAuthenticated();

      if (!authenticated) {
        return _failure(
          'Please sign in with Google first.',
        );
      }

      // --------------------------------------------------------
      // Initialize Google Sheets service.
      // --------------------------------------------------------

      await _sheets.initialize();

      final spreadsheetId =
          _sheets.spreadsheetId;

      if (spreadsheetId == null ||
          spreadsheetId.trim().isEmpty) {
        return _failure(
          'No Google synchronization spreadsheet has been configured.',
        );
      }

      // --------------------------------------------------------
      // Ensure headers are correct.
      // --------------------------------------------------------

      await _sheets.initializeSyncHeaders();

      // --------------------------------------------------------
      // Fixed cutoff for this complete synchronization run.
      // --------------------------------------------------------

      final cutoff =
          DateTime.now()
              .toUtc()
              .toIso8601String();

      var inserted = 0;
      var updated = 0;

      // ========================================================
      // LEARNERS
      // ========================================================

      final learners =
          await _getPendingRows(
        learnersTable,
        cutoff: cutoff,
      );

      if (learners.isNotEmpty) {
        final rows =
            learners
                .map(
                  _learnerToSheetRow,
                )
                .toList();

        final result =
            await _sheets.upsertRowsBySyncId(
          sheetTitle:
              GoogleSheetsService
                  .learnersSheet,
          headers:
              GoogleSheetsService
                  .learnerHeaders,
          rows: rows,
        );

        inserted += result.inserted;
        updated += result.updated;
      }

      for (final row in learners) {
        await _setRecordSyncState(
          learnersTable,
          row,
        );
      }

      await _setLastPushedAt(
        learnersTable,
        cutoff,
      );

      // ========================================================
      // TEACHERS
      // ========================================================

      final teachers =
          await _getPendingRows(
        teachersTable,
        cutoff: cutoff,
      );

      if (teachers.isNotEmpty) {
        final rows =
            teachers
                .map(
                  _teacherToSheetRow,
                )
                .toList();

        final result =
            await _sheets.upsertRowsBySyncId(
          sheetTitle:
              GoogleSheetsService
                  .teachersSheet,
          headers:
              GoogleSheetsService
                  .teacherHeaders,
          rows: rows,
        );

        inserted += result.inserted;
        updated += result.updated;
      }

      for (final row in teachers) {
        await _setRecordSyncState(
          teachersTable,
          row,
        );
      }

      await _setLastPushedAt(
        teachersTable,
        cutoff,
      );

      // ========================================================
      // SECTIONS
      // ========================================================

      final sections =
          await _getPendingRows(
        sectionsTable,
        cutoff: cutoff,
      );

      if (sections.isNotEmpty) {
        final rows =
            sections
                .map(
                  _sectionToSheetRow,
                )
                .toList();

        final result =
            await _sheets.upsertRowsBySyncId(
          sheetTitle:
              GoogleSheetsService
                  .sectionsSheet,
          headers:
              GoogleSheetsService
                  .sectionHeaders,
          rows: rows,
        );

        inserted += result.inserted;
        updated += result.updated;
      }

      for (final row in sections) {
        await _setRecordSyncState(
          sectionsTable,
          row,
        );
      }

      await _setLastPushedAt(
        sectionsTable,
        cutoff,
      );

      // ========================================================
      // SCHOOL HISTORY
      // ========================================================

      final schoolHistory =
          await _getPendingSchoolHistory(
        cutoff,
      );

      if (schoolHistory.isNotEmpty) {
        final rows =
            schoolHistory
                .map(
                  _schoolHistoryToSheetRow,
                )
                .toList();

        final result =
            await _sheets.upsertRowsBySyncId(
          sheetTitle:
              GoogleSheetsService
                  .schoolHistorySheet,
          headers:
              GoogleSheetsService
                  .schoolHistoryHeaders,
          rows: rows,
        );

        inserted += result.inserted;
        updated += result.updated;
      }

      for (final row in schoolHistory) {
        await _setRecordSyncState(
          schoolHistoryTable,
          row,
        );
      }

      await _setLastPushedAt(
        schoolHistoryTable,
        cutoff,
      );

      // ========================================================
      // INCIDENTS
      // ========================================================

      final incidents =
          await _getPendingIncidents(
        cutoff,
      );

      if (incidents.isNotEmpty) {
        final rows =
            incidents
                .map(
                  _incidentToSheetRow,
                )
                .toList();

        final result =
            await _sheets.upsertRowsBySyncId(
          sheetTitle:
              GoogleSheetsService
                  .incidentsSheet,
          headers:
              GoogleSheetsService
                  .incidentHeaders,
          rows: rows,
        );

        inserted += result.inserted;
        updated += result.updated;
      }

      for (final row in incidents) {
        await _setRecordSyncState(
          incidentsTable,
          row,
        );
      }

      await _setLastPushedAt(
        incidentsTable,
        cutoff,
      );

      // ========================================================
      // FINAL RESULT
      // ========================================================

      final remaining =
          await getTotalPendingCount();

      return SyncResult(
        success: true,
        message:
            'Google Sheets synchronization completed.\n\n'
            'Inserted: $inserted\n'
            'Updated: $updated\n'
            'Remaining pending: $remaining',
        learners:
            await _getPendingCount(
          learnersTable,
        ),
        teachers:
            await _getPendingCount(
          teachersTable,
        ),
        sections:
            await _getPendingCount(
          sectionsTable,
        ),
        schoolHistory:
            await _getPendingCount(
          schoolHistoryTable,
        ),
        incidents:
            await _getPendingCount(
          incidentsTable,
        ),
        totalPending:
            remaining,
      );
    } catch (e) {
      return _failure(
        'Google Sheets synchronization failed.\n$e',
      );
    }
  }

  // ============================================================
  // SCHOOL HISTORY + LEARNER SYNC ID
  // ============================================================

  Future<List<Map<String, Object?>>>
      _getPendingSchoolHistory(
    String cutoff,
  ) async {
    return _getPendingJoinedRows(
      table: schoolHistoryTable,
      cutoff: cutoff,
      sql: '''
        SELECT h.*, l.SyncID AS LearnerSyncID
        FROM SCHOOL_HISTORY_Table h
        LEFT JOIN LEARNERS_Table l
          ON l.LearnerID = h.LearnerID
        WHERE h.UpdatedAt <= ?
        ORDER BY h.UpdatedAt ASC
      ''',
    );
  }

  Future<List<Map<String, Object?>>>
      _getPendingIncidents(
    String cutoff,
  ) async {
    return _getPendingJoinedRows(
      table: incidentsTable,
      cutoff: cutoff,
      sql: '''
        SELECT i.*, l.SyncID AS LearnerSyncID
        FROM INCIDENTS_Table i
        LEFT JOIN LEARNERS_Table l
          ON l.LearnerID = i.LearnerID
        WHERE i.UpdatedAt <= ?
        ORDER BY i.UpdatedAt ASC
      ''',
    );
  }

  Future<List<Map<String, Object?>>>
      _getPendingJoinedRows({
    required String table,
    required String cutoff,
    required String sql,
  }) async {
    await _ensureSyncStateTable();

    final db =
        _database.database;

    final legacyWatermark =
        await _getLegacyLastSyncedAt(
      table,
    );

    final rows =
        await db.rawQuery(
      sql,
      [cutoff],
    );

    final states =
        await db.query(
      _syncStateTable,
      columns: [
        'SyncID',
        'SyncedVersion',
        'SyncedUpdatedAt',
      ],
      where: 'TableName = ?',
      whereArgs: [table],
    );

    final stateBySyncId =
        <String, Map<String, Object?>>{};

    for (final state in states) {
      final id =
          state['SyncID']
                  ?.toString()
                  .trim() ??
              '';

      if (id.isNotEmpty) {
        stateBySyncId[id] = state;
      }
    }

    final pending =
        <Map<String, Object?>>[];

    for (final row in rows) {
      final syncId =
          _syncId(row);

      if (syncId.isEmpty) {
        pending.add(row);
        continue;
      }

      final state =
          stateBySyncId[syncId];

      if (state != null) {
        final localVersion =
            _asInt(row['Version']) ?? 1;

        final syncedVersion =
            _asInt(
                  state['SyncedVersion'],
                ) ??
                1;

        final localUpdatedAt =
            row['UpdatedAt']?.toString() ?? '';

        final syncedUpdatedAt =
            state['SyncedUpdatedAt']
                    ?.toString() ??
                '';

        if (localVersion !=
                syncedVersion ||
            localUpdatedAt !=
                syncedUpdatedAt) {
          pending.add(row);
        }

        continue;
      }

      if (legacyWatermark == null ||
          legacyWatermark.trim().isEmpty ||
          _isAfterWatermark(
            row['UpdatedAt'],
            legacyWatermark,
          )) {
        pending.add(row);
      }
    }

    return pending;
  }

  // ============================================================
  // 6.5B — COMPARE REMOTE WITH LOCAL
  //
  // READ ONLY.
  //
  // Nothing is changed in SQLite here.
  // ============================================================

  Future<SyncComparisonResult>
      compareRemoteWithLocal() {
    return _context.exclusive(() => _compareRemoteWithLocal());
  }

  Future<SyncComparisonResult>
      _compareRemoteWithLocal() async {
    await _verifyOwnership();
    await _sheets.initialize();

    if (_sheets.spreadsheetId == null ||
        _sheets.spreadsheetId!.trim().isEmpty) {
      throw StateError(
        'No Google synchronization spreadsheet has been configured.',
      );
    }

    final remote =
        await _sheets.downloadAllTables();

    final comparisons =
        <SyncComparison>[];

    // Load the per-record synchronization baseline once.
    // This is important for restored databases and conflict
    // resolution: a restored record can legitimately have the
    // same SyncID/version/timestamp as the remote row even if
    // SQLite normalizes some values differently during import.
    await _ensureSyncStateTable();

    final syncStates =
        await _database.database.query(
      _syncStateTable,
      columns: [
        'TableName',
        'SyncID',
        'SyncedVersion',
        'SyncedUpdatedAt',
      ],
    );

    final baselineByKey =
        <String, Map<String, Object?>>{};

    for (final state in syncStates) {
      final tableName =
          state['TableName']?.toString().trim() ?? '';
      final syncId =
          state['SyncID']?.toString().trim() ?? '';

      if (tableName.isNotEmpty && syncId.isNotEmpty) {
        baselineByKey['$tableName|$syncId'] = state;
      }
    }

    // ----------------------------------------------------------
    // LEARNERS
    // ----------------------------------------------------------

    final localLearners =
        await _database.database.query(
      learnersTable,
      where: 'Deleted IN (0, 1)',
    );

    comparisons.addAll(
      await _compareTable(
        tableName:
            learnersTable,
        localRows:
            localLearners,
        remoteRows:
            remote.learners,
        baselineByKey:
            baselineByKey,
      ),
    );

    // ----------------------------------------------------------
    // TEACHERS
    // ----------------------------------------------------------

    final localTeachers =
        await _database.database.query(
      teachersTable,
      where: 'Deleted IN (0, 1)',
    );

    comparisons.addAll(
      await _compareTable(
        tableName:
            teachersTable,
        localRows:
            localTeachers,
        remoteRows:
            remote.teachers,
        baselineByKey:
            baselineByKey,
      ),
    );

    // ----------------------------------------------------------
    // SECTIONS
    // ----------------------------------------------------------

    final localSections =
        await _database.database.query(
      sectionsTable,
      where: 'Deleted IN (0, 1)',
    );

    comparisons.addAll(
      await _compareTable(
        tableName:
            sectionsTable,
        localRows:
            localSections,
        remoteRows:
            remote.sections,
        baselineByKey:
            baselineByKey,
      ),
    );

    // ----------------------------------------------------------
    // SCHOOL HISTORY
    // ----------------------------------------------------------

    final localHistory =
        await _getLocalSchoolHistoryForComparison();

    comparisons.addAll(
      await _compareTable(
        tableName:
            schoolHistoryTable,
        localRows:
            localHistory,
        remoteRows:
            remote.schoolHistory,
        baselineByKey:
            baselineByKey,
      ),
    );

    // ----------------------------------------------------------
    // INCIDENTS
    // ----------------------------------------------------------

    final localIncidents =
        await _getLocalIncidentsForComparison();

    comparisons.addAll(
      await _compareTable(
        tableName:
            incidentsTable,
        localRows:
            localIncidents,
        remoteRows:
            remote.incidents,
        baselineByKey:
            baselineByKey,
      ),
    );

    final result =
        SyncComparisonResult(
      comparisons:
          comparisons,
    );

    await _setLastKnownConflictCount(
      result.conflictCount,
    );

    return result;
  }

  // ============================================================
  // LOCAL SCHOOL HISTORY FOR COMPARISON
  // ============================================================

  Future<List<Map<String, Object?>>>
      _getLocalSchoolHistoryForComparison() async {
    final db =
        _database.database;

    return db.rawQuery(
      '''
      SELECT
        h.*,
        l.SyncID AS LearnerSyncID
      FROM SCHOOL_HISTORY_Table h
      LEFT JOIN LEARNERS_Table l
        ON l.LearnerID = h.LearnerID
      WHERE h.Deleted IN (0, 1)
      ''',
    );
  }

  // ============================================================
  // LOCAL INCIDENTS FOR COMPARISON
  // ============================================================

  Future<List<Map<String, Object?>>>
      _getLocalIncidentsForComparison() async {
    final db =
        _database.database;

    return db.rawQuery(
      '''
      SELECT
        i.*,
        l.SyncID AS LearnerSyncID
      FROM INCIDENTS_Table i
      LEFT JOIN LEARNERS_Table l
        ON l.LearnerID = i.LearnerID
      WHERE i.Deleted IN (0, 1)
      ''',
    );
  }

  // ============================================================
  // COMPARE TABLE
  // ============================================================

  Future<List<SyncComparison>> _compareTable({
    required String tableName,
    required List<Map<String, Object?>> localRows,
    required List<Map<String, Object?>> remoteRows,
    required Map<String, Map<String, Object?>> baselineByKey,
  }) async {
    final localBySyncId =
        <String, Map<String, Object?>>{};

    final remoteBySyncId =
        <String, Map<String, Object?>>{};

    // ----------------------------------------------------------
    // Index local records
    // ----------------------------------------------------------

    for (final row in localRows) {
      final syncId =
          _syncId(row);

      if (syncId.isEmpty) {
        continue;
      }

      localBySyncId[syncId] =
          row;
    }

    // ----------------------------------------------------------
    // Index remote records
    // ----------------------------------------------------------

    for (final row in remoteRows) {
      final syncId =
          _syncId(row);

      if (syncId.isEmpty) {
        continue;
      }

      remoteBySyncId[syncId] =
          row;
    }

    final allSyncIds =
        <String>{
      ...localBySyncId.keys,
      ...remoteBySyncId.keys,
    };

    final comparisons =
        <SyncComparison>[];

    for (final syncId in allSyncIds) {
      final local =
          localBySyncId[syncId];

      final remote =
          remoteBySyncId[syncId];

      var status =
          _compareRecord(
        local:
            local,
        remote:
            remote,
      );

      // If both sides still carry the exact synchronization
      // baseline for this record, the record is already resolved.
      // This is especially important after restoring an existing
      // Google Sheet into a fresh SQLite database. The imported
      // row is authoritative for the baseline even when SQLite
      // representation differs slightly from the sheet value.
      if (status == SyncComparisonStatus.conflict) {
        final baseline =
            baselineByKey['$tableName|$syncId'];

        if (baseline != null &&
            _recordMatchesSyncBaseline(
              local,
              baseline,
            ) &&
            _recordMatchesSyncBaseline(
              remote,
              baseline,
            )) {
          status = SyncComparisonStatus.same;
        }
      }

      comparisons.add(
        SyncComparison(
          tableName:
              tableName,
          syncId:
              syncId,
          status:
              status,
          localRecord:
              local,
          remoteRecord:
              remote,
        ),
      );
    }

    // Stable ordering makes the test results easier to read.
    comparisons.sort(
      (a, b) {
        final tableCompare =
            a.tableName.compareTo(
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

  bool _recordMatchesSyncBaseline(
    Map<String, Object?>? record,
    Map<String, Object?> baseline,
  ) {
    if (record == null) {
      return false;
    }

    final recordVersion =
        _asInt(record['Version']) ?? 1;
    final baselineVersion =
        _asInt(baseline['SyncedVersion']) ?? 1;

    final recordUpdatedAt =
        record['UpdatedAt']?.toString() ?? '';
    final baselineUpdatedAt =
        baseline['SyncedUpdatedAt']?.toString() ?? '';

    return recordVersion == baselineVersion &&
        recordUpdatedAt == baselineUpdatedAt;
  }

  // ============================================================
  // COMPARE ONE RECORD
  // ============================================================

  SyncComparisonStatus _compareRecord({
    required Map<String, Object?>? local,
    required Map<String, Object?>? remote,
  }) {
    // ----------------------------------------------------------
    // Only remote exists.
    // ----------------------------------------------------------

    if (local == null &&
        remote != null) {
      return SyncComparisonStatus.newRemote;
    }

    // ----------------------------------------------------------
    // Only local exists.
    // ----------------------------------------------------------

    if (local != null &&
        remote == null) {
      return SyncComparisonStatus.localOnly;
    }

    // ----------------------------------------------------------
    // Both must exist from this point onward.
    // ----------------------------------------------------------

    if (local == null ||
        remote == null) {
      return SyncComparisonStatus.same;
    }

    final localRecord =
        local;

    final remoteRecord =
        remote;

    // ----------------------------------------------------------
    // Version
    // ----------------------------------------------------------

    final localVersion =
        _asInt(
              localRecord['Version'],
            ) ??
            1;

    final remoteVersion =
        _asInt(
              remoteRecord['Version'],
            ) ??
            1;

    // ----------------------------------------------------------
    // UpdatedAt
    // ----------------------------------------------------------

    final localUpdated =
        _parseSyncDate(
      localRecord['UpdatedAt'],
    );

    final remoteUpdated =
        _parseSyncDate(
      remoteRecord['UpdatedAt'],
    );

    // ----------------------------------------------------------
    // Compare actual record data.
    // ----------------------------------------------------------

    final dataSame =
        _recordsHaveSameData(
      localRecord,
      remoteRecord,
    );

    // ----------------------------------------------------------
    // Same version + same data
    // ----------------------------------------------------------

    if (localVersion ==
            remoteVersion &&
        dataSame) {
      return SyncComparisonStatus.same;
    }

    // ----------------------------------------------------------
    // Remote has newer version.
    // ----------------------------------------------------------

    if (remoteVersion >
        localVersion) {
      return SyncComparisonStatus.remoteNewer;
    }

    // ----------------------------------------------------------
    // Local has newer version.
    // ----------------------------------------------------------

    if (localVersion >
        remoteVersion) {
      return SyncComparisonStatus.localNewer;
    }

    // ----------------------------------------------------------
    // Same version, but timestamps differ.
    // ----------------------------------------------------------

    if (localUpdated != null &&
        remoteUpdated != null) {
      if (remoteUpdated.isAfter(
        localUpdated,
      )) {
        return SyncComparisonStatus.remoteNewer;
      }

      if (localUpdated.isAfter(
        remoteUpdated,
      )) {
        return SyncComparisonStatus.localNewer;
      }
    }

    // ----------------------------------------------------------
    // Same version + same timestamp + different data.
    // ----------------------------------------------------------

    return SyncComparisonStatus.conflict;
  }

  // ============================================================
  // RECORD DATA COMPARISON
  // ============================================================

  bool _recordsHaveSameData(
    Map<String, Object?> local,
    Map<String, Object?> remote,
  ) {
    const ignoredFields =
        <String>{
      'LearnerID',
      'TeacherID',
      'SectionID',
      'SchoolHistoryID',
      'IncidentID',
    };

    final keys =
        <String>{
      ...local.keys,
      ...remote.keys,
    };

    for (final key in keys) {
      if (ignoredFields.contains(key)) {
        continue;
      }

      if (key == 'Version' ||
          key == 'UpdatedAt') {
        continue;
      }

      final localValue =
          _normaliseValue(
        local[key],
      );

      final remoteValue =
          _normaliseValue(
        remote[key],
      );

      if (localValue !=
          remoteValue) {
        return false;
      }
    }

    return true;
  }

  // ============================================================
  // SYNC ID
  // ============================================================

  String _syncId(
    Map<String, Object?> row,
  ) {
    return row['SyncID']
            ?.toString()
            .trim() ??
        '';
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

  DateTime? _parseSyncDate(
    Object? value,
  ) {
    final text =
        value?.toString().trim() ??
            '';

    if (text.isEmpty) {
      return null;
    }

    return DateTime.tryParse(
      text,
    );
  }

  // ============================================================
  // NORMALIZE VALUE
  // ============================================================

  String _normaliseValue(
    Object? value,
  ) {
    if (value == null) {
      return '';
    }

    return value
        .toString()
        .trim()
        .toLowerCase();
  }

  // ============================================================
  // LEARNER → GOOGLE SHEETS
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

  List<Object?>
      _schoolHistoryToSheetRow(
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

  List<Object?>
      _incidentToSheetRow(
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
    final syncId =
        _syncId(remote);

    if (syncId.isEmpty) {
      return _ApplyAction.skipped;
    }

    final existing =
        await txn.query(
      learnersTable,
      where: 'SyncID = ?',
      whereArgs: [syncId],
      limit: 1,
    );

    final values =
        <String, Object?>{
      'SyncID': syncId,
      'LearnerReferenceNumber':
          remote['LearnerReferenceNumber'],
      'LastName':
          remote['LastName']?.toString() ?? '',
      'FirstName':
          remote['FirstName']?.toString() ?? '',
      'MiddleName':
          remote['MiddleName'],
      'Sex':
          remote['Sex']?.toString() ?? '',
      'BirthDate':
          remote['BirthDate'],
      'Age':
          _asInt(remote['Age']),
      'PersonalContactNumber':
          remote['PersonalContactNumber'],
      'RegionCode':
          remote['RegionCode'],
      'Region':
          remote['Region'],
      'ProvinceCode':
          remote['ProvinceCode'],
      'Province':
          remote['Province'],
      'CityMunicipalityCode':
          remote['CityMunicipalityCode'],
      'TownMunicipality':
          remote['TownMunicipality'],
      'BarangayCode':
          remote['BarangayCode'],
      'Barangay':
          remote['Barangay'],
      'Purok':
          remote['Purok'],
      'Street':
          remote['Street'],
      'HouseNo':
          remote['HouseNo'],
      'Parents':
          remote['Parents'],
      'Guardian':
          remote['Guardian'],
      'RelationshipToGuardian':
          remote['RelationshipToGuardian'],
      'ParentsContactNumber':
          remote['ParentsContactNumber'],
      'NotesDetails':
          remote['NotesDetails'],
      'CreatedAt':
          remote['CreatedAt']?.toString() ??
              DateTime.now()
                  .toUtc()
                  .toIso8601String(),
      'UpdatedAt':
          remote['UpdatedAt']?.toString() ??
              DateTime.now()
                  .toUtc()
                  .toIso8601String(),
      'DeviceID':
          remote['DeviceID']?.toString() ??
              'google-sheets',
      'Version':
          _asInt(remote['Version']) ?? 1,
      'Deleted':
          _asInt(remote['Deleted']) ?? 0,
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

    final localId =
        existing.first['LearnerID'];

    await txn.update(
      learnersTable,
      values,
      where: 'LearnerID = ?',
      whereArgs: [localId],
    );

    return values['Deleted'] == 1
        ? _ApplyAction.deleted
        : _ApplyAction.updated;
  }

  // ============================================================
  // APPLY TEACHER CHANGE
  // ============================================================

  Future<_ApplyAction> _applyTeacherChange(
    DatabaseExecutor txn,
    Map<String, Object?> remote,
  ) async {
    final syncId =
        _syncId(remote);

    if (syncId.isEmpty) {
      return _ApplyAction.skipped;
    }

    final existing =
        await txn.query(
      teachersTable,
      where: 'SyncID = ?',
      whereArgs: [syncId],
      limit: 1,
    );

    final values =
        <String, Object?>{
      'SyncID': syncId,
      'TeacherName':
          remote['TeacherName']
                  ?.toString() ??
              '',
      'MobileNumber':
          remote['MobileNumber'],
      'Status':
          remote['Status']?.toString() ??
              'Active',
      'CreatedAt':
          remote['CreatedAt']?.toString() ??
              DateTime.now()
                  .toUtc()
                  .toIso8601String(),
      'UpdatedAt':
          remote['UpdatedAt']?.toString() ??
              DateTime.now()
                  .toUtc()
                  .toIso8601String(),
      'DeviceID':
          remote['DeviceID']?.toString() ??
              'google-sheets',
      'Version':
          _asInt(remote['Version']) ?? 1,
      'Deleted':
          _asInt(remote['Deleted']) ?? 0,
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

    return values['Deleted'] == 1
        ? _ApplyAction.deleted
        : _ApplyAction.updated;
  }

  // ============================================================
  // APPLY SECTION CHANGE
  // ============================================================

  Future<_ApplyAction> _applySectionChange(
    DatabaseExecutor txn,
    Map<String, Object?> remote,
  ) async {
    final syncId =
        _syncId(remote);

    if (syncId.isEmpty) {
      return _ApplyAction.skipped;
    }

    final existing =
        await txn.query(
      sectionsTable,
      where: 'SyncID = ?',
      whereArgs: [syncId],
      limit: 1,
    );

    final values =
        <String, Object?>{
      'SyncID':
          syncId,
      'SchoolYear':
          remote['SchoolYear']?.toString() ??
              '',
      'GradeLevel':
          remote['GradeLevel']?.toString() ??
              '',
      'SectionName':
          remote['SectionName']?.toString() ??
              '',
      'Adviser':
          remote['Adviser']?.toString() ??
              '',
      'CreatedAt':
          remote['CreatedAt']?.toString() ??
              DateTime.now()
                  .toUtc()
                  .toIso8601String(),
      'UpdatedAt':
          remote['UpdatedAt']?.toString() ??
              DateTime.now()
                  .toUtc()
                  .toIso8601String(),
      'DeviceID':
          remote['DeviceID']?.toString() ??
              'google-sheets',
      'Version':
          _asInt(remote['Version']) ?? 1,
      'Deleted':
          _asInt(remote['Deleted']) ?? 0,
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

    return values['Deleted'] == 1
        ? _ApplyAction.deleted
        : _ApplyAction.updated;
  }

  // ============================================================
  // FIND LOCAL LEARNER BY SYNC ID
  // ============================================================

  Future<int?> _findLocalLearnerIdBySyncId(
    DatabaseExecutor txn,
    Object? learnerSyncId,
  ) async {
    final syncId =
        learnerSyncId
                ?.toString()
                .trim() ??
            '';

    if (syncId.isEmpty) {
      return null;
    }

    final rows =
        await txn.query(
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

  Future<_ApplyAction>
      _applySchoolHistoryChange(
    DatabaseExecutor txn,
    Map<String, Object?> remote,
  ) async {
    final syncId =
        _syncId(remote);

    if (syncId.isEmpty) {
      return _ApplyAction.skipped;
    }

    final learnerId =
        await _findLocalLearnerIdBySyncId(
      txn,
      remote['LearnerSyncID'],
    );

    // Do NOT use remote LearnerID.
    if (learnerId == null) {
      return _ApplyAction.skipped;
    }

    final existing =
        await txn.query(
      schoolHistoryTable,
      where: 'SyncID = ?',
      whereArgs: [syncId],
      limit: 1,
    );

    final values =
        <String, Object?>{
      'SyncID':
          syncId,
      'LearnerID':
          learnerId,
      'SchoolYear':
          remote['SchoolYear']?.toString() ??
              '',
      'Grade':
          remote['Grade']?.toString() ??
              '',
      'School':
          remote['School']?.toString() ??
              '',
      'Section':
          remote['Section'],
      'Adviser':
          remote['Adviser'],
      'NotesDetails':
          remote['NotesDetails'],
      'CreatedAt':
          remote['CreatedAt']?.toString() ??
              DateTime.now()
                  .toUtc()
                  .toIso8601String(),
      'UpdatedAt':
          remote['UpdatedAt']?.toString() ??
              DateTime.now()
                  .toUtc()
                  .toIso8601String(),
      'DeviceID':
          remote['DeviceID']?.toString() ??
              'google-sheets',
      'Version':
          _asInt(remote['Version']) ?? 1,
      'Deleted':
          _asInt(remote['Deleted']) ?? 0,
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

    return values['Deleted'] == 1
        ? _ApplyAction.deleted
        : _ApplyAction.updated;
  }

  // ============================================================
  // APPLY INCIDENT CHANGE
  // ============================================================

  Future<_ApplyAction>
      _applyIncidentChange(
    DatabaseExecutor txn,
    Map<String, Object?> remote,
  ) async {
    final syncId =
        _syncId(remote);

    if (syncId.isEmpty) {
      return _ApplyAction.skipped;
    }

    final learnerId =
        await _findLocalLearnerIdBySyncId(
      txn,
      remote['LearnerSyncID'],
    );

    // Never use another device's local LearnerID.
    if (learnerId == null) {
      return _ApplyAction.skipped;
    }

    final existing =
        await txn.query(
      incidentsTable,
      where: 'SyncID = ?',
      whereArgs: [syncId],
      limit: 1,
    );

    final values =
        <String, Object?>{
      'SyncID':
          syncId,
      'LearnerID':
          learnerId,
      'IncidentDate':
          remote['IncidentDate']
                  ?.toString() ??
              '',
      'IncidentTime':
          remote['IncidentTime'],
      'Observer':
          remote['Observer'],
      'BehaviorProblem':
          remote['BehaviorProblem']
                  ?.toString() ??
              '',
      'ObservationDetails':
          remote['ObservationDetails'],
      'Intervention':
          remote['Intervention'],
      'ActionTaken':
          remote['ActionTaken'],
      'Remarks':
          remote['Remarks'],
      'Details':
          remote['Details'],
      'CreatedAt':
          remote['CreatedAt']?.toString() ??
              DateTime.now()
                  .toUtc()
                  .toIso8601String(),
      'UpdatedAt':
          remote['UpdatedAt']?.toString() ??
              DateTime.now()
                  .toUtc()
                  .toIso8601String(),
      'DeviceID':
          remote['DeviceID']?.toString() ??
              'google-sheets',
      'Version':
          _asInt(remote['Version']) ?? 1,
      'Deleted':
          _asInt(remote['Deleted']) ?? 0,
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

    return values['Deleted'] == 1
        ? _ApplyAction.deleted
        : _ApplyAction.updated;
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

      final authenticated =
          await _isGoogleAuthenticated();

      if (!authenticated) {
        return _failure(
          'Please sign in with Google first.',
        );
      }

      // ----------------------------------------------------------
      // Initialize Google Sheets
      // ----------------------------------------------------------

      await _sheets.initialize();

      final spreadsheetId =
          _sheets.spreadsheetId;

      if (spreadsheetId == null ||
          spreadsheetId.trim().isEmpty) {
        return _failure(
          'No Google synchronization spreadsheet has been configured.',
        );
      }

      // ----------------------------------------------------------
      // Re-check comparison immediately before resolving.
      // ----------------------------------------------------------

      final comparison =
          await compareRemoteWithLocal();

      final matches =
          comparison.comparisons.where(
        (item) =>
            item.tableName == tableName &&
            item.syncId == syncId,
      ).toList();

      if (matches.isEmpty) {
        return _failure(
          'The specified synchronization record was not found.',
        );
      }

      final item =
          matches.first;

      // ----------------------------------------------------------
      // The record must still be a conflict.
      // ----------------------------------------------------------

      if (item.status !=
          SyncComparisonStatus.conflict) {
        return _failure(
          'The record is no longer in conflict.\n\n'
          'Current status: ${item.status.name}',
        );
      }

      final local =
          item.localRecord;

      if (local == null) {
        return _failure(
          'The local record no longer exists.',
        );
      }

      // ----------------------------------------------------------
      // Keep Local creates a new local revision.
      // ----------------------------------------------------------

      final localVersion =
          _asInt(local['Version']) ?? 1;

      final remoteVersion =
          _asInt(
                item.remoteRecord?['Version'],
              ) ??
              1;

      final resolvedVersion =
          (localVersion > remoteVersion
                  ? localVersion
                  : remoteVersion) +
              1;

      final resolvedUpdatedAt =
          DateTime.now()
              .toUtc()
              .toIso8601String();

      final resolvedLocal =
          Map<String, Object?>.from(local)
            ..['Version'] =
                resolvedVersion
            ..['UpdatedAt'] =
                resolvedUpdatedAt
            ..['DeviceID'] =
                deviceId;

      await _database.database.update(
        tableName,
        {
          'Version':
              resolvedVersion,
          'UpdatedAt':
              resolvedUpdatedAt,
          'DeviceID':
              deviceId,
        },
        where: 'SyncID = ?',
        whereArgs: [syncId],
      );

      // ----------------------------------------------------------
      // Convert resolved local record to sheet row.
      // ----------------------------------------------------------

      final row =
          _buildSheetRowForTable(
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

      final result =
          await _sheets.upsertRowsBySyncId(
        sheetTitle:
            _sheetTitleForTable(
          tableName,
        ),
        headers:
            _headersForTable(
          tableName,
        ),
        rows: [row],
      );

      // ----------------------------------------------------------
      // Mark this table as synced.
      // ----------------------------------------------------------

      final pushedAt =
          DateTime.now()
              .toUtc()
              .toIso8601String();

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
        message:
            'Conflict resolved by keeping the local record.\n\n'
            'Table: $tableName\n'
            'SyncID: $syncId\n'
            'Google Sheets inserted: ${result.inserted}\n'
            'Google Sheets updated: ${result.updated}',
        learners: 0,
        teachers: 0,
        sections: 0,
        schoolHistory: 0,
        incidents: 0,
        totalPending:
            await getTotalPendingCount(),
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

  Future<SyncApplyResult>
      resolveConflictUseRemote({
    required String tableName,
    required String syncId,
  }) {
    return _context.exclusive(() => _resolveConflictUseRemote(
      tableName: tableName,
      syncId: syncId,
    ));
  }

  Future<SyncApplyResult>
      _resolveConflictUseRemote({
    required String tableName,
    required String syncId,
  }) async {
    try {
      await _verifyOwnership();
      // ----------------------------------------------------------
      // Authentication
      // ----------------------------------------------------------

      final authenticated =
          await _isGoogleAuthenticated();

      if (!authenticated) {
        return _applyFailure(
          'Please sign in with Google first.',
        );
      }

      // ----------------------------------------------------------
      // Initialize Google Sheets
      // ----------------------------------------------------------

      await _sheets.initialize();

      final spreadsheetId =
          _sheets.spreadsheetId;

      if (spreadsheetId == null ||
          spreadsheetId.trim().isEmpty) {
        return _applyFailure(
          'No Google synchronization spreadsheet has been configured.',
        );
      }

      // ----------------------------------------------------------
      // Re-check comparison immediately before resolving.
      // ----------------------------------------------------------

      final comparison =
          await compareRemoteWithLocal();

      final matches =
          comparison.comparisons.where(
        (item) =>
            item.tableName == tableName &&
            item.syncId == syncId,
      ).toList();

      if (matches.isEmpty) {
        return _applyFailure(
          'The specified synchronization record was not found.',
        );
      }

      final item =
          matches.first;

      // ----------------------------------------------------------
      // The record must still be a conflict.
      // ----------------------------------------------------------

      if (item.status !=
          SyncComparisonStatus.conflict) {
        return _applyFailure(
          'The record is no longer in conflict.\n\n'
          'Current status: ${item.status.name}',
        );
      }

      final remote =
          item.remoteRecord;

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

  Future<SyncApplyResult>
      _applySingleRemoteRecord({
    required String tableName,
    required Map<String, Object?> remote,
  }) async {
    try {
      var inserted = 0;
      var updated = 0;
      var deleted = 0;
      var skipped = 0;

      await _database.database.transaction(
        (txn) async {
          late _ApplyAction action;

          switch (tableName) {
            case learnersTable:
              action =
                  await _applyLearnerChange(
                txn,
                remote,
              );
              break;

            case teachersTable:
              action =
                  await _applyTeacherChange(
                txn,
                remote,
              );
              break;

            case sectionsTable:
              action =
                  await _applySectionChange(
                txn,
                remote,
              );
              break;

            case schoolHistoryTable:
              action =
                  await _applySchoolHistoryChange(
                txn,
                remote,
              );
              break;

            case incidentsTable:
              action =
                  await _applyIncidentChange(
                txn,
                remote,
              );
              break;

            default:
              action =
                  _ApplyAction.skipped;
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

          if (action !=
              _ApplyAction.skipped) {
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
        DateTime.now()
            .toUtc()
            .toIso8601String(),
      );

      return SyncApplyResult(
        success: true,
        message:
            'Conflict resolved by using the remote record.\n\n'
            'Table: $tableName\n'
            'SyncID: ${_syncId(remote)}\n'
            'Inserted: $inserted\n'
            'Updated: $updated\n'
            'Deleted: $deleted\n'
            'Skipped: $skipped',
        learnersInserted:
            tableName == learnersTable
                ? inserted
                : 0,
        learnersUpdated:
            tableName == learnersTable
                ? updated
                : 0,
        learnersDeleted:
            tableName == learnersTable
                ? deleted
                : 0,
        teachersInserted:
            tableName == teachersTable
                ? inserted
                : 0,
        teachersUpdated:
            tableName == teachersTable
                ? updated
                : 0,
        teachersDeleted:
            tableName == teachersTable
                ? deleted
                : 0,
        sectionsInserted:
            tableName == sectionsTable
                ? inserted
                : 0,
        sectionsUpdated:
            tableName == sectionsTable
                ? updated
                : 0,
        sectionsDeleted:
            tableName == sectionsTable
                ? deleted
                : 0,
        schoolHistoryInserted:
            tableName == schoolHistoryTable
                ? inserted
                : 0,
        schoolHistoryUpdated:
            tableName == schoolHistoryTable
                ? updated
                : 0,
        schoolHistoryDeleted:
            tableName == schoolHistoryTable
                ? deleted
                : 0,
        incidentsInserted:
            tableName == incidentsTable
                ? inserted
                : 0,
        incidentsUpdated:
            tableName == incidentsTable
                ? updated
                : 0,
        incidentsDeleted:
            tableName == incidentsTable
                ? deleted
                : 0,
        skipped:
            skipped,
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

  String get message =>
      'The Google Spreadsheet was restored successfully.\n\n'
      'Imported records: $total.'
      '${preferencesPending ? '\n\nSynchronization settings could not be refreshed. '
          'The local restore is complete; settings recovery will retry on the next synchronization.' : ''}';
}
