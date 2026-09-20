import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:flutter/foundation.dart';

import 'google_auth_service.dart';
import 'sync_context_service.dart';
import '../models/sync_record_state.dart';

class GoogleSheetsService {
  GoogleSheetsService._();

  @visibleForTesting
  GoogleSheetsService.forTesting();

  static final GoogleSheetsService instance =
      GoogleSheetsService._();

  final GoogleAuthService _auth =
      GoogleAuthService.instance;

  final SyncContextService _context = SyncContextService.instance;

  String? _spreadsheetId;

  // ============================================================
  // SHEET NAMES
  // ============================================================

  static const String learnersSheet =
      'LEARNERS';

  static const String teachersSheet =
      'TEACHERS';

  static const String sectionsSheet =
      'SECTIONS';

  static const String schoolHistorySheet =
      'SCHOOL_HISTORY';

  static const String incidentsSheet =
      'INCIDENTS';

  static const List<String> requiredSheets = [
    learnersSheet,
    teachersSheet,
    sectionsSheet,
    schoolHistorySheet,
    incidentsSheet,
  ];

  // ============================================================
  // HEADERS
  //
  // These must match the actual Google Sheets structure.
  // SyncID is the cross-device identity.
  // ============================================================

  static const List<String> learnerHeaders = [
    'SyncID',
    'LearnerID',
    'LearnerReferenceNumber',
    'LastName',
    'FirstName',
    'MiddleName',
    'Sex',
    'BirthDate',
    'Age',
    'PersonalContactNumber',
    'RegionCode',
    'Region',
    'ProvinceCode',
    'Province',
    'CityMunicipalityCode',
    'TownMunicipality',
    'BarangayCode',
    'Barangay',
    'Purok',
    'Street',
    'HouseNo',
    'Parents',
    'Guardian',
    'RelationshipToGuardian',
    'ParentsContactNumber',
    'NotesDetails',
    'CreatedAt',
    'UpdatedAt',
    'DeviceID',
    'Version',
    'Deleted',
  ];

  static const List<String> teacherHeaders = [
    'SyncID',
    'TeacherID',
    'TeacherName',
    'MobileNumber',
    'Status',
    'CreatedAt',
    'UpdatedAt',
    'DeviceID',
    'Version',
    'Deleted',
  ];

  static const List<String> sectionHeaders = [
    'SyncID',
    'SectionID',
    'SchoolYear',
    'GradeLevel',
    'SectionName',
    'Adviser',
    'CreatedAt',
    'UpdatedAt',
    'DeviceID',
    'Version',
    'Deleted',
  ];

  static const List<String> schoolHistoryHeaders = [
    'SyncID',
    'SchoolHistoryID',
    'LearnerID',
    'LearnerSyncID',
    'SchoolYear',
    'Grade',
    'School',
    'Section',
    'Adviser',
    'NotesDetails',
    'CreatedAt',
    'UpdatedAt',
    'DeviceID',
    'Version',
    'Deleted',
  ];

  static const List<String> incidentHeaders = [
    'SyncID',
    'IncidentID',
    'LearnerID',
    'LearnerSyncID',
    'IncidentDate',
    'IncidentTime',
    'Observer',
    'BehaviorProblem',
    'ObservationDetails',
    'Intervention',
    'ActionTaken',
    'Remarks',
    'Details',
    'CreatedAt',
    'UpdatedAt',
    'DeviceID',
    'Version',
    'Deleted',
  ];

  // ============================================================
  // INITIALIZE
  // ============================================================

  Future<void> initialize() async {
    _spreadsheetId = await _context.activeSpreadsheetId();
  }

  // ============================================================
  // SPREADSHEET ID
  // ============================================================

  String? get spreadsheetId =>
      _spreadsheetId;

  Future<void> setSpreadsheetId(
    String? value,
  ) async {
    await _context.exclusive(() async {
      await _context.activate(value);
      await initialize();
    });
  }

  String _requireSpreadsheetId() {
    final id =
        _spreadsheetId;

    if (id == null ||
        id.trim().isEmpty) {
      throw StateError(
        'Google Spreadsheet ID has not been configured.',
      );
    }

    return id.trim();
  }

  // ============================================================
  // AUTHENTICATED SHEETS API
  // ============================================================

  Future<sheets.SheetsApi> _getApi({bool initializeTarget = true}) async {
    if (initializeTarget) await initialize();

    final client =
        await _auth.authenticatedClient;

    if (client == null) {
      throw StateError(
        'Google account is not authenticated.',
      );
    }

    return sheets.SheetsApi(
      client,
    );
  }

  // ============================================================
  // SPREADSHEET METADATA
  // ============================================================

  Future<sheets.Spreadsheet>
      getSpreadsheet() async {
    final api =
        await _getApi();

    final id =
        _requireSpreadsheetId();

    return api.spreadsheets.get(
      id,
    );
  }

  Future<String?>
      getSpreadsheetTitle() async {
    final spreadsheet =
        await getSpreadsheet();

    return spreadsheet
        .properties
        ?.title;
  }

  Future<String?>
      getSpreadsheetUrl() async {
    final spreadsheet =
        await getSpreadsheet();

    return spreadsheet.spreadsheetUrl;
  }

  Future<List<String>>
      getSheetTitles() async {
    final spreadsheet =
        await getSpreadsheet();

    return (spreadsheet.sheets ??
            const <sheets.Sheet>[])
        .map(
          (sheet) =>
              sheet.properties
                  ?.title ??
              '',
        )
        .where(
          (title) =>
              title.trim().isNotEmpty,
        )
        .toList();
  }

  Future<sheets.Sheet?> findSheet(
    String title,
  ) async {
    final spreadsheet =
        await getSpreadsheet();

    for (final sheet
        in spreadsheet.sheets ??
            const <sheets.Sheet>[]) {
      final sheetTitle =
          sheet.properties
                  ?.title ??
              '';

      if (sheetTitle == title) {
        return sheet;
      }
    }

    return null;
  }

  // ============================================================
  // CHECK SHEET
  // ============================================================

  Future<bool> sheetExists(
    String title,
  ) async {
    final sheet =
        await findSheet(
      title,
    );

    return sheet != null;
  }

  Future<List<String>>
      missingRequiredSheets() async {
    final existing =
        await getSheetTitles();

    return requiredSheets
        .where(
          (required) =>
              !existing.contains(
            required,
          ),
        )
        .toList();
  }

  // ============================================================
  // CREATE SPREADSHEET
  // ============================================================

  Future<sheets.Spreadsheet>
      createAndInitializeSpreadsheet({
    String title =
        'HOLISTIC EDUCATIONAL ANECDOTAL RECORD & TRACKING SYSTEM',
  }) async {
    final api =
        await _getApi();

    final created =
        await api.spreadsheets.create(
      sheets.Spreadsheet(
        properties:
            sheets.SpreadsheetProperties(
          title: title,
        ),
      ),
    );

    final id =
        created.spreadsheetId;

    if (id == null ||
        id.trim().isEmpty) {
      throw StateError(
        'Google did not return a spreadsheet ID.',
      );
    }

    final createdSheets =
        created.sheets ??
            const <sheets.Sheet>[];

    if (createdSheets.isEmpty) {
      throw StateError(
        'The newly created spreadsheet has no worksheet.',
      );
    }

    final defaultSheetId =
        createdSheets.first
            .properties
            ?.sheetId;

    final requests =
        <sheets.Request>[];

    if (defaultSheetId != null) {
      requests.add(
        sheets.Request(
          updateSheetProperties:
              sheets
                  .UpdateSheetPropertiesRequest(
            properties:
                sheets.SheetProperties(
              sheetId:
                  defaultSheetId,
              title:
                  learnersSheet,
            ),
            fields:
                'title',
          ),
        ),
      );
    }

    for (final sheetTitle
        in [
      teachersSheet,
      sectionsSheet,
      schoolHistorySheet,
      incidentsSheet,
    ]) {
      requests.add(
        sheets.Request(
          addSheet:
              sheets.AddSheetRequest(
            properties:
                sheets.SheetProperties(
              title:
                  sheetTitle,
            ),
          ),
        ),
      );
    }

    await api.spreadsheets.batchUpdate(
      sheets.BatchUpdateSpreadsheetRequest(
        requests:
            requests,
      ),
      id,
    );

    // Prepare the candidate explicitly; the active target remains unchanged
    // until all remote setup and validation have succeeded.
    final headersBySheet = <String, List<String>>{
      learnersSheet: learnerHeaders,
      teachersSheet: teacherHeaders,
      sectionsSheet: sectionHeaders,
      schoolHistorySheet: schoolHistoryHeaders,
      incidentsSheet: incidentHeaders,
    };
    for (final entry in headersBySheet.entries) {
      await api.spreadsheets.values.update(
        sheets.ValueRange(values: [entry.value]),
        id,
        '${entry.key}!A1',
        valueInputOption: 'RAW',
      );
    }
    // This validates every worksheet/header before activating the candidate.
    return connectToExistingSpreadsheet(id);
  }

    // ============================================================
    // CONNECT TO EXISTING SPREADSHEET
    //
    // Used when another device needs to connect to the same
    // counselor-owned Google Spreadsheet.
    //
    // Accepts either:
    //   - Spreadsheet ID
    //   - Full Google Sheets URL
    //
    // The spreadsheet is validated before the ID is saved.
    // ============================================================

    Future<sheets.Spreadsheet>
        connectToExistingSpreadsheet(String input) async {
      final spreadsheet = await validateSpreadsheet(input);
      await setSpreadsheetId(spreadsheet.spreadsheetId!);
      return spreadsheet;
    }

    /// Validates a candidate without changing SQLite ownership or preferences.
    Future<sheets.Spreadsheet>
        validateSpreadsheet(
      String input,
    ) async {
      final text = input.trim();

      if (text.isEmpty) {
        throw ArgumentError(
          'Please enter a Google Spreadsheet ID or URL.',
        );
      }

      final spreadsheetId =
          _extractSpreadsheetId(text);

      if (spreadsheetId == null ||
          spreadsheetId.isEmpty) {
        throw ArgumentError(
          'The Google Spreadsheet ID or URL is not valid.',
        );
      }

      final api = await _getApi(initializeTarget: false);

      // ------------------------------------------------------------
      // Read spreadsheet metadata first.
      // Nothing is saved locally yet.
      // ------------------------------------------------------------

      final spreadsheet =
          await api.spreadsheets.get(
        spreadsheetId,
      );

      // ------------------------------------------------------------
      // Verify all five required worksheets exist.
      // ------------------------------------------------------------

      final existingSheets =
          (spreadsheet.sheets ??
                  const <sheets.Sheet>[])
              .map(
                (sheet) =>
                    sheet.properties?.title ??
                    '',
              )
              .where(
                (title) =>
                    title.trim().isNotEmpty,
              )
              .toSet();

      final missingSheets =
          requiredSheets
              .where(
                (sheet) =>
                    !existingSheets.contains(
                  sheet,
                ),
              )
              .toList();

      if (missingSheets.isNotEmpty) {
        throw StateError(
          'This spreadsheet is missing the required worksheet(s): '
          '${missingSheets.join(', ')}',
        );
      }

      // ------------------------------------------------------------
      // Verify the header structure of every worksheet.
      // This prevents accidentally connecting the app to an
      // unrelated Google Spreadsheet.
      // ------------------------------------------------------------

      await _validateRemoteHeaders(
        api: api,
        spreadsheetId: spreadsheetId,
        sheetTitle: learnersSheet,
        expectedHeaders: learnerHeaders,
      );

      await _validateRemoteHeaders(
        api: api,
        spreadsheetId: spreadsheetId,
        sheetTitle: teachersSheet,
        expectedHeaders: teacherHeaders,
      );

      await _validateRemoteHeaders(
        api: api,
        spreadsheetId: spreadsheetId,
        sheetTitle: sectionsSheet,
        expectedHeaders: sectionHeaders,
      );

      await _validateRemoteHeaders(
        api: api,
        spreadsheetId: spreadsheetId,
        sheetTitle: schoolHistorySheet,
        expectedHeaders: schoolHistoryHeaders,
      );

      await _validateRemoteHeaders(
        api: api,
        spreadsheetId: spreadsheetId,
        sheetTitle: incidentsSheet,
        expectedHeaders: incidentHeaders,
      );

      if (spreadsheet.spreadsheetId != spreadsheetId) {
        throw StateError('Google returned an unexpected spreadsheet ID.');
      }
      return spreadsheet;
    }

    // ============================================================
    // EXTRACT SPREADSHEET ID
    // ============================================================

    String? _extractSpreadsheetId(
      String input,
    ) {
      final text = input.trim();

      // Plain Spreadsheet ID.
      if (!text.contains('/') &&
          !text.contains(' ')) {
        return text;
      }

      // Full Google Sheets URL.
      final match = RegExp(
        r'/spreadsheets/d/([a-zA-Z0-9_-]+)',
      ).firstMatch(text);

      return match?.group(1);
    }

    // ============================================================
    // VALIDATE REMOTE HEADERS
    // ============================================================

    Future<void> _validateRemoteHeaders({
      required sheets.SheetsApi api,
      required String spreadsheetId,
      required String sheetTitle,
      required List<String> expectedHeaders,
    }) async {
      final response =
          await api.spreadsheets.values.get(
        spreadsheetId,
        '$sheetTitle!A:ZZ',
      );

      final values =
          response.values ??
              const <List<Object?>>[];

      if (values.isEmpty) {
        throw StateError(
          'The $sheetTitle worksheet is empty. '
          'The required header row was not found.',
        );
      }

      final actualHeaders =
          values.first
              .map(
                (value) =>
                    value
                        ?.toString()
                        .trim() ??
                    '',
              )
              .toList();

      _validateHeaders(
        sheetTitle: sheetTitle,
        expectedHeaders: expectedHeaders,
        actualHeaders: actualHeaders,
      );
    }

  // ============================================================
  // INITIALIZE HEADERS
  // ============================================================

  Future<void>
      initializeSyncHeaders() async {
    await writeHeader(
      sheetTitle:
          learnersSheet,
      headers:
          learnerHeaders,
    );

    await writeHeader(
      sheetTitle:
          teachersSheet,
      headers:
          teacherHeaders,
    );

    await writeHeader(
      sheetTitle:
          sectionsSheet,
      headers:
          sectionHeaders,
    );

    await writeHeader(
      sheetTitle:
          schoolHistorySheet,
      headers:
          schoolHistoryHeaders,
    );

    await writeHeader(
      sheetTitle:
          incidentsSheet,
      headers:
          incidentHeaders,
    );
  }

  // ============================================================
  // WRITE RANGE
  // ============================================================

  Future<void> updateRange({
    required String sheetTitle,
    required String range,
    required List<List<Object?>> values,
  }) async {
    final api =
        await _getApi();

    final id =
        _requireSpreadsheetId();

    final a1Range =
        '$sheetTitle!$range';

    await api.spreadsheets.values.update(
      sheets.ValueRange(
        values:
            values,
      ),
      id,
      a1Range,
      valueInputOption:
          'RAW',
    );
  }

  // ============================================================
  // WRITE HEADER
  // ============================================================

  Future<void> writeHeader({
    required String sheetTitle,
    required List<String> headers,
  }) async {
    await updateRange(
      sheetTitle:
          sheetTitle,
      range:
          'A1',
      values: [
        headers,
      ],
    );
  }

  // ============================================================
  // APPEND ROWS
  // ============================================================

  Future<void> appendRows({
    required String sheetTitle,
    required List<List<Object?>> rows,
  }) async {
    if (rows.isEmpty) {
      return;
    }

    final api =
        await _getApi();

    final id =
        _requireSpreadsheetId();

    await api.spreadsheets.values.append(
      sheets.ValueRange(
        values:
            rows,
      ),
      id,
      '$sheetTitle!A:ZZ',
      valueInputOption:
          'RAW',
      insertDataOption:
          'INSERT_ROWS',
    );
  }

  // ============================================================
  // READ RAW RANGE
  //
  // 6.5A foundation.
  // ============================================================

  Future<List<List<Object?>>>
      readRange({
    required String sheetTitle,
    String range = 'A:ZZ',
    String? spreadsheetId,
  }) async {
    final api =
        await _getApi(initializeTarget: spreadsheetId == null);

    final id =
        spreadsheetId ?? _requireSpreadsheetId();

    final a1Range =
        '$sheetTitle!$range';

    final response =
        await api.spreadsheets.values.get(
      id,
      a1Range,
    );

    return (response.values ??
            const <List<Object?>>[])
        .map(
          (row) => row.cast<Object?>(),
        )
        .toList();
  }

  // ============================================================
  // READ WHOLE SHEET
  // ============================================================

  Future<List<List<Object?>>>
      readSheet(
    String sheetTitle,
  ) async {
    return readRange(
      sheetTitle:
          sheetTitle,
      range:
          'A:ZZ',
    );
  }

  // ============================================================
  // DOWNLOAD SHEET AS MAPS
  //
  // The first row is treated as the header row.
  //
  // Example:
  //
  // [
  //   {
  //     'SyncID': 'abc123',
  //     'LearnerID': '1',
  //     'LastName': 'Santos',
  //     ...
  //   }
  // ]
  //
  // Empty cells become null.
  // ============================================================

  Future<List<Map<String, Object?>>>
      downloadSheetRows({
    required String sheetTitle,
  }) async {
    final raw =
        await readSheet(
      sheetTitle,
    );

    if (raw.isEmpty) {
      return const [];
    }

    final headers =
        raw.first
            .map(
              (value) =>
                  value
                      ?.toString()
                      .trim() ??
                  '',
            )
            .toList();

    if (headers.isEmpty) {
      return const [];
    }

    final rows =
        <Map<String, Object?>>[];

    for (
      var rowIndex = 1;
      rowIndex < raw.length;
      rowIndex++
    ) {
      final sourceRow =
          raw[rowIndex];

      // Ignore completely blank rows.
      if (_isBlankRow(
        sourceRow,
      )) {
        continue;
      }

      final map =
          <String, Object?>{};

      for (
        var columnIndex = 0;
        columnIndex < headers.length;
        columnIndex++
      ) {
        final header =
            headers[columnIndex];

        if (header.isEmpty) {
          continue;
        }

        Object? value;

        if (columnIndex <
            sourceRow.length) {
          value =
              sourceRow[columnIndex];

          if (value is String) {
            final text =
                value.trim();

            value =
                text.isEmpty
                    ? null
                    : text;
          }
        } else {
          value = null;
        }

        map[header] =
            value;
      }

      rows.add(
        map,
      );
    }

    return rows;
  }

  // ============================================================
  // DOWNLOAD WITH EXPECTED HEADERS
  //
  // This protects us from accidentally reading a worksheet
  // whose structure does not match our application.
  // ============================================================

  Future<List<Map<String, Object?>>>
      downloadTable({
    required String sheetTitle,
    required List<String> expectedHeaders,
    String? spreadsheetId,
  }) async {
    final raw =
        await readRange(
      sheetTitle: sheetTitle,
      spreadsheetId: spreadsheetId,
    );

    if (raw.isEmpty) {
      if (spreadsheetId != null) {
        throw StateError('The $sheetTitle worksheet has no header row.');
      }
      return const [];
    }

    final actualHeaders =
        raw.first
            .map(
              (value) =>
                  value
                      ?.toString()
                      .trim() ??
                  '',
            )
            .toList();

    _validateHeaders(
      sheetTitle:
          sheetTitle,
      expectedHeaders:
          expectedHeaders,
      actualHeaders:
          actualHeaders,
    );

    return _convertRowsToMaps(
      headers:
          actualHeaders,
      rawRows:
          raw.skip(1).toList(),
    );
  }

  // ============================================================
  // DOWNLOAD LEARNERS
  // ============================================================

  Future<List<Map<String, Object?>>>
      downloadLearners({String? spreadsheetId}) {
    return downloadTable(
      spreadsheetId: spreadsheetId,
      sheetTitle:
          learnersSheet,
      expectedHeaders:
          learnerHeaders,
    );
  }

  // ============================================================
  // DOWNLOAD TEACHERS
  // ============================================================

  Future<List<Map<String, Object?>>>
      downloadTeachers({String? spreadsheetId}) {
    return downloadTable(
      spreadsheetId: spreadsheetId,
      sheetTitle:
          teachersSheet,
      expectedHeaders:
          teacherHeaders,
    );
  }

  // ============================================================
  // DOWNLOAD SECTIONS
  // ============================================================

  Future<List<Map<String, Object?>>>
      downloadSections({String? spreadsheetId}) {
    return downloadTable(
      spreadsheetId: spreadsheetId,
      sheetTitle:
          sectionsSheet,
      expectedHeaders:
          sectionHeaders,
    );
  }

  // ============================================================
  // DOWNLOAD SCHOOL HISTORY
  // ============================================================

  Future<List<Map<String, Object?>>>
      downloadSchoolHistory({String? spreadsheetId}) {
    return downloadTable(
      spreadsheetId: spreadsheetId,
      sheetTitle:
          schoolHistorySheet,
      expectedHeaders:
          schoolHistoryHeaders,
    );
  }

  // ============================================================
  // DOWNLOAD INCIDENTS
  // ============================================================

  Future<List<Map<String, Object?>>>
      downloadIncidents({String? spreadsheetId}) {
    return downloadTable(
      spreadsheetId: spreadsheetId,
      sheetTitle:
          incidentsSheet,
      expectedHeaders:
          incidentHeaders,
    );
  }

  // ============================================================
  // DOWNLOAD ALL TABLES
  //
  // This is the main 6.5A method.
  //
  // IMPORTANT:
  // This only reads Google Sheets.
  // It does NOT modify SQLite.
  // ============================================================

  Future<GoogleSheetsDownload>
      downloadAllTables({String? spreadsheetId}) async {
    final learners =
        await downloadLearners(spreadsheetId: spreadsheetId);

    final teachers =
        await downloadTeachers(spreadsheetId: spreadsheetId);

    final sections =
        await downloadSections(spreadsheetId: spreadsheetId);

    final schoolHistory =
        await downloadSchoolHistory(spreadsheetId: spreadsheetId);

    final incidents =
        await downloadIncidents(spreadsheetId: spreadsheetId);

    return GoogleSheetsDownload(
      learners:
          learners,
      teachers:
          teachers,
      sections:
          sections,
      schoolHistory:
          schoolHistory,
      incidents:
          incidents,
    );
  }

  // ============================================================
  // FIND REMOTE RECORD BY SYNC ID
  // ============================================================

  Future<Map<String, Object?>?>
      findRemoteRecordBySyncId({
    required String sheetTitle,
    required String syncId,
  }) async {
    final rows =
        await downloadSheetRows(
      sheetTitle:
          sheetTitle,
    );

    final target =
        syncId.trim();

    if (target.isEmpty) {
      return null;
    }

    for (final row
        in rows) {
      final remoteId =
          row['SyncID']
                  ?.toString()
                  .trim() ??
              '';

      if (remoteId == target) {
        return row;
      }
    }

    return null;
  }


    // ============================================================
    // DELETE REMOTE RECORD BY SYNC ID
    //
    // Permanently removes matching rows from Google Sheets.
    //
    // The first row (header) is never deleted.
    //
    // Returns:
    //   Number of rows deleted.
    //
    // If the SyncID does not exist remotely, returns 0.
    // ============================================================

    Future<int> deleteRowsBySyncId({
      required String sheetTitle,
      required String syncId,
    }) async {
      final target =
          syncId.trim();

      if (target.isEmpty) {
        return 0;
      }

      final sheet =
          await findSheet(
        sheetTitle,
      );

      if (sheet == null) {
        throw StateError(
          'The $sheetTitle worksheet was not found.',
        );
      }

      final sheetId =
          sheet.properties?.sheetId;

      if (sheetId == null) {
        throw StateError(
          'The $sheetTitle worksheet does not have a valid sheet ID.',
        );
      }

      final raw =
          await readRange(
        sheetTitle: sheetTitle,
        range: 'A:ZZ',
      );

      if (raw.length <= 1) {
        return 0;
      }

      final headers =
          raw.first
              .map(
                (value) =>
                    value
                        ?.toString()
                        .trim() ??
                    '',
              )
              .toList();

      final syncIdColumn =
          headers.indexOf(
        'SyncID',
      );

      if (syncIdColumn < 0) {
        throw StateError(
          'The $sheetTitle worksheet does not contain a SyncID column.',
        );
      }

      // ----------------------------------------------------------
      // Find all matching worksheet row numbers.
      //
      // raw[0] is the header row.
      // Google Sheets row numbers are 1-based.
      // ----------------------------------------------------------

      final matchingRows =
          <int>[];

      for (
        var i = 1;
        i < raw.length;
        i++
      ) {
        final row =
            raw[i];

        if (syncIdColumn >=
            row.length) {
          continue;
        }

        final rowSyncId =
            row[syncIdColumn]
                    ?.toString()
                    .trim() ??
                '';

        if (rowSyncId == target) {
          // Convert zero-based raw list index
          // into one-based Google Sheets row number.
          matchingRows.add(
            i + 1,
          );
        }
      }

      if (matchingRows.isEmpty) {
        return 0;
      }

      // ----------------------------------------------------------
      // Delete from bottom to top.
      //
      // This prevents deleting one row from shifting the
      // positions of rows that still need to be deleted.
      // ----------------------------------------------------------

      matchingRows.sort(
        (a, b) => b.compareTo(a),
      );

      final requests =
          <sheets.Request>[];

      for (final rowNumber
          in matchingRows) {
        // Google Sheets API uses zero-based indexes.
        final startIndex =
            rowNumber - 1;

        requests.add(
          sheets.Request(
            deleteDimension:
                sheets.DeleteDimensionRequest(
              range:
                  sheets.DimensionRange(
                sheetId:
                    sheetId,
                dimension:
                    'ROWS',
                startIndex:
                    startIndex,
                endIndex:
                    rowNumber,
              ),
            ),
          ),
        );
      }

      final api =
          await _getApi();

      final spreadsheetId =
          _requireSpreadsheetId();

      await api.spreadsheets.batchUpdate(
        sheets.BatchUpdateSpreadsheetRequest(
          requests:
              requests,
        ),
        spreadsheetId,
      );

      return matchingRows.length;
    }

  // ============================================================
  // VALIDATE HEADERS
  // ============================================================

  void _validateHeaders({
    required String sheetTitle,
    required List<String> expectedHeaders,
    required List<String> actualHeaders,
  }) {
    if (actualHeaders.length <
        expectedHeaders.length) {
      throw StateError(
        'The $sheetTitle worksheet has fewer columns than expected.',
      );
    }

    for (
      var i = 0;
      i < expectedHeaders.length;
      i++
    ) {
      final expected =
          expectedHeaders[i];

      final actual =
          actualHeaders[i];

      if (actual != expected) {
        throw StateError(
          'The $sheetTitle worksheet has an unexpected header at column '
          '${i + 1}.\n'
          'Expected: $expected\n'
          'Found: $actual',
        );
      }
    }
  }

  // ============================================================
  // CONVERT ROWS TO MAPS
  // ============================================================

  List<Map<String, Object?>>
      _convertRowsToMaps({
    required List<String> headers,
    required List<List<Object?>> rawRows,
  }) {
    final result =
        <Map<String, Object?>>[];

    for (final sourceRow
        in rawRows) {
      if (_isBlankRow(
        sourceRow,
      )) {
        continue;
      }

      final row =
          <String, Object?>{};

      for (
        var i = 0;
        i < headers.length;
        i++
      ) {
        final header =
            headers[i];

        if (header.isEmpty) {
          continue;
        }

        Object? value;

        if (i <
            sourceRow.length) {
          value =
              sourceRow[i];
        }

        if (value is String) {
          final text =
              value.trim();

          value =
              text.isEmpty
                  ? null
                  : text;
        }

        row[header] =
            value;
      }

      result.add(
        row,
      );
    }

    return result;
  }

  // ============================================================
  // BLANK ROW
  // ============================================================

  bool _isBlankRow(
    List<Object?> row,
  ) {
    if (row.isEmpty) {
      return true;
    }

    for (final value
        in row) {
      if (value == null) {
        continue;
      }

      if (value
          .toString()
          .trim()
          .isNotEmpty) {
        return false;
      }
    }

    return true;
  }

  // ============================================================
  // UPSERT BY SYNC ID
  //
  // This remains part of 6.4C.
  // ============================================================

  Future<GoogleSheetWriteResult>
      upsertRowsBySyncId({
    required String sheetTitle,
    required List<String> headers,
    required List<List<Object?>> rows,
    Map<String, Map<String, Object?>?>? expectedRecords,
  }) async {
    if (rows.isEmpty) {
      return const GoogleSheetWriteResult(
        inserted: 0,
        updated: 0,
      );
    }

    if (!headers.contains(
      'SyncID',
    )) {
      throw StateError(
        'The $sheetTitle sheet must contain a SyncID column.',
      );
    }

    final existing =
        await readRange(
      sheetTitle:
          sheetTitle,
      range:
          'A:ZZ',
    );

    if (expectedRecords != null) {
      if (existing.isEmpty) throw const RemoteRecordChanged();
      _validateHeaders(sheetTitle: sheetTitle, expectedHeaders: headers,
          actualHeaders: existing.first.map((v) => v?.toString().trim() ?? '').toList());
      // Service calls use one row per request: this read is immediately before
      // its write, not a stale index reused across a batch of remote updates.
      final records = _convertRowsToMaps(headers: headers, rawRows: existing.skip(1).toList());
      for (final entry in expectedRecords.entries) {
        final matches = records.where((r) => r['SyncID']?.toString().trim() == entry.key).toList();
        if (matches.length > 1 || !SyncRecordState.same(
            matches.isEmpty ? null : matches.single, entry.value)) {
          throw const RemoteRecordChanged();
        }
      }
    }
    final syncIdColumn =
        headers.indexOf(
      'SyncID',
    );

    final existingRows =
        <String, int>{};

    for (
      var i = 1;
      i < existing.length;
      i++
    ) {
      final row =
          existing[i];

      if (syncIdColumn >=
          row.length) {
        continue;
      }

      final syncId =
          row[syncIdColumn]
                  ?.toString()
                  .trim() ??
              '';

      if (syncId.isEmpty) {
        continue;
      }

      existingRows[syncId] =
          i + 1;
    }

    final rowsToAppend =
        <List<Object?>>[];

    var updated = 0;

    for (final row in rows) {
      if (syncIdColumn >=
          row.length) {
        throw StateError(
          'A row for $sheetTitle does not contain enough columns for SyncID.',
        );
      }

      final syncId =
          row[syncIdColumn]
                  ?.toString()
                  .trim() ??
              '';

      if (syncId.isEmpty) {
        throw StateError(
          'A $sheetTitle row has an empty SyncID.',
        );
      }

      final existingRow =
          existingRows[syncId];

      if (existingRow == null) {
        rowsToAppend.add(
          row,
        );
        continue;
      }

      await updateRange(
        sheetTitle:
            sheetTitle,
        range:
            'A$existingRow:${_columnLetter(headers.length)}$existingRow',
        values: [
          row,
        ],
      );

      updated++;
    }

    if (rowsToAppend.isNotEmpty) {
      await appendRows(
        sheetTitle:
            sheetTitle,
        rows:
            rowsToAppend,
      );
    }

    return GoogleSheetWriteResult(
      inserted:
          rowsToAppend.length,
      updated:
          updated,
    );
  }

  // ============================================================
  // CONNECTION TEST
  // ============================================================

  Future<String>
      runConnectionTest() async {
    try {
      await initialize();

      final id =
          _spreadsheetId;

      if (id == null ||
          id.trim().isEmpty) {
        return '''
GOOGLE SHEETS CONNECTION TEST

Authentication is available, but no spreadsheet
has been configured.
''';
      }

      final spreadsheet =
          await getSpreadsheet();

      final title =
          spreadsheet.properties
                  ?.title ??
              '(Untitled)';

      final titles =
          await getSheetTitles();

      return '''
GOOGLE SHEETS CONNECTION TEST SUCCESSFUL

Spreadsheet:
  $title

Spreadsheet ID:
  $id

Worksheets:
  ${titles.join(', ')}
''';
    } catch (e) {
      return '''
GOOGLE SHEETS CONNECTION TEST FAILED

$e
''';
    }
  }

  // ============================================================
  // COLUMN LETTER
  // ============================================================

  String _columnLetter(
    int columnNumber,
  ) {
    var number =
        columnNumber;

    final buffer =
        StringBuffer();

    while (number > 0) {
      final remainder =
          (number - 1) % 26;

      buffer.write(
        String.fromCharCode(
          65 + remainder,
        ),
      );

      number =
          (number - 1) ~/ 26;
    }

    return buffer
        .toString()
        .split('')
        .reversed
        .join();
  }
}

// ================================================================
// DOWNLOAD RESULT
// ================================================================

class GoogleSheetsDownload {
  const GoogleSheetsDownload({
    required this.learners,
    required this.teachers,
    required this.sections,
    required this.schoolHistory,
    required this.incidents,
  });

  final List<Map<String, Object?>>
      learners;

  final List<Map<String, Object?>>
      teachers;

  final List<Map<String, Object?>>
      sections;

  final List<Map<String, Object?>>
      schoolHistory;

  final List<Map<String, Object?>>
      incidents;

  int get total =>
      learners.length +
      teachers.length +
      sections.length +
      schoolHistory.length +
      incidents.length;
}

// ================================================================
// WRITE RESULT
// ================================================================

class GoogleSheetWriteResult {
  const GoogleSheetWriteResult({
    required this.inserted,
    required this.updated,
  });

  final int inserted;

  final int updated;

  int get total =>
      inserted + updated;
}
