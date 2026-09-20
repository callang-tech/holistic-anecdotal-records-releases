import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../database/app_database.dart';
import '../models/sync_record_state.dart';

/// Owns the single active baseline set. SQLite is authoritative; preferences
/// are repaired after an interrupted activation before any baseline is used.
class SyncContextService {
  SyncContextService({
    required Database Function() database,
    Future<SharedPreferences> Function()? preferences,
  }) : _database = database,
       _preferences = preferences ?? SharedPreferences.getInstance;

  static final instance = SyncContextService(
    database: () => AppDatabase.instance.database,
  );

  static const spreadsheetIdKey = 'google_sync_spreadsheet_id';
  static const stateTable = 'SYNC_STATE_Table';
  static const contextTable = 'SYNC_CONTEXT_Table';
  static const _tables = [
    'LEARNERS_Table',
    'TEACHERS_Table',
    'SECTIONS_Table',
    'SCHOOL_HISTORY_Table',
    'INCIDENTS_Table',
  ];

  final Database Function() _database;
  final Future<SharedPreferences> Function() _preferences;
  final Object _zoneKey = Object();
  Future<void> _tail = Future<void>.value();

  /// Reentrant within one operation, serialized against target activation.
  Future<T> exclusive<T>(Future<T> Function() operation) {
    if (Zone.current[_zoneKey] == this) return operation();
    final result = _tail.then((_) => runZoned(
          operation,
          zoneValues: {_zoneKey: this},
        ));
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<void> _ensureTables([DatabaseExecutor? executor]) async {
    final db = executor ?? _database();
    await ensureStateTable(db);
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $contextTable (
        ID INTEGER PRIMARY KEY CHECK (ID = 1),
        SpreadsheetID TEXT,
        PreferencesPending INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  /// Additive migration: legacy baselines stay untrusted until both sides agree.
  static Future<void> ensureStateTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $stateTable (
        TableName TEXT NOT NULL,
        SyncID TEXT NOT NULL,
        SyncedVersion INTEGER NOT NULL DEFAULT 1,
        SyncedUpdatedAt TEXT NOT NULL DEFAULT '',
        SyncedFingerprint TEXT,
        NeedsReview INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (TableName, SyncID)
      )
    ''');
    final columns = await db.rawQuery('PRAGMA table_info($stateTable)');
    final names = columns.map((row) => row['name']).toSet();
    if (!names.contains('SyncedFingerprint')) {
      await db.execute('ALTER TABLE $stateTable ADD COLUMN SyncedFingerprint TEXT');
    }
    if (!names.contains('NeedsReview')) {
      await db.execute('ALTER TABLE $stateTable ADD COLUMN NeedsReview INTEGER NOT NULL DEFAULT 0');
    }
  }

  Future<Map<String, Object?>?> _context() async {
    await _ensureTables();
    final rows = await _database().query(contextTable, where: 'ID = 1');
    return rows.isEmpty ? null : rows.single;
  }

  Iterable<String> get _watermarkKeys sync* {
    for (final table in _tables) {
      yield 'sync_last_synced_$table';
      yield 'sync_last_pushed_$table';
      yield 'sync_last_pulled_$table';
    }
  }

  Future<void> _checkWrite(Future<bool> write) async {
    if (!await write) {
      throw StateError('Unable to persist synchronization settings.');
    }
  }

  Future<void> _repairMirror(Map<String, Object?> context) async {
    final prefs = await _preferences();
    final owner = context['SpreadsheetID'] as String?;
    final mirrorChanged = prefs.getString(spreadsheetIdKey) != owner;
    if (context['PreferencesPending'] == 1 || mirrorChanged) {
      // A mismatched mirror's watermarks cannot be trusted to belong to owner.
      for (final key in _watermarkKeys) {
        if (prefs.containsKey(key)) await _checkWrite(prefs.remove(key));
      }
      await _checkWrite(prefs.setInt('sync_last_conflict_count', 0));
    }
    if (mirrorChanged) {
      await _checkWrite(owner == null
          ? prefs.remove(spreadsheetIdKey)
          : prefs.setString(spreadsheetIdKey, owner));
    }
    if (context['PreferencesPending'] == 1) {
      await _database()
          .update(contextTable, {'PreferencesPending': 0}, where: 'ID = 1');
    }
  }

  Future<String?> activeSpreadsheetId() => exclusive(() async {
        final context = await _context();
        if (context != null) {
          await _repairMirror(context);
          return context['SpreadsheetID'] as String?;
        }
        // Legacy configuration is a candidate, not proof of baseline ownership.
        final prefs = await _preferences();
        final candidate = prefs.getString(spreadsheetIdKey)?.trim();
        return candidate == null || candidate.isEmpty ? null : candidate;
      });

  Future<void> verifyOwner(String? activeId) => exclusive(() async {
        final context = await _context();
        if (context != null) {
          await _repairMirror(context);
          if (context['SpreadsheetID'] != activeId) {
            throw StateError(
                'Synchronization spreadsheet ownership changed. Retry the operation.');
          }
          return;
        }
        final prefs = await _preferences();
        final rows = await _database().query(stateTable, limit: 1);
        if (rows.isNotEmpty || _watermarkKeys.any(prefs.containsKey)) {
          throw StateError(
            'Existing synchronization state has no spreadsheet owner. '
            'Synchronization is blocked until a spreadsheet is explicitly '
            'activated or synchronization state is cleared. Local records are unchanged.',
          );
        }
        if (activeId != null) await activate(activeId);
      });

  /// Explicit activation never adopts unowned baselines. Reconnecting to the
  /// same known owner preserves them; every other activation starts a new set.
  Future<void> activate(String? spreadsheetId) => exclusive(() async {
        final text = spreadsheetId?.trim();
        final target = text == null || text.isEmpty ? null : text;
        final context = await _context();
        if (context != null && context['SpreadsheetID'] == target) {
          await _repairMirror(context);
          return;
        }
        await _replaceContext(target);
      });

  Future<void> clear() => exclusive(() async {
        final target = await activeSpreadsheetId();
        await _replaceContext(target);
      });

  Future<void> _replaceContext(String? owner) async {
    await _database().transaction((txn) async {
      await txn.delete(stateTable);
      await _writeOwner(txn, owner);
    });
    // The durable flag makes cleanup retryable after errors or process exit.
    await _repairMirror((await _context())!);
  }

  /// Called under [exclusive], inside the same transaction as the core import.
  /// Baselines reflect the normalized rows actually stored by the importer.
  /// No preferences are changed until the caller commits and reconciles.
  Future<void> replaceImportedStateInTransaction(
    DatabaseExecutor txn, {
    required String spreadsheetId,
  }) async {
    final owner = spreadsheetId.trim();
    if (owner.isEmpty) throw ArgumentError('Spreadsheet ID is required.');
    await _ensureTables(txn);
    await txn.delete(stateTable);
    for (final table in _tables) {
      final rows = table == 'SCHOOL_HISTORY_Table' || table == 'INCIDENTS_Table'
          ? await txn.rawQuery('''
              SELECT child.*, parent.SyncID AS LearnerSyncID
              FROM $table child LEFT JOIN LEARNERS_Table parent
              ON parent.LearnerID = child.LearnerID
            ''')
          : await txn.query(table);
      for (final row in rows) {
        final syncId = row['SyncID']?.toString().trim() ?? '';
        if (syncId.isEmpty) {
          throw StateError('Imported $table record has no SyncID.');
        }
        await txn.insert(stateTable, {
          'TableName': table,
          'SyncID': syncId,
          'SyncedVersion': row['Version'],
          'SyncedUpdatedAt': row['UpdatedAt'],
          'SyncedFingerprint': SyncRecordState.fingerprint(row),
        }, conflictAlgorithm: ConflictAlgorithm.abort);
      }
    }
    // Also runs for an empty restore. No synthetic watermarks are needed.
    await _writeOwner(txn, owner);
  }

  Future<void> _writeOwner(DatabaseExecutor txn, String? owner) async {
    await txn.insert(
      contextTable,
      {
        'ID': 1,
        'SpreadsheetID': owner,
        'PreferencesPending': 1,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
