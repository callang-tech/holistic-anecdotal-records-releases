import 'package:flutter/foundation.dart';

import 'app_database.dart';

class DatabaseRepository {
  DatabaseRepository._();

  static final DatabaseRepository instance =
      DatabaseRepository._();

  final AppDatabase _database = AppDatabase.instance;

  // ============================================================
  // GENERAL HELPERS
  // ============================================================

  String _now() {
    return DateTime.now().toUtc().toIso8601String();
  }

  String _deviceId() {
    return defaultTargetPlatform.name;
  }

  String? _nullIfEmpty(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }

    return value.trim();
  }

  bool _hasText(String? value) {
    return value != null && value.trim().isNotEmpty;
  }

  int? _asInt(Object? value) {
  if (value is int) {
    return value;
  }

  return int.tryParse(
    value?.toString() ?? '',
  );
}


  String? _asGrade(Object? value) {
    if (value == null) {
      return null;
    }

    final text = value.toString().trim();

    if (text.isEmpty) {
      return null;
    }

    return text;
  }



  // ============================================================
  // LEARNERS
  // ============================================================

  Future<int> addLearner({
    required String lastName,
    required String firstName,
    String? middleName,
    String? lrn,
    required String sex,
    String? birthDate,
    int? age,
    String? contact,

    String? regionCode,
    String? region,

    String? provinceCode,
    String? province,

    String? municipalityCode,
    String? municipality,

    String? barangayCode,
    String? barangay,

    String? purok,
    String? street,
    String? houseNo,
    String? parents,
    String? guardian,
    String? relationship,
    String? parentContact,
    String? notes,
  }) async {
    final now = _now();

    return _database.database.insert(
      'LEARNERS_Table',
      {
        'LearnerReferenceNumber': _nullIfEmpty(lrn),
        'LastName': lastName.trim(),
        'FirstName': firstName.trim(),
        'MiddleName': _nullIfEmpty(middleName),
        'Sex': sex,
        'BirthDate': _nullIfEmpty(birthDate),
        'Age': age,
        'PersonalContactNumber':
            _nullIfEmpty(contact),

        'RegionCode': _nullIfEmpty(regionCode),
        'Region': _nullIfEmpty(region),

        'ProvinceCode': _nullIfEmpty(provinceCode),
        'Province': _nullIfEmpty(province),

        'CityMunicipalityCode':
            _nullIfEmpty(municipalityCode),
        'TownMunicipality':
            _nullIfEmpty(municipality),

        'BarangayCode': _nullIfEmpty(barangayCode),
        'Barangay': _nullIfEmpty(barangay),

        'Purok': _nullIfEmpty(purok),
        'Street': _nullIfEmpty(street),
        'HouseNo': _nullIfEmpty(houseNo),
        'Parents': _nullIfEmpty(parents),
        'Guardian': _nullIfEmpty(guardian),
        'RelationshipToGuardian':
            _nullIfEmpty(relationship),
        'ParentsContactNumber':
            _nullIfEmpty(parentContact),
        'NotesDetails': _nullIfEmpty(notes),

        'CreatedAt': now,
        'UpdatedAt': now,
        'DeviceID': _deviceId(),
        'Version': 1,
        'Deleted': 0,
      },
    );
  }

  // ============================================================
  // ADD LEARNER + SCHOOL HISTORY
  // ATOMIC TRANSACTION
  // ============================================================

  Future<int> addLearnerWithSchoolHistory({
    required String lastName,
    required String firstName,
    String? middleName,
    String? lrn,
    required String sex,
    String? birthDate,
    int? age,
    String? contact,

    String? regionCode,
    String? region,

    String? provinceCode,
    String? province,

    String? municipalityCode,
    String? municipality,

    String? barangayCode,
    String? barangay,

    String? purok,
    String? street,
    String? houseNo,
    String? parents,
    String? guardian,
    String? relationship,
    String? parentContact,
    String? notes,

    required List<Map<String, Object?>> schoolHistory,
  }) async {
    final now = _now();
    final deviceId = _deviceId();

    return _database.database.transaction<int>(
      (txn) async {
        final learnerId = await txn.insert(
          'LEARNERS_Table',
          {
            'LearnerReferenceNumber':
                _nullIfEmpty(lrn),
            'LastName': lastName.trim(),
            'FirstName': firstName.trim(),
            'MiddleName':
                _nullIfEmpty(middleName),
            'Sex': sex,
            'BirthDate':
                _nullIfEmpty(birthDate),
            'Age': age,
            'PersonalContactNumber':
                _nullIfEmpty(contact),

            'RegionCode':
                _nullIfEmpty(regionCode),
            'Region':
                _nullIfEmpty(region),

            'ProvinceCode':
                _nullIfEmpty(provinceCode),
            'Province':
                _nullIfEmpty(province),

            'CityMunicipalityCode':
                _nullIfEmpty(municipalityCode),
            'TownMunicipality':
                _nullIfEmpty(municipality),

            'BarangayCode':
                _nullIfEmpty(barangayCode),
            'Barangay':
                _nullIfEmpty(barangay),

            'Purok': _nullIfEmpty(purok),
            'Street': _nullIfEmpty(street),
            'HouseNo':
                _nullIfEmpty(houseNo),
            'Parents':
                _nullIfEmpty(parents),
            'Guardian':
                _nullIfEmpty(guardian),
            'RelationshipToGuardian':
                _nullIfEmpty(relationship),
            'ParentsContactNumber':
                _nullIfEmpty(parentContact),
            'NotesDetails':
                _nullIfEmpty(notes),

            'CreatedAt': now,
            'UpdatedAt': now,
            'DeviceID': deviceId,
            'Version': 1,
            'Deleted': 0,
          },
        );

        for (final history in schoolHistory) {
          await txn.insert(
            'SCHOOL_HISTORY_Table',
            {
              'LearnerID': learnerId,
              'SchoolYear':
                  history['SchoolYear'],
              'Grade': history['Grade'],
              'School': history['School'],
              'Section':
                  history['Section']?.toString().trim() ?? '',
              'Adviser':
                  history['Adviser']?.toString().trim() ?? '',
              'NotesDetails':
                  _nullIfEmpty(
                history['Notes']?.toString(),
              ),
              'CreatedAt': now,
              'UpdatedAt': now,
              'DeviceID': deviceId,
              'Version': 1,
              'Deleted': 0,
            },
          );
        }

        return learnerId;
      },
    );
  }

  Future<Map<String, Object?>?> getLearner(
  int learnerId,
) async {
  final rows = await _database.database.query(
    'LEARNERS_Table',
    where: 'LearnerID = ? AND Deleted = 0',
    whereArgs: [learnerId],
    limit: 1,
  );

  return rows.isEmpty ? null : rows.first;
}

  Future<List<Map<String, Object?>>>
      getAllLearners() {
    return _database.database.query(
      'LEARNERS_Table',
      where: 'Deleted = 0',
      orderBy:
          'LastName COLLATE NOCASE, '
          'FirstName COLLATE NOCASE',
    );
  }

  Future<int> updateLearnerFields({
    required int learnerId,
    String? lrn,
    required String lastName,
    required String firstName,
    String? middleName,
    String? sex,
    String? birthDate,
    int? age,
    
    String? schoolYearLastEnrolled,
    String? houseNo,
    String? street,
    String? purok,

    String? barangayCode,
    String? barangay,

    String? municipalityCode,
    String? townMunicipality,

    String? provinceCode,
    String? province,

    String? regionCode,
    String? region,

    String? parents,
    String? guardian,
    String? relationshipToGuardian,
    String? contactNumber,
    String? parentContactNumber,
    String? notesDetails,
  }) async {
    final db = _database.database;

    // ------------------------------------------------------------
    // GET CURRENT VERSION
    // ------------------------------------------------------------
    final existing = await db.query(
      'LEARNERS_Table',
      columns: ['Version'],
      where: 'LearnerID = ?',
      whereArgs: [learnerId],
      limit: 1,
    );

    if (existing.isEmpty) {
      throw StateError(
        'Learner record could not be found.',
      );
    }

    final currentVersion =
        int.tryParse(
              existing.first['Version']?.toString() ?? '',
            ) ??
            1;

    // ------------------------------------------------------------
    // UPDATE LEARNER
    // ------------------------------------------------------------
    return db.update(
      'LEARNERS_Table',
      {
        'LearnerReferenceNumber':
            _nullIfEmpty(lrn),

        'LastName':
            lastName.trim(),

        'FirstName':
            firstName.trim(),

        'MiddleName':
            _nullIfEmpty(middleName),

        'Sex':
            _nullIfEmpty(sex),

        'BirthDate':
            _nullIfEmpty(birthDate),

        'Age':
            age,

        'PersonalContactNumber':
            _nullIfEmpty(contactNumber),

        'HouseNo':
            _nullIfEmpty(houseNo),

        'Street':
            _nullIfEmpty(street),

        'Purok':
            _nullIfEmpty(purok),

        'BarangayCode':
            _nullIfEmpty(barangayCode),

        'Barangay':
            _nullIfEmpty(barangay),

        'CityMunicipalityCode':
            _nullIfEmpty(municipalityCode),

        'TownMunicipality':
            _nullIfEmpty(townMunicipality),

        'ProvinceCode':
            _nullIfEmpty(provinceCode),

        'Province':
            _nullIfEmpty(province),

        'RegionCode':
            _nullIfEmpty(regionCode),

        'Region':
            _nullIfEmpty(region),

        'Parents':
            _nullIfEmpty(parents),

        'Guardian':
            _nullIfEmpty(guardian),

        'RelationshipToGuardian':
            _nullIfEmpty(
              relationshipToGuardian,
            ),

        'ParentsContactNumber':
            _nullIfEmpty(
              parentContactNumber,
            ),

        'NotesDetails':
            _nullIfEmpty(notesDetails),

        // ----------------------------------------------------------
        // SYNCHRONIZATION FIELDS
        // ----------------------------------------------------------
        'UpdatedAt':
            _now(),

        'DeviceID':
            _deviceId(),

        'Version':
            currentVersion + 1,
      },
      where: 'LearnerID = ?',
      whereArgs: [learnerId],
    );
  }

  Future<int> archiveLearner({
    required int learnerId,
  }) async {
    final db = _database.database;

    final existing = await db.query(
      'LEARNERS_Table',
      columns: [
        'LearnerID',
        'SyncID',
        'Version',
        'Deleted',
      ],
      where: 'LearnerID = ?',
      whereArgs: [learnerId],
      limit: 1,
    );

    if (existing.isEmpty) {
      throw StateError(
        'Learner record could not be found.',
      );
    }

    final row = existing.first;

    final deleted =
        int.tryParse(
              row['Deleted']?.toString() ?? '',
            ) ??
            0;

    if (deleted == 1) {
      return 0;
    }

    final currentVersion =
        int.tryParse(
              row['Version']?.toString() ?? '',
            ) ??
            1;

    return db.update(
      'LEARNERS_Table',
      {
        'Deleted': 1,
        'UpdatedAt': _now(),
        'DeviceID': _deviceId(),
        'Version': currentVersion + 1,
      },
      where: 'LearnerID = ?',
      whereArgs: [learnerId],
    );
  }

  // ============================================================
  // ARCHIVED LEARNERS
  // ============================================================

  Future<List<Map<String, Object?>>>
      getArchivedLearners() async {
    final db =
      _database.database;

    return db.query(
      'LEARNERS_Table',
      where: 'Deleted = ?',
      whereArgs: [1],
      orderBy:
          'LastName ASC, FirstName ASC, MiddleName ASC',
    );
  }

  // ============================================================
  // RESTORE LEARNER
  // ============================================================

  Future<int> restoreLearner({
    required int learnerId,
  }) async {
    final db =
     _database.database;

    final current =
        await db.query(
      'LEARNERS_Table',
      columns: [
        'Version',
      ],
      where: 'LearnerID = ?',
      whereArgs: [
        learnerId,
      ],
      limit: 1,
    );

    if (current.isEmpty) {
      throw StateError(
        'Learner record not found.',
      );
    }

    final currentVersion =
        int.tryParse(
              current.first['Version']
                      ?.toString() ??
                  '',
            ) ??
            1;

    final now =
        DateTime.now()
            .toUtc()
            .toIso8601String();

    return db.update(
      'LEARNERS_Table',
      {
        'Deleted': 0,
        'UpdatedAt': now,
        'Version': currentVersion + 1,
      },
      where: 'LearnerID = ?',
      whereArgs: [
        learnerId,
      ],
    );
  }


  // ============================================================
  // PERMANENT DELETE REQUEST
  // ============================================================
  //
  // Deleted = 2 means:
  // The record is marked for permanent deletion.
  // It is NOT physically removed locally yet.
  //
  // Synchronization will later use this state to remove
  // the corresponding remote record from Google Sheets.
  //
  Future<int> permanentlyDeleteLearner({
    required int learnerId,
  }) async {
    final db =
        _database.database;

    final current =
        await db.query(
      'LEARNERS_Table',
      columns: [
        'Deleted',
        'Version',
      ],
      where: 'LearnerID = ?',
      whereArgs: [
        learnerId,
      ],
      limit: 1,
    );

    if (current.isEmpty) {
      throw StateError(
        'Learner record not found.',
      );
    }

    final currentDeleted =
        int.tryParse(
              current.first['Deleted']
                      ?.toString() ??
                  '',
            ) ??
            0;

    final currentVersion =
        int.tryParse(
              current.first['Version']
                      ?.toString() ??
                  '',
            ) ??
            1;

    // Only archived records may be permanently deleted
    // through the Archived Learners screen.
    if (currentDeleted != 1) {
      throw StateError(
        'Only archived learners can be permanently deleted.',
      );
    }

    final now =
        DateTime.now()
            .toUtc()
            .toIso8601String();

    return db.update(
      'LEARNERS_Table',
      {
        'Deleted': 2,
        'UpdatedAt': now,
        'Version': currentVersion + 1,
      },
      where: 'LearnerID = ?',
      whereArgs: [
        learnerId,
      ],
    );
  }


  Future<int> deleteLearner(
    int learnerId,
  ) async {
    final existing =
        await getLearner(learnerId);

    if (existing == null) {
      return 0;
    }

    final version =
        (existing['Version'] as int?) ?? 1;

    return _database.database.update(
      'LEARNERS_Table',
      {
        'UpdatedAt': _now(),
        'DeviceID': _deviceId(),
        'Version': version + 1,
        'Deleted': 1,
      },
      where: 'LearnerID = ?',
      whereArgs: [learnerId],
    );
  }

  Future<int> bulkAddLearners(
    List<Map<String, Object?>> rows,
  ) async {
    if (rows.isEmpty) {
      return 0;
    }

    final now = _now();
    final deviceId = _deviceId();

    return _database.database.transaction<int>(
      (txn) async {
        var count = 0;

        for (final row in rows) {
          final lastName =
              row['LastName']
                      ?.toString()
                      .trim() ??
                  '';

          final firstName =
              row['FirstName']
                      ?.toString()
                      .trim() ??
                  '';

          final sex =
              row['Sex']
                      ?.toString()
                      .trim() ??
                  '';

          if (lastName.isEmpty ||
              firstName.isEmpty ||
              sex.isEmpty) {
            continue;
          }

          int? age;

          final ageText =
              row['Age']
                      ?.toString()
                      .trim() ??
                  '';

          if (ageText.isNotEmpty) {
            age = int.tryParse(ageText);
          }

          await txn.insert(
            'LEARNERS_Table',
            {
              'LearnerReferenceNumber':
                  _nullIfEmpty(
                row['LRN']?.toString(),
              ),
              'LastName': lastName,
              'FirstName': firstName,
              'MiddleName':
                  _nullIfEmpty(
                row['MiddleName']?.toString(),
              ),
              'Sex': sex,
              'BirthDate':
                  _nullIfEmpty(
                row['BirthDate']?.toString(),
              ),
              'Age': age,
              'PersonalContactNumber':
                  _nullIfEmpty(
                row['PersonalContactNumber']
                    ?.toString(),
              ),
              'RegionCode': null,
              'Region':
                  _nullIfEmpty(
                row['Region']?.toString(),
              ),
              'ProvinceCode': null,
              'Province':
                  _nullIfEmpty(
                row['Province']?.toString(),
              ),
              'CityMunicipalityCode': null,
              'TownMunicipality':
                  _nullIfEmpty(
                row['TownMunicipality']
                    ?.toString(),
              ),
              'BarangayCode': null,
              'Barangay':
                  _nullIfEmpty(
                row['Barangay']?.toString(),
              ),
              'Purok':
                  _nullIfEmpty(
                row['Purok']?.toString(),
              ),
              'Street':
                  _nullIfEmpty(
                row['Street']?.toString(),
              ),
              'HouseNo':
                  _nullIfEmpty(
                row['HouseNo']?.toString(),
              ),
              'Parents':
                  _nullIfEmpty(
                row['Parents']?.toString(),
              ),
              'Guardian':
                  _nullIfEmpty(
                row['Guardian']?.toString(),
              ),
              'RelationshipToGuardian':
                  _nullIfEmpty(
                row['RelationshipToGuardian']
                    ?.toString(),
              ),
              'ParentsContactNumber':
                  _nullIfEmpty(
                row['ParentsContactNumber']
                    ?.toString(),
              ),
              'NotesDetails':
                  _nullIfEmpty(
                row['NotesDetails']
                    ?.toString(),
              ),
              'CreatedAt': now,
              'UpdatedAt': now,
              'DeviceID': deviceId,
              'Version': 1,
              'Deleted': 0,
            },
          );

          count++;
        }

        return count;
      },
    );
  }



  // ============================================================
  // TEACHERS
  // ============================================================

  Future<int> addTeacher({
    required String teacherName,
    String? mobileNumber,
    String status = 'Active',
  }) async {
    final now = _now();

    return _database.database.insert(
      'TEACHERS_Table',
      {
        'TeacherName':
            teacherName.trim(),
        'MobileNumber':
            _nullIfEmpty(mobileNumber),
        'Status': status,
        'CreatedAt': now,
        'UpdatedAt': now,
        'DeviceID': _deviceId(),
        'Version': 1,
        'Deleted': 0,
      },
    );
  }

  Future<List<Map<String, Object?>>>
      getTeachers() {
    return _database.database.query(
      'TEACHERS_Table',
      where: 'Deleted = 0',
      orderBy:
          'TeacherName COLLATE NOCASE',
    );
  }

  Future<int> updateTeacher(
    int teacherId, {
    String? teacherName,
    String? mobileNumber,
    String? status,
  }) async {
    final rows =
        await _database.database.query(
      'TEACHERS_Table',
      columns: ['Version'],
      where:
          'TeacherID = ? AND Deleted = 0',
      whereArgs: [teacherId],
      limit: 1,
    );

    if (rows.isEmpty) {
      throw StateError(
        'Teacher $teacherId was not found.',
      );
    }

    final version =
        (rows.first['Version'] as int?) ?? 1;

    return _database.database.update(
      'TEACHERS_Table',
      {
        if (teacherName != null)
          'TeacherName':
              teacherName.trim(),
        if (mobileNumber != null)
          'MobileNumber':
              _nullIfEmpty(mobileNumber),
        if (status != null)
          'Status': status,
        'UpdatedAt': _now(),
        'DeviceID': _deviceId(),
        'Version': version + 1,
      },
      where: 'TeacherID = ?',
      whereArgs: [teacherId],
    );
  }

  Future<int> deleteTeacher(
    int teacherId,
  ) async {
    final rows =
        await _database.database.query(
      'TEACHERS_Table',
      columns: ['Version'],
      where:
          'TeacherID = ? AND Deleted = 0',
      whereArgs: [teacherId],
      limit: 1,
    );

    if (rows.isEmpty) {
      return 0;
    }

    final version =
        (rows.first['Version'] as int?) ?? 1;

    return _database.database.update(
      'TEACHERS_Table',
      {
        'UpdatedAt': _now(),
        'DeviceID': _deviceId(),
        'Version': version + 1,
        'Deleted': 1,
      },
      where: 'TeacherID = ?',
      whereArgs: [teacherId],
    );
  }

  Future<int> bulkAddTeachers(
    List<Map<String, Object?>> rows,
  ) async {
    if (rows.isEmpty) {
      return 0;
    }

    final now = _now();
    final deviceId = _deviceId();

    return _database.database.transaction<int>(
      (txn) async {
        var count = 0;

        for (final row in rows) {
          final teacherName =
              row['TeacherName']
                      ?.toString()
                      .trim() ??
                  '';

          if (teacherName.isEmpty) {
            continue;
          }

          await txn.insert(
            'TEACHERS_Table',
            {
              'TeacherName': teacherName,
              'MobileNumber':
                  _nullIfEmpty(
                row['MobileNumber']?.toString(),
              ),
              'Status':
                  _nullIfEmpty(
                        row['Status']?.toString(),
                      ) ??
                      'Active',
              'CreatedAt': now,
              'UpdatedAt': now,
              'DeviceID': deviceId,
              'Version': 1,
              'Deleted': 0,
            },
          );

          count++;
        }

        return count;
      },
    );
  }



  // ============================================================
  // SECTIONS
  // ============================================================

  Future<int> addSection({
    required String schoolYear,
    required String gradeLevel,
    required String sectionName,
    required String adviser,
  }) async {
    final now = _now();

    return _database.database.insert(
      'SECTIONS_Table',
      {
        'SchoolYear':
            schoolYear.trim(),
        'GradeLevel': gradeLevel,
        'SectionName':
            sectionName.trim(),
        'Adviser': adviser.trim(),
        'CreatedAt': now,
        'UpdatedAt': now,
        'DeviceID': _deviceId(),
        'Version': 1,
        'Deleted': 0,
      },
    );
  }

  Future<List<Map<String, Object?>>> getSections({
    String? schoolYear,
    String? gradeLevel,
  })
  
  {
    final conditions = <String>[
      'Deleted = 0',
    ];

    final args = <Object?>[];

    if (_hasText(schoolYear)) {
      conditions.add(
        'SchoolYear = ?',
      );
      args.add(
        schoolYear!.trim(),
      );
    }

    if (gradeLevel != null) {
      conditions.add(
        'GradeLevel = ?',
      );
      args.add(gradeLevel);
    }

    return _database.database.query(
      'SECTIONS_Table',
      where: conditions.join(' AND '),
      whereArgs: args,
      orderBy:
          'SchoolYear DESC, '
          'GradeLevel, '
          'SectionName COLLATE NOCASE',
    );
  }

  Future<List<Map<String, Object?>>> getSectionsForSearch({
    String? schoolYear,
    String? gradeLevel,
  }) {
    return getSections(
      schoolYear: schoolYear,
      gradeLevel: gradeLevel,
    );
  }

  Future<int> updateSection(
    int sectionId, {
    String? schoolYear,
    String? gradeLevel,
    String? sectionName,
    String? adviser,
  }) async {
    final rows =
        await _database.database.query(
      'SECTIONS_Table',
      columns: ['Version'],
      where:
          'SectionID = ? AND Deleted = 0',
      whereArgs: [sectionId],
      limit: 1,
    );

    if (rows.isEmpty) {
      throw StateError(
        'Section $sectionId was not found.',
      );
    }

    final version =
        (rows.first['Version'] as int?) ?? 1;

    return _database.database.update(
      'SECTIONS_Table',
      {
        if (schoolYear != null)
          'SchoolYear':
              schoolYear.trim(),
        if (gradeLevel != null)
          'GradeLevel': gradeLevel,
        if (sectionName != null)
          'SectionName':
              sectionName.trim(),
        if (adviser != null)
          'Adviser': adviser.trim(),
        'UpdatedAt': _now(),
        'DeviceID': _deviceId(),
        'Version': version + 1,
      },
      where: 'SectionID = ?',
      whereArgs: [sectionId],
    );
  }

  Future<int> deleteSection(
    int sectionId,
  ) async {
    final rows =
        await _database.database.query(
      'SECTIONS_Table',
      columns: ['Version'],
      where:
          'SectionID = ? AND Deleted = 0',
      whereArgs: [sectionId],
      limit: 1,
    );

    if (rows.isEmpty) {
      return 0;
    }

    final version =
        (rows.first['Version'] as int?) ?? 1;

    return _database.database.update(
      'SECTIONS_Table',
      {
        'UpdatedAt': _now(),
        'DeviceID': _deviceId(),
        'Version': version + 1,
        'Deleted': 1,
      },
      where: 'SectionID = ?',
      whereArgs: [sectionId],
    );
  }

  Future<int> bulkAddSections(
    List<Map<String, Object?>> rows,
  ) async {
    if (rows.isEmpty) {
      return 0;
    }

    final now = _now();
    final deviceId = _deviceId();

    return _database.database.transaction<int>(
      (txn) async {
        var count = 0;

        for (final row in rows) {
          final schoolYear =
              row['SchoolYear']
                      ?.toString()
                      .trim() ??
                  '';

          final gradeLevel =
              row['GradeLevel']
                      ?.toString()
                      .trim() ??
                  '';

          final sectionName =
              row['SectionName']
                      ?.toString()
                      .trim() ??
                  '';

          final adviser =
              row['Adviser']
                      ?.toString()
                      .trim() ??
                  '';

          if (schoolYear.isEmpty ||
              gradeLevel.isEmpty ||
              sectionName.isEmpty) {
            continue;
          }

          await txn.insert(
            'SECTIONS_Table',
            {
              'SchoolYear': schoolYear,
              'GradeLevel': gradeLevel,
              'SectionName': sectionName,
              'Adviser': adviser,
              'CreatedAt': now,
              'UpdatedAt': now,
              'DeviceID': deviceId,
              'Version': 1,
              'Deleted': 0,
            },
          );

          count++;
        }

        return count;
      },
    );
  }




  // ============================================================
  // SCHOOL HISTORY
  // ============================================================

  Future<int> addSchoolHistory({
    required int learnerId,
    required String schoolYear,
    required String grade,
    required String school,
    String? section,
    String? adviser,
    String? notes,
  }) async {
    final now = _now();

    return _database.database.insert(
      'SCHOOL_HISTORY_Table',
      {
        'LearnerID': learnerId,
        'SchoolYear':
            schoolYear.trim(),
        'Grade': grade,
        'School': school.trim(),
        'Section': section?.trim() ?? '',
        'Adviser': adviser?.trim() ?? '',
        'NotesDetails':
            _nullIfEmpty(notes),
        'CreatedAt': now,
        'UpdatedAt': now,
        'DeviceID': _deviceId(),
        'Version': 1,
        'Deleted': 0,
      },
    );
  }

  Future<List<Map<String, Object?>>>
      getSchoolHistory(
    int learnerId,
  ) {
    return _database.database.query(
      'SCHOOL_HISTORY_Table',
      where:
          'LearnerID = ? AND Deleted = 0',
      whereArgs: [learnerId],
      orderBy:
          'SchoolYear DESC, Grade DESC',
    );
  }

  Future<int> updateSchoolHistory({
    required int schoolHistoryId,
    required String schoolYear,
    required String grade,
    required String school,
    String? section,
    String? adviser,
    String? notes,
  }) async {
    return _database.database.rawUpdate(
      '''
      UPDATE SCHOOL_HISTORY_Table
      SET SchoolYear = ?,
          Grade = ?,
          School = ?,
          Section = ?,
          Adviser = ?,
          NotesDetails = ?,
          UpdatedAt = ?,
          DeviceID = ?,
          Version = Version + 1
      WHERE SchoolHistoryID = ?
      ''',
      [
        schoolYear.trim(),
        grade.trim(),
        school.trim(),
        section?.trim() ?? '',
        adviser?.trim() ?? '',
        _nullIfEmpty(notes),
        _now(),
        _deviceId(),
        schoolHistoryId,
      ],
    );
  }

  Future<int> deleteSchoolHistory(
    int schoolHistoryId,
  ) async {
    final rows =
        await _database.database.query(
      'SCHOOL_HISTORY_Table',
      columns: [
        'Version',
      ],
      where:
          'SchoolHistoryID = ? AND Deleted = 0',
      whereArgs: [
        schoolHistoryId,
      ],
      limit: 1,
    );

    if (rows.isEmpty) {
      return 0;
    }

    final currentVersion =
        _asInt(
          rows.first['Version'],
        ) ??
        1;

    return _database.database.update(
      'SCHOOL_HISTORY_Table',
      {
        'UpdatedAt':
            _now(),

        'DeviceID':
            _deviceId(),

        'Version':
            currentVersion + 1,

        'Deleted':
            1,
      },
      where:
          'SchoolHistoryID = ?',
      whereArgs: [
        schoolHistoryId,
      ],
    );
  }


  // ============================================================
  // INCIDENTS
  // ============================================================

  Future<int> addIncident({
    required int learnerId,
    required String incidentDate,
    String? incidentTime,
    String? observer,
    required String behaviorProblem,
    String? observationDetails,
    String? intervention,
    String? actionTaken,
    String? remarks,
    String? details,
  }) async {
    final now = _now();

    return _database.database.insert(
      'INCIDENTS_Table',
      {
        'LearnerID': learnerId,
        'IncidentDate':
            incidentDate,
        'IncidentTime':
            _nullIfEmpty(incidentTime),
        'Observer':
            _nullIfEmpty(observer),
        'BehaviorProblem':
            behaviorProblem,
        'ObservationDetails':
            _nullIfEmpty(
          observationDetails,
        ),
        'Intervention':
            _nullIfEmpty(intervention),
        'ActionTaken':
            _nullIfEmpty(actionTaken),
        'Remarks':
            _nullIfEmpty(remarks),
        'Details':
            _nullIfEmpty(details),
        'CreatedAt': now,
        'UpdatedAt': now,
        'DeviceID': _deviceId(),
        'Version': 1,
        'Deleted': 0,
      },
    );
  }


  Future<int> updateIncident(
  int incidentId, {
  String? incidentDate,
  String? incidentTime,
  String? observer,
  String? behaviorProblem,
  String? observationDetails,
  String? intervention,
  String? actionTaken,
  String? remarks,
  String? details,
}) async {
  final rows =
      await _database.database.query(
    'INCIDENTS_Table',
    columns: ['Version'],
    where:
        'IncidentID = ? AND Deleted = 0',
    whereArgs: [incidentId],
    limit: 1,
  );

  if (rows.isEmpty) {
    throw StateError(
      'Incident $incidentId was not found.',
    );
  }

  final currentVersion =
      _asInt(rows.first['Version']) ?? 1;

  return _database.database.update(
    'INCIDENTS_Table',
    {
      if (incidentDate != null)
        'IncidentDate':
            incidentDate.trim(),

      if (incidentTime != null)
        'IncidentTime':
            _nullIfEmpty(incidentTime),

      if (observer != null)
        'Observer':
            _nullIfEmpty(observer),

      if (behaviorProblem != null)
        'BehaviorProblem':
            behaviorProblem.trim(),

      if (observationDetails != null)
        'ObservationDetails':
            _nullIfEmpty(
          observationDetails,
        ),

      if (intervention != null)
        'Intervention':
            _nullIfEmpty(intervention),

      if (actionTaken != null)
        'ActionTaken':
            _nullIfEmpty(actionTaken),

      if (remarks != null)
        'Remarks':
            _nullIfEmpty(remarks),

      if (details != null)
        'Details':
            _nullIfEmpty(details),

      'UpdatedAt': _now(),
      'DeviceID': _deviceId(),
      'Version': currentVersion + 1,
    },
    where: 'IncidentID = ?',
    whereArgs: [incidentId],
  );
}

Future<int> deleteIncident(
  int incidentId,
) async {
  final rows =
      await _database.database.query(
    'INCIDENTS_Table',
    columns: ['Version'],
    where:
        'IncidentID = ? AND Deleted = 0',
    whereArgs: [incidentId],
    limit: 1,
  );

  if (rows.isEmpty) {
    return 0;
  }

  final currentVersion =
      _asInt(rows.first['Version']) ?? 1;

  return _database.database.update(
    'INCIDENTS_Table',
    {
      'UpdatedAt': _now(),
      'DeviceID': _deviceId(),
      'Version': currentVersion + 1,
      'Deleted': 1,
    },
    where: 'IncidentID = ?',
    whereArgs: [incidentId],
  );
}




  Future<List<Map<String, Object?>>> getIncidents(
    int learnerId,
  ) async {
    final incidents =
        await _database.database.query(
      'INCIDENTS_Table',
      where:
          'LearnerID = ? AND Deleted = 0',
      whereArgs: [learnerId],
    );

    final history =
        await getSchoolHistory(
      learnerId,
    );

    final results =
        <Map<String, Object?>>[];

    for (final incident in incidents) {
      final incidentDate =
          _parseStoredDate(
        incident['IncidentDate']?.toString(),
      );

      final historyMatch =
          _findSchoolHistoryForIncident(
        history,
        incidentDate,
      );

      final result =
          Map<String, Object?>.from(
        incident,
      );

      result['IncidentGrade'] =
          historyMatch?['Grade'];

      result['IncidentSection'] =
          historyMatch?['Section'];

      result['IncidentSchoolYear'] =
          historyMatch?['SchoolYear'];

      result['IncidentAdviser'] =
          historyMatch?['Adviser'];

      results.add(result);
    }

    results.sort(
      (a, b) {
        final aDate =
            _parseStoredDate(
          a['IncidentDate']?.toString(),
        );

        final bDate =
            _parseStoredDate(
          b['IncidentDate']?.toString(),
        );

        if (aDate == null &&
            bDate == null) {
          return 0;
        }

        if (aDate == null) {
          return 1;
        }

        if (bDate == null) {
          return -1;
        }

        final dateCompare =
            bDate.compareTo(aDate);

        if (dateCompare != 0) {
          return dateCompare;
        }

        final aTime =
            a['IncidentTime']?.toString() ?? '';

        final bTime =
            b['IncidentTime']?.toString() ?? '';

        return bTime.compareTo(aTime);
      },
    );

    return results;
  }

  // ============================================================
  // SCHOOL YEARS
  // ============================================================

  Future<List<Map<String, Object?>>>
      getSchoolYearsForSearch() async {
    final rows =
        await _database.database.rawQuery(
      '''
      SELECT SchoolYear
      FROM SCHOOL_HISTORY_Table
      WHERE Deleted = 0
        AND SchoolYear IS NOT NULL
        AND TRIM(SchoolYear) <> ''

      UNION

      SELECT SchoolYear
      FROM SECTIONS_Table
      WHERE Deleted = 0
        AND SchoolYear IS NOT NULL
        AND TRIM(SchoolYear) <> ''

      ORDER BY SchoolYear DESC
      ''',
    );

    return rows;
  }

  // ============================================================
  // COMPLETE SEARCH
  // ============================================================

  Future<List<Map<String, Object?>>>
      searchIncidentRecords({
    String? lastName,
    String? firstName,
    String? middleName,
    String? lrn,

    String? currentGradeLevel,
    String? incidentGradeLevel,
    String? section,

    int? age,

    String? regionCode,
    String? provinceCode,
    String? municipalityCode,
    String? barangayCode,

    String? schoolYearLastEnrolled,

    DateTime? incidentDateFrom,
    DateTime? incidentDateTo,

    String? observer,

    List<String> behaviors = const [],
    List<String> interventions = const [],
    List<String> remarks = const [],
  }) async {
    final db =
        _database.database;

    final learners =
        await db.query(
      'LEARNERS_Table',
      where: 'Deleted = 0',
      orderBy:
          'LastName COLLATE NOCASE, '
          'FirstName COLLATE NOCASE, '
          'MiddleName COLLATE NOCASE',
    );

    final historyRows =
        await db.query(
      'SCHOOL_HISTORY_Table',
      where: 'Deleted = 0',
      orderBy:
          'SchoolYear DESC, Grade DESC',
    );

    final historyByLearner =
        <int, List<Map<String, Object?>>>{};

    for (final row in historyRows) {
      final learnerId =
          row['LearnerID'] as int;

      historyByLearner
          .putIfAbsent(
            learnerId,
            () => [],
          )
          .add(row);
    }

    final incidentRows =
        await db.query(
      'INCIDENTS_Table',
      where: 'Deleted = 0',
      orderBy:
          'IncidentDate DESC, '
          'IncidentTime DESC',
    );

    final incidentsByLearner =
        <int, List<Map<String, Object?>>>{};

    for (final row in incidentRows) {
      final learnerId =
          row['LearnerID'] as int;

      incidentsByLearner
          .putIfAbsent(
            learnerId,
            () => [],
          )
          .add(row);
    }

    final incidentSearchActive =
        _isIncidentSearchActive(
      incidentGradeLevel:
          incidentGradeLevel,  
      section: section,
      incidentDateFrom:
          incidentDateFrom,
      incidentDateTo:
          incidentDateTo,
      observer: observer,
      behaviors: behaviors,
      interventions: interventions,
      remarks: remarks,
    );

    final results =
        <Map<String, Object?>>[];

    for (final learner in learners) {
      final learnerId =
          learner['LearnerID'] as int;

      // --------------------------------------------------------
      // BASIC LEARNER FILTERS
      // --------------------------------------------------------

      if (!_matchesText(
        learner['LastName'],
        lastName,
      )) {
        continue;
      }

      if (!_matchesText(
        learner['FirstName'],
        firstName,
      )) {
        continue;
      }

      if (!_matchesText(
        learner['MiddleName'],
        middleName,
      )) {
        continue;
      }

      if (!_matchesText(
        learner['LearnerReferenceNumber'],
        lrn,
      )) {
        continue;
      }

      if (age != null &&
          learner['Age'] != age) {
        continue;
      }

      // --------------------------------------------------------
      // LOCATION
      // --------------------------------------------------------

      if (!_matchesCode(
        learner['RegionCode'],
        regionCode,
      )) {
        continue;
      }

      if (!_matchesCode(
        learner['ProvinceCode'],
        provinceCode,
      )) {
        continue;
      }

      if (!_matchesCode(
        learner['CityMunicipalityCode'],
        municipalityCode,
      )) {
        continue;
      }

      if (!_matchesCode(
        learner['BarangayCode'],
        barangayCode,
      )) {
        continue;
      }

      // --------------------------------------------------------
      // SCHOOL HISTORY
      // --------------------------------------------------------

      final history =
          historyByLearner[learnerId] ??
              [];

      final currentHistory =
          _findCurrentSchoolHistory(
        history,
      );

      final currentGrade =
          _asGrade(
            currentHistory?['Grade'],
          );

      final currentSection =
          currentHistory?['Section']
              ?.toString();

      final currentSchoolYear =
          currentHistory?['SchoolYear']
              ?.toString();

      // Current Grade
      if (_hasText(currentGradeLevel) &&
        currentGrade != currentGradeLevel) {
      continue;
      }





      // Last Enrolled School Year
      if (_hasText(
        schoolYearLastEnrolled,
      )) {
        final matchingHistory =
            history.any(
          (item) =>
              item['SchoolYear']
                  ?.toString() ==
              schoolYearLastEnrolled!.trim(),
        );

        if (!matchingHistory) {
          continue;
        }
      }

      final incidents =
          incidentsByLearner[learnerId] ??
              [];

      // ========================================================
      // LEARNER-LEVEL RESULT
      // No incident-specific criteria.
      // ========================================================

      if (!incidentSearchActive) {
        final result =
            Map<String, Object?>.from(
          learner,
        );

        result['CurrentGrade'] =
            currentGrade;

        result['CurrentSection'] =
            currentSection;

        result['CurrentSchoolYear'] =
            currentSchoolYear;

        result['IncidentID'] = null;
        result['IncidentDate'] = null;
        result['IncidentTime'] = null;
        result['Observer'] = null;
        result['BehaviorProblem'] =
            null;
        result['ObservationDetails'] =
            null;
        result['Intervention'] = null;
        result['ActionTaken'] = null;
        result['Remarks'] = null;
        result['Details'] = null;

        result['IncidentGrade'] = null;
        result['IncidentSection'] = null;
        result['IncidentSchoolYear'] =
            null;

        results.add(result);

        continue;
      }

      // ========================================================
      // INCIDENT-LEVEL RESULTS
      // ========================================================

      for (final incident in incidents) {
        final incidentDate =
            _parseStoredDate(
          incident['IncidentDate']
              ?.toString(),
        );

        if (incidentDateFrom != null) {
          if (incidentDate == null ||
              incidentDate.isBefore(
                _dateOnly(
                  incidentDateFrom,
                ),
              )) {
            continue;
          }
        }

        if (incidentDateTo != null) {
          if (incidentDate == null ||
              incidentDate.isAfter(
                _dateEnd(
                  incidentDateTo,
                ),
              )) {
            continue;
          }
        }

        if (!_matchesText(
          incident['Observer'],
          observer,
        )) {
          continue;
        }

        if (!_matchesChecklist(
          incident['BehaviorProblem'],
          behaviors,
        )) {
          continue;
        }

        if (!_matchesChecklist(
          incident['Intervention'],
          interventions,
        )) {
          continue;
        }

        if (!_matchesChecklist(
          incident['Remarks'],
          remarks,
        )) {
          continue;
        }

        final incidentHistory =
            _findSchoolHistoryForIncident(
          history,
          incidentDate,
        );

        final incidentGrade =
            _asGrade(
              incidentHistory?['Grade'],
            );

        final incidentSection =
            incidentHistory?['Section']
                ?.toString();

        final incidentSchoolYear =
            incidentHistory?['SchoolYear']
                ?.toString();

        // Grade during incident
        if (_hasText(incidentGradeLevel) &&
          incidentGrade != incidentGradeLevel) {
        continue;
      }

        // Section during incident
        if (_hasText(section)) {
          if (!_matchesText(
            incidentSection,
            section,
          )) {
            continue;
          }
        }

        final result =
            Map<String, Object?>.from(
          learner,
        );

        result['CurrentGrade'] =
            currentGrade;

        result['CurrentSection'] =
            currentSection;

        result['CurrentSchoolYear'] =
            currentSchoolYear;

        result['IncidentID'] =
            incident['IncidentID'];

        result['IncidentDate'] =
            incident['IncidentDate'];

        result['IncidentTime'] =
            incident['IncidentTime'];

        result['Observer'] =
            incident['Observer'];

        result['BehaviorProblem'] =
            incident[
                'BehaviorProblem'];

        result['ObservationDetails'] =
            incident[
                'ObservationDetails'];

        result['Intervention'] =
            incident['Intervention'];

        result['ActionTaken'] =
            incident['ActionTaken'];

        result['Remarks'] =
            incident['Remarks'];

        result['Details'] =
            incident['Details'];

        result['IncidentGrade'] =
            incidentGrade;

        result['IncidentSection'] =
            incidentSection;

        result['IncidentSchoolYear'] =
            incidentSchoolYear;

        results.add(result);
      }
    }

    results.sort(
      (a, b) {
        final aIncident =
            _parseStoredDate(
          a['IncidentDate']?.toString(),
        );

        final bIncident =
            _parseStoredDate(
          b['IncidentDate']?.toString(),
        );

        if (aIncident == null &&
            bIncident == null) {
          return _compareLearnerNames(
            a,
            b,
          );
        }

        if (aIncident == null) {
          return 1;
        }

        if (bIncident == null) {
          return -1;
        }

        // Most recent incident first.
        final dateCompare =
            bIncident.compareTo(
          aIncident,
        );

        if (dateCompare != 0) {
          return dateCompare;
        }

        // If dates are identical, compare time.
        final aTime =
            a['IncidentTime']?.toString() ?? '';

        final bTime =
            b['IncidentTime']?.toString() ?? '';

        final timeCompare =
            bTime.compareTo(aTime);

        if (timeCompare != 0) {
          return timeCompare;
        }

        return _compareLearnerNames(
          a,
          b,
        );
      },
    );


    return results;
  }

  // ============================================================
  // SEARCH HELPERS
  // ============================================================

  bool _isIncidentSearchActive({
    required String? incidentGradeLevel,
    required String? section,
    required DateTime? incidentDateFrom,
    required DateTime? incidentDateTo,
    required String? observer,
    required List<String> behaviors,
    required List<String> interventions,
    required List<String> remarks,
  }) {
    return incidentGradeLevel != null ||
        _hasText(section) ||
        incidentDateFrom != null ||
        incidentDateTo != null ||
        _hasText(observer) ||
        behaviors.isNotEmpty ||
        interventions.isNotEmpty ||
        remarks.isNotEmpty;
  }

  bool _matchesText(
    Object? actual,
    String? search,
  ) {
    if (!_hasText(search)) {
      return true;
    }

    final actualText =
        actual?.toString().toLowerCase() ??
            '';

    return actualText.contains(
      search!.trim().toLowerCase(),
    );
  }

  bool _matchesCode(
    Object? actual,
    String? search,
  ) {
    if (!_hasText(search)) {
      return true;
    }

    return actual?.toString() ==
        search;
  }

  bool _matchesChecklist(
    Object? actual,
    List<String> selected,
  ) {
    if (selected.isEmpty) {
      return true;
    }

    final actualText =
        actual?.toString().toLowerCase() ??
            '';

    // Multiple selections within the
    // same checklist category = OR.
    return selected.any(
      (item) => actualText.contains(
        item.toLowerCase(),
      ),
    );
  }

  // ============================================================
  // CURRENT SCHOOL HISTORY
  // ============================================================

  Map<String, Object?>? _findCurrentSchoolHistory(
    List<Map<String, Object?>> history,
  ) {
    if (history.isEmpty) {
      return null;
    }

    Map<String, Object?>? best;
    var bestYear = -1;

    for (final item in history) {
      final schoolYear =
          item['SchoolYear']?.toString() ?? '';

      final startYear =
          _schoolYearStartYear(
        schoolYear,
      );

      if (best == null ||
          startYear > bestYear) {
        best = item;
        bestYear = startYear;
      }
    }

    return best;
  }

  int _schoolYearStartYear(
    String schoolYear,
  ) {
    final match = RegExp(
      r'^(\d{4})\s*-\s*(\d{4})$',
    ).firstMatch(
      schoolYear.trim(),
    );

    if (match == null) {
      return 0;
    }

    return int.parse(
      match.group(1)!,
    );
  }

  // ============================================================
  // SCHOOL HISTORY FOR AN INCIDENT
  // ============================================================

  Map<String, Object?>?
      _findSchoolHistoryForIncident(
    List<Map<String, Object?>> history,
    DateTime? incidentDate,
  ) {
    if (history.isEmpty) {
      return null;
    }

    if (incidentDate == null) {
      return _findCurrentSchoolHistory(
        history,
      );
    }

    Map<String, Object?>? bestMatch;

    for (final item in history) {
      final schoolYear =
          item['SchoolYear']?.toString();

      if (schoolYear == null ||
          schoolYear.trim().isEmpty) {
        continue;
      }

      final range =
          _schoolYearDateRange(
        schoolYear,
      );

      if (range == null) {
        continue;
      }

      // Exact school-year match.
      if (!incidentDate.isBefore(
            range.start,
          ) &&
          !incidentDate.isAfter(
            range.end,
          )) {
        return item;
      }

      // Fallback:
      // latest school year that had already started.
      if (!range.start.isAfter(
        incidentDate,
      )) {
        if (bestMatch == null) {
          bestMatch = item;
        } else {
          final bestRange =
              _schoolYearDateRange(
            bestMatch['SchoolYear']
                    ?.toString() ??
                '',
          );

          if (bestRange != null &&
              range.start.isAfter(
                bestRange.start,
              )) {
            bestMatch = item;
          }
        }
      }
    }

    return bestMatch;
  }

  ({DateTime start, DateTime end})?
    _schoolYearDateRange(
  String schoolYear,
) {
  final match = RegExp(
    r'^(\d{4})\s*-\s*(\d{4})$',
  ).firstMatch(
    schoolYear.trim(),
  );

  if (match == null) {
    return null;
  }

  final startYear =
      int.parse(match.group(1)!);

  final endYear =
      int.parse(match.group(2)!);

  return (
    start: DateTime(
      startYear,
      6,
      1,
    ),
    end: DateTime(
      endYear,
      5,
      31,
      23,
      59,
      59,
    ),
  );
}

  // ============================================================
  // DATE HELPERS
  // ============================================================

  DateTime? _parseStoredDate(
    String? value,
  ) {
    if (!_hasText(value)) {
      return null;
    }

    final text = value!.trim();

    final iso =
        DateTime.tryParse(text);

    if (iso != null) {
      return DateTime(
        iso.year,
        iso.month,
        iso.day,
      );
    }

    const monthNames = {
      'january': 1,
      'february': 2,
      'march': 3,
      'april': 4,
      'may': 5,
      'june': 6,
      'july': 7,
      'august': 8,
      'september': 9,
      'october': 10,
      'november': 11,
      'december': 12,
    };

    final match = RegExp(
      r'^([A-Za-z]+)\s+(\d{1,2}),?\s+(\d{4})$',
    ).firstMatch(text);

    if (match != null) {
      final month =
          monthNames[
            match.group(1)!
                .toLowerCase()
          ];

      if (month != null) {
        return DateTime(
          int.parse(match.group(3)!),
          month,
          int.parse(match.group(2)!),
        );
      }
    }

    return null;
  }

  DateTime _dateOnly(DateTime date) {
    return DateTime(
      date.year,
      date.month,
      date.day,
    );
  }

  DateTime _dateEnd(DateTime date) {
    return DateTime(
      date.year,
      date.month,
      date.day,
      23,
      59,
      59,
      999,
    );
  }

  int _compareLearnerNames(
    Map<String, Object?> a,
    Map<String, Object?> b,
  ) {
    final aLast =
        a['LastName']
            ?.toString()
            .toLowerCase() ??
        '';

    final bLast =
        b['LastName']
            ?.toString()
            .toLowerCase() ??
        '';

    final lastCompare =
        aLast.compareTo(bLast);

    if (lastCompare != 0) {
      return lastCompare;
    }

    final aFirst =
        a['FirstName']
            ?.toString()
            .toLowerCase() ??
        '';

    final bFirst =
        b['FirstName']
            ?.toString()
            .toLowerCase() ??
        '';

    return aFirst.compareTo(bFirst);
  }

  // ============================================================
  // SYNC STATUS
  // ============================================================

  Future<int> pendingSyncCount() async {
    final tables = [
      'TEACHERS_Table',
      'SECTIONS_Table',
      'LEARNERS_Table',
      'SCHOOL_HISTORY_Table',
      'INCIDENTS_Table',
    ];

    var total = 0;

    for (final table in tables) {
      final result =
          await _database.database.rawQuery(
        'SELECT COUNT(*) AS RecordCount '
        'FROM $table '
        'WHERE Deleted = 0',
      );

      final count =
          result.first['RecordCount'];

      if (count is int) {
        total += count;
      }
    }

    return total;
  }

  // ============================================================
  // DATABASE TEST
  // ============================================================

  Future<String> runDatabaseTest() async {
    try {
      final database =
          _database.database;

      final teacherId =
          await addTeacher(
        teacherName:
            'DATABASE TEST TEACHER',
        mobileNumber: '09000000000',
        status: 'Active',
      );

      final learnerId =
          await addLearner(
        lastName: 'DATABASE',
        firstName: 'TEST',
        middleName: 'LEARNER',
        lrn: 'TEST-LRN-001',
        sex: 'Male',
        age: 15,
        region: 'Region II',
        province: 'Isabela',
        municipality: 'San Manuel',
      );

      final learner =
          await getLearner(
        learnerId,
      );

      if (learner == null) {
        throw StateError(
          'Learner could not be retrieved.',
        );
      }

      await addSchoolHistory(
        learnerId: learnerId,
        schoolYear: '2026-2027',
        grade: '9',
        school:
            'Callang National High School',
        section: 'Test Section',
        adviser:
            'DATABASE TEST TEACHER',
      );

      await addIncident(
        learnerId: learnerId,
        incidentDate:
            'August 22, 2026',
        incidentTime: '10:30 AM',
        observer:
            'DATABASE TEST TEACHER',
        behaviorProblem: 'Testing',
        observationDetails:
            'Database test incident.',
        intervention: 'Testing',
        actionTaken: 'Testing',
        remarks: 'Testing',
        details:
            'Temporary test record.',
      );

      final history =
          await getSchoolHistory(
        learnerId,
      );

      final incidents =
          await getIncidents(
        learnerId,
      );

      if (history.length != 1) {
        throw StateError(
          'School history test failed.',
        );
      }

      if (incidents.length != 1) {
        throw StateError(
          'Incident test failed.',
        );
      }

      final metadata =
          await database.query(
        'LEARNERS_Table',
        columns: [
          'CreatedAt',
          'UpdatedAt',
          'DeviceID',
          'Version',
          'Deleted',
        ],
        where: 'LearnerID = ?',
        whereArgs: [learnerId],
      );

      if (metadata.isEmpty) {
        throw StateError(
          'Metadata test failed.',
        );
      }

      await deleteLearner(
        learnerId,
      );

      await database.update(
        'TEACHERS_Table',
        {
          'UpdatedAt': _now(),
          'DeviceID': _deviceId(),
          'Version': 2,
          'Deleted': 1,
        },
        where: 'TeacherID = ?',
        whereArgs: [teacherId],
      );

      return '''
DATABASE TEST SUCCESSFUL

SQLite opened successfully.

Teacher:
  ID: $teacherId

Learner:
  ID: $learnerId
  Name: ${learner['LastName']}, ${learner['FirstName']}

School History:
  ${history.length} record

Incidents:
  ${incidents.length} record

Sync Metadata:
  CreatedAt: ${metadata.first['CreatedAt']}
  UpdatedAt: ${metadata.first['UpdatedAt']}
  DeviceID: ${metadata.first['DeviceID']}
  Version: ${metadata.first['Version']}
  Deleted: ${metadata.first['Deleted']}

Soft-delete test:
  PASSED
''';
    } catch (e, stackTrace) {
      debugPrint(
        'DATABASE TEST ERROR: $e',
      );

      debugPrintStack(
        stackTrace: stackTrace,
      );

      return '''
DATABASE TEST FAILED

$e
''';
    }
  }
}
