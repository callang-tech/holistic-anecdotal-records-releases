import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class AppDatabase {
  AppDatabase._() : _databasePathOverride = null;

  @visibleForTesting
  AppDatabase.forTesting(String databasePath)
      : _databasePathOverride = databasePath;

  final String? _databasePathOverride;

  static final AppDatabase instance =
      AppDatabase._();

  Database? _database;

  // ============================================================
  // DATABASE ACCESS
  // ============================================================

  Database get database {
    final db = _database;

    if (db == null) {
      throw StateError(
        'Database has not been initialized.',
      );
    }

    return db;
  }

  // ============================================================
  // DATABASE PATH
  //
  // Documents/
  //   HolisticAnecdotalRecords/
  //     holistic_anecdotal_records.db
  //
  // ============================================================

  Future<String> _databasePath() async {
    if (_databasePathOverride != null) return _databasePathOverride;
    final documentsDirectory =
        await getApplicationDocumentsDirectory();

    final appDirectory = Directory(
      p.join(
        documentsDirectory.path,
        'HolisticAnecdotalRecords',
      ),
    );

    if (!await appDirectory.exists()) {
      await appDirectory.create(
        recursive: true,
      );
    }

    return p.join(
      appDirectory.path,
      'holistic_anecdotal_records.db',
    );
  }

  // ============================================================
  // INITIALIZE
  // ============================================================

  Future<void> initialize() async {
    if (_database != null) {
      return;
    }

    if (Platform.isWindows ||
        Platform.isLinux ||
        Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory =
          databaseFactoryFfi;
    }

    final path =
        await _databasePath();

    debugPrint(
      'DATABASE PATH: $path',
    );

    _database = await openDatabase(
      path,
      version: 1,
      onCreate: (
        db,
        version,
      ) async {
        await _createSchema(db);
      },
    );
  }

  // ============================================================
  // START FRESH DATABASE
  //
  // Completely removes the current local database and creates
  // a new empty database using the current application schema.
  //
  // This is intentionally a local operation only.
  //
  // It does NOT:
  //   - delete Google Sheet data
  //   - create a new Google Sheet
  //   - modify the cloud database
  //
  // ============================================================

  Future<void> resetDatabase() async {
    final path =
        await _databasePath();

    // ----------------------------------------------------------
    // Close the currently open database first.
    // ----------------------------------------------------------

    final currentDatabase =
        _database;

    if (currentDatabase != null) {
      await currentDatabase.close();
      _database = null;
    }

    // ----------------------------------------------------------
    // Remove the SQLite database and associated temporary files.
    //
    // WAL/SHM files may remain on some systems, so remove them
    // explicitly if they exist.
    // ----------------------------------------------------------

    final databaseFile =
        File(path);

    final walFile =
        File('$path-wal');

    final shmFile =
        File('$path-shm');

    if (await databaseFile.exists()) {
      await databaseFile.delete();
    }

    if (await walFile.exists()) {
      await walFile.delete();
    }

    if (await shmFile.exists()) {
      await shmFile.delete();
    }

    // ----------------------------------------------------------
    // Recreate the database using the current schema.
    // ----------------------------------------------------------

    await initialize();

    debugPrint(
      'DATABASE RESET COMPLETE: $path',
    );
  }

  // ============================================================
  // IMPORT GOOGLE SHEETS DATA
  //
  // Intended for:
  //
  //   Start Fresh Database
  //       +
  //   Import Existing Google Spreadsheet
  //
  // IMPORTANT:
  // This operation expects an EMPTY/FRESH local database.
  //
  // SyncID and synchronization metadata are preserved.
  //
  // Import order:
  //
  //   Teachers
  //   Sections
  //   Learners
  //   School History
  //   Incidents
  //
  // Child records resolve LearnerID through LearnerSyncID.
  //
  // ============================================================

  Future<DatabaseImportResult>
      importSyncedTables({
    required List<Map<String, Object?>> teachers,
    required List<Map<String, Object?>> sections,
    required List<Map<String, Object?>> learners,
    required List<Map<String, Object?>> schoolHistory,
    required List<Map<String, Object?>> incidents,
  }) async {
    await initialize();
    return database.transaction((txn) => _importSyncedTables(
      txn,
      teachers: teachers,
      sections: sections,
      learners: learners,
      schoolHistory: schoolHistory,
      incidents: incidents,
    ));
  }

  /// Replaces core data and synchronization metadata in one transaction.
  /// The callback must use the supplied executor and must not write preferences.
  Future<DatabaseImportResult> replaceSyncedTables({
    required List<Map<String, Object?>> teachers,
    required List<Map<String, Object?>> sections,
    required List<Map<String, Object?>> learners,
    required List<Map<String, Object?>> schoolHistory,
    required List<Map<String, Object?>> incidents,
    required Future<void> Function(DatabaseExecutor txn) establishSyncState,
  }) async {
    await initialize();
    return database.transaction((txn) async {
      for (final table in [
        'INCIDENTS_Table',
        'SCHOOL_HISTORY_Table',
        'LEARNERS_Table',
        'SECTIONS_Table',
        'TEACHERS_Table',
      ]) {
        await txn.delete(table);
      }
      final result = await _importSyncedTables(
        txn,
        teachers: teachers,
        sections: sections,
        learners: learners,
        schoolHistory: schoolHistory,
        incidents: incidents,
      );
      await establishSyncState(txn);
      return result;
    });
  }

  Future<DatabaseImportResult> _importSyncedTables(
    DatabaseExecutor txn, {
    required List<Map<String, Object?>> teachers,
    required List<Map<String, Object?>> sections,
    required List<Map<String, Object?>> learners,
    required List<Map<String, Object?>> schoolHistory,
    required List<Map<String, Object?>> incidents,
  }) async {
    var importedTeachers = 0;
    var importedSections = 0;
    var importedLearners = 0;
    var importedSchoolHistory = 0;
    var importedIncidents = 0;

    final learnerSyncToLocalId =
        <String, int>{};

    // ======================================================
    // TEACHERS
    // ======================================================

    for (final source
        in teachers) {
      final row =
          _teacherImportRow(
        source,
      );

      await txn.insert(
        'TEACHERS_Table',
        row,
        conflictAlgorithm:
            ConflictAlgorithm.abort,
      );

      importedTeachers++;
    }

    // ======================================================
    // SECTIONS
    // ======================================================

    for (final source
        in sections) {
      final row =
          _sectionImportRow(
        source,
      );

      await txn.insert(
        'SECTIONS_Table',
        row,
        conflictAlgorithm:
            ConflictAlgorithm.abort,
      );

      importedSections++;
    }

    // ======================================================
    // LEARNERS
    // ======================================================

    for (final source
        in learners) {
      final row =
          _learnerImportRow(
        source,
      );

      final localId =
          await txn.insert(
        'LEARNERS_Table',
        row,
        conflictAlgorithm:
            ConflictAlgorithm.abort,
      );

      final syncId =
          _stringValue(
        source['SyncID'],
      );

      if (syncId.isNotEmpty) {
        learnerSyncToLocalId[
            syncId] = localId;
      }

      importedLearners++;
    }

    // ======================================================
    // SCHOOL HISTORY
    // ======================================================

    for (final source
        in schoolHistory) {
      final learnerId =
          _resolveLearnerId(
        source,
        learnerSyncToLocalId,
      );

      if (learnerId == null) {
        throw StateError(
          'Cannot import School History record '
          '"${_stringValue(source['SyncID'])}". '
          'The referenced learner could not be found.',
        );
      }

      final row =
          _schoolHistoryImportRow(
        source,
        learnerId,
      );

      await txn.insert(
        'SCHOOL_HISTORY_Table',
        row,
        conflictAlgorithm:
            ConflictAlgorithm.abort,
      );

      importedSchoolHistory++;
    }

    // ======================================================
    // INCIDENTS
    // ======================================================

    for (final source
        in incidents) {
      final learnerId =
          _resolveLearnerId(
        source,
        learnerSyncToLocalId,
      );

      if (learnerId == null) {
        throw StateError(
          'Cannot import Incident record '
          '"${_stringValue(source['SyncID'])}". '
          'The referenced learner could not be found.',
        );
      }

      final row =
          _incidentImportRow(
        source,
        learnerId,
      );

      await txn.insert(
        'INCIDENTS_Table',
        row,
        conflictAlgorithm:
            ConflictAlgorithm.abort,
      );

      importedIncidents++;
    }

    return DatabaseImportResult(
      teachers:
          importedTeachers,
      sections:
          importedSections,
      learners:
          importedLearners,
      schoolHistory:
          importedSchoolHistory,
      incidents:
          importedIncidents,
    );
  }

  // ============================================================
  // RESOLVE LEARNER ID
  // ============================================================

  int? _resolveLearnerId(
    Map<String, Object?> source,
    Map<String, int> learnerSyncToLocalId,
  ) {
    final learnerSyncId =
        _stringValue(
      source['LearnerSyncID'],
    );

    // Integer IDs are device-local and cannot resolve imported relationships.
    return learnerSyncToLocalId[learnerSyncId];
  }

  // ============================================================
  // TEACHER IMPORT ROW
  // ============================================================

  Map<String, Object?> _teacherImportRow(
    Map<String, Object?> source,
  ) {
    return {
      'SyncID':
          _requiredString(
            source,
            'SyncID',
          ),
      'TeacherName':
          _requiredString(
            source,
            'TeacherName',
          ),
      'MobileNumber':
          _nullableString(
            source['MobileNumber'],
          ),
      'Status':
          _requiredString(
            source,
            'Status',
            fallback: 'Active',
          ),
      'CreatedAt':
          _requiredString(
            source,
            'CreatedAt',
          ),
      'UpdatedAt':
          _requiredString(
            source,
            'UpdatedAt',
          ),
      'DeviceID':
          _requiredString(
            source,
            'DeviceID',
          ),
      'Version':
          _intValue(
                source['Version'],
              ) ??
              1,
      'Deleted':
          _intValue(
                source['Deleted'],
              ) ??
              0,
    };
  }

  // ============================================================
  // SECTION IMPORT ROW
  // ============================================================

  Map<String, Object?> _sectionImportRow(
    Map<String, Object?> source,
  ) {
    return {
      'SyncID':
          _requiredString(
            source,
            'SyncID',
          ),
      'SchoolYear':
          _requiredString(
            source,
            'SchoolYear',
          ),
      'GradeLevel':
          _requiredString(
            source,
            'GradeLevel',
          ),
      'SectionName':
          _requiredString(
            source,
            'SectionName',
          ),
      'Adviser':
          _nullableString(
            source['Adviser'],
          ) ??
          '',
      'CreatedAt':
          _requiredString(
            source,
            'CreatedAt',
          ),
      'UpdatedAt':
          _requiredString(
            source,
            'UpdatedAt',
          ),
      'DeviceID':
          _requiredString(
            source,
            'DeviceID',
          ),
      'Version':
          _intValue(
                source['Version'],
              ) ??
              1,
      'Deleted':
          _intValue(
                source['Deleted'],
              ) ??
              0,
    };
  }

  // ============================================================
  // LEARNER IMPORT ROW
  // ============================================================

  Map<String, Object?> _learnerImportRow(
    Map<String, Object?> source,
  ) {
    return {
      'SyncID':
          _requiredString(
            source,
            'SyncID',
          ),
      'LearnerReferenceNumber':
          _nullableString(
            source['LearnerReferenceNumber'],
          ),
      'LastName':
          _requiredString(
            source,
            'LastName',
          ),
      'FirstName':
          _requiredString(
            source,
            'FirstName',
          ),
      'MiddleName':
          _nullableString(
            source['MiddleName'],
          ),
      'Sex':
          _requiredString(
            source,
            'Sex',
          ),
      'BirthDate':
          _nullableString(
            source['BirthDate'],
          ),
      'Age':
          _intValue(
            source['Age'],
          ),
      'PersonalContactNumber':
          _nullableString(
            source['PersonalContactNumber'],
          ),
      'RegionCode':
          _nullableString(
            source['RegionCode'],
          ),
      'Region':
          _nullableString(
            source['Region'],
          ),
      'ProvinceCode':
          _nullableString(
            source['ProvinceCode'],
          ),
      'Province':
          _nullableString(
            source['Province'],
          ),
      'CityMunicipalityCode':
          _nullableString(
            source['CityMunicipalityCode'],
          ),
      'TownMunicipality':
          _nullableString(
            source['TownMunicipality'],
          ),
      'BarangayCode':
          _nullableString(
            source['BarangayCode'],
          ),
      'Barangay':
          _nullableString(
            source['Barangay'],
          ),
      'Purok':
          _nullableString(
            source['Purok'],
          ),
      'Street':
          _nullableString(
            source['Street'],
          ),
      'HouseNo':
          _nullableString(
            source['HouseNo'],
          ),
      'Parents':
          _nullableString(
            source['Parents'],
          ),
      'Guardian':
          _nullableString(
            source['Guardian'],
          ),
      'RelationshipToGuardian':
          _nullableString(
            source['RelationshipToGuardian'],
          ),
      'ParentsContactNumber':
          _nullableString(
            source['ParentsContactNumber'],
          ),
      'NotesDetails':
          _nullableString(
            source['NotesDetails'],
          ),
      'CreatedAt':
          _requiredString(
            source,
            'CreatedAt',
          ),
      'UpdatedAt':
          _requiredString(
            source,
            'UpdatedAt',
          ),
      'DeviceID':
          _requiredString(
            source,
            'DeviceID',
          ),
      'Version':
          _intValue(
                source['Version'],
              ) ??
              1,
      'Deleted':
          _intValue(
                source['Deleted'],
              ) ??
              0,
    };
  }

  // ============================================================
  // SCHOOL HISTORY IMPORT ROW
  // ============================================================

  Map<String, Object?> _schoolHistoryImportRow(
    Map<String, Object?> source,
    int learnerId,
  ) {
    return {
      'SyncID':
          _requiredString(
            source,
            'SyncID',
          ),
      'LearnerID':
          learnerId,
      'SchoolYear':
          _requiredString(
            source,
            'SchoolYear',
          ),
      'Grade':
          _requiredString(
            source,
            'Grade',
          ),
      'School':
          _requiredString(
            source,
            'School',
          ),
      'Section':
          _nullableString(
            source['Section'],
          ),
      'Adviser':
          _nullableString(
            source['Adviser'],
          ),
      'NotesDetails':
          _nullableString(
            source['NotesDetails'],
          ),
      'CreatedAt':
          _requiredString(
            source,
            'CreatedAt',
          ),
      'UpdatedAt':
          _requiredString(
            source,
            'UpdatedAt',
          ),
      'DeviceID':
          _requiredString(
            source,
            'DeviceID',
          ),
      'Version':
          _intValue(
                source['Version'],
              ) ??
              1,
      'Deleted':
          _intValue(
                source['Deleted'],
              ) ??
              0,
    };
  }

  // ============================================================
  // INCIDENT IMPORT ROW
  // ============================================================

  Map<String, Object?> _incidentImportRow(
    Map<String, Object?> source,
    int learnerId,
  ) {
    return {
      'SyncID':
          _requiredString(
            source,
            'SyncID',
          ),
      'LearnerID':
          learnerId,
      'IncidentDate':
          _requiredString(
            source,
            'IncidentDate',
          ),
      'IncidentTime':
          _nullableString(
            source['IncidentTime'],
          ),
      'Observer':
          _nullableString(
            source['Observer'],
          ),
      'BehaviorProblem':
          _requiredString(
            source,
            'BehaviorProblem',
          ),
      'ObservationDetails':
          _nullableString(
            source['ObservationDetails'],
          ),
      'Intervention':
          _nullableString(
            source['Intervention'],
          ),
      'ActionTaken':
          _nullableString(
            source['ActionTaken'],
          ),
      'Remarks':
          _nullableString(
            source['Remarks'],
          ),
      'Details':
          _nullableString(
            source['Details'],
          ),
      'CreatedAt':
          _requiredString(
            source,
            'CreatedAt',
          ),
      'UpdatedAt':
          _requiredString(
            source,
            'UpdatedAt',
          ),
      'DeviceID':
          _requiredString(
            source,
            'DeviceID',
          ),
      'Version':
          _intValue(
                source['Version'],
              ) ??
              1,
      'Deleted':
          _intValue(
                source['Deleted'],
              ) ??
              0,
    };
  }

  // ============================================================
  // VALUE HELPERS
  // ============================================================

  String _stringValue(
    Object? value,
  ) {
    return value
            ?.toString()
            .trim() ??
        '';
  }

  String? _nullableString(
    Object? value,
  ) {
    final text =
        _stringValue(value);

    return text.isEmpty
        ? null
        : text;
  }

  String _requiredString(
    Map<String, Object?> source,
    String key, {
    String? fallback,
  }) {
    final value =
        _stringValue(
      source[key],
    );

    if (value.isNotEmpty) {
      return value;
    }

    if (fallback != null) {
      return fallback;
    }

    throw StateError(
      'Imported record is missing required field "$key".',
    );
  }

  int? _intValue(
    Object? value,
  ) {
    if (value == null) {
      return null;
    }

    if (value is int) {
      return value;
    }

    if (value is double) {
      return value.toInt();
    }

    final text =
        value.toString().trim();

    if (text.isEmpty) {
      return null;
    }

    return int.tryParse(text) ??
        double.tryParse(text)?.toInt();
  }

  // ============================================================
  // CREATE COMPLETE DATABASE SCHEMA
  // ============================================================

  Future<void> _createSchema(
    Database db,
  ) async {
    // ==========================================================
    // TEACHERS
    // ==========================================================

    await db.execute('''
      CREATE TABLE TEACHERS_Table (
        TeacherID INTEGER PRIMARY KEY AUTOINCREMENT,

        SyncID TEXT UNIQUE,

        TeacherName TEXT NOT NULL,
        MobileNumber TEXT,
        Status TEXT NOT NULL DEFAULT 'Active',

        CreatedAt TEXT NOT NULL,
        UpdatedAt TEXT NOT NULL,
        DeviceID TEXT NOT NULL,
        Version INTEGER NOT NULL DEFAULT 1,
        Deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // ==========================================================
    // SECTIONS
    // ==========================================================

    await db.execute('''
      CREATE TABLE SECTIONS_Table (
        SectionID INTEGER PRIMARY KEY AUTOINCREMENT,

        SyncID TEXT UNIQUE,

        SchoolYear TEXT NOT NULL,
        GradeLevel TEXT NOT NULL,
        SectionName TEXT NOT NULL,
        Adviser TEXT NOT NULL,

        CreatedAt TEXT NOT NULL,
        UpdatedAt TEXT NOT NULL,
        DeviceID TEXT NOT NULL,
        Version INTEGER NOT NULL DEFAULT 1,
        Deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // ==========================================================
    // LEARNERS
    // ==========================================================

    await db.execute('''
      CREATE TABLE LEARNERS_Table (
        LearnerID INTEGER PRIMARY KEY AUTOINCREMENT,

        SyncID TEXT UNIQUE,

        LearnerReferenceNumber TEXT,

        LastName TEXT NOT NULL,
        FirstName TEXT NOT NULL,
        MiddleName TEXT,

        Sex TEXT NOT NULL,

        BirthDate TEXT,
        Age INTEGER,

        PersonalContactNumber TEXT,

        RegionCode TEXT,
        Region TEXT,

        ProvinceCode TEXT,
        Province TEXT,

        CityMunicipalityCode TEXT,
        TownMunicipality TEXT,

        BarangayCode TEXT,
        Barangay TEXT,

        Purok TEXT,
        Street TEXT,
        HouseNo TEXT,

        Parents TEXT,
        Guardian TEXT,
        RelationshipToGuardian TEXT,
        ParentsContactNumber TEXT,

        NotesDetails TEXT,

        CreatedAt TEXT NOT NULL,
        UpdatedAt TEXT NOT NULL,
        DeviceID TEXT NOT NULL,
        Version INTEGER NOT NULL DEFAULT 1,
        Deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // ==========================================================
    // SCHOOL HISTORY
    // ==========================================================

    await db.execute('''
      CREATE TABLE SCHOOL_HISTORY_Table (
        SchoolHistoryID INTEGER PRIMARY KEY AUTOINCREMENT,

        SyncID TEXT UNIQUE,

        LearnerID INTEGER NOT NULL,

        SchoolYear TEXT NOT NULL,
        Grade TEXT NOT NULL,
        School TEXT NOT NULL,

        Section TEXT,
        Adviser TEXT,

        NotesDetails TEXT,

        CreatedAt TEXT NOT NULL,
        UpdatedAt TEXT NOT NULL,
        DeviceID TEXT NOT NULL,
        Version INTEGER NOT NULL DEFAULT 1,
        Deleted INTEGER NOT NULL DEFAULT 0,

        FOREIGN KEY (LearnerID)
          REFERENCES LEARNERS_Table(LearnerID)
      )
    ''');

    // ==========================================================
    // INCIDENTS
    // ==========================================================

    await db.execute('''
      CREATE TABLE INCIDENTS_Table (
        IncidentID INTEGER PRIMARY KEY AUTOINCREMENT,

        SyncID TEXT UNIQUE,

        LearnerID INTEGER NOT NULL,

        IncidentDate TEXT NOT NULL,
        IncidentTime TEXT,

        Observer TEXT,

        BehaviorProblem TEXT NOT NULL,

        ObservationDetails TEXT,
        Intervention TEXT,
        ActionTaken TEXT,
        Remarks TEXT,
        Details TEXT,

        CreatedAt TEXT NOT NULL,
        UpdatedAt TEXT NOT NULL,
        DeviceID TEXT NOT NULL,
        Version INTEGER NOT NULL DEFAULT 1,
        Deleted INTEGER NOT NULL DEFAULT 0,

        FOREIGN KEY (LearnerID)
          REFERENCES LEARNERS_Table(LearnerID)
      )
    ''');

    // ==========================================================
    // INDEXES
    // ==========================================================

    await db.execute('''
      CREATE INDEX idx_learners_name
      ON LEARNERS_Table(
        LastName,
        FirstName,
        MiddleName
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_incidents_learner_date
      ON INCIDENTS_Table(
        LearnerID,
        IncidentDate
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_school_history_learner
      ON SCHOOL_HISTORY_Table(
        LearnerID
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_sections_school_year_grade
      ON SECTIONS_Table(
        SchoolYear,
        GradeLevel
      )
    ''');

    // ==========================================================
    // STABLE SYNC ID TRIGGERS
    // ==========================================================

    await _createSyncIdTrigger(
      db: db,
      table: 'LEARNERS_Table',
      primaryKey: 'LearnerID',
      triggerName: 'trg_learners_syncid',
    );

    await _createSyncIdTrigger(
      db: db,
      table: 'TEACHERS_Table',
      primaryKey: 'TeacherID',
      triggerName: 'trg_teachers_syncid',
    );

    await _createSyncIdTrigger(
      db: db,
      table: 'SECTIONS_Table',
      primaryKey: 'SectionID',
      triggerName: 'trg_sections_syncid',
    );

    await _createSyncIdTrigger(
      db: db,
      table: 'SCHOOL_HISTORY_Table',
      primaryKey: 'SchoolHistoryID',
      triggerName: 'trg_school_history_syncid',
    );

    await _createSyncIdTrigger(
      db: db,
      table: 'INCIDENTS_Table',
      primaryKey: 'IncidentID',
      triggerName: 'trg_incidents_syncid',
    );
  }

  // ============================================================
  // CREATE SYNC ID TRIGGER
  // ============================================================

  Future<void> _createSyncIdTrigger({
    required Database db,
    required String table,
    required String primaryKey,
    required String triggerName,
  }) async {
    await db.execute('''
      CREATE TRIGGER $triggerName
      AFTER INSERT ON $table
      FOR EACH ROW
      WHEN NEW.SyncID IS NULL
        OR TRIM(NEW.SyncID) = ''
      BEGIN
        UPDATE $table
        SET SyncID = lower(hex(randomblob(16)))
        WHERE $primaryKey = NEW.$primaryKey;
      END
    ''');
  }
}

// ================================================================
// DATABASE IMPORT RESULT
// ================================================================

class DatabaseImportResult {
  const DatabaseImportResult({
    required this.teachers,
    required this.sections,
    required this.learners,
    required this.schoolHistory,
    required this.incidents,
  });

  final int teachers;
  final int sections;
  final int learners;
  final int schoolHistory;
  final int incidents;

  int get total =>
      teachers +
      sections +
      learners +
      schoolHistory +
      incidents;
}
