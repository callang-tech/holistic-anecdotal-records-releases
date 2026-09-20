import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class AnecdotalPdfService {
  // ==========================================================
  // GENERATE PDF
  // ==========================================================

  static Future<Uint8List> generate({
    required Map<String, Object?> learner,
    required List<Map<String, Object?>> schoolHistory,
    required List<Map<String, Object?>> incidents,
  }) async {
    final pdf = pw.Document();

    // Use Unicode-capable fonts instead of built-in fonts
    final regularFont = await PdfGoogleFonts.notoSansRegular();
    final boldFont = await PdfGoogleFonts.notoSansBold();

    final pdfTheme = pw.ThemeData.withFont(
      base: regularFont,
      bold: boldFont,
    );

    // ----------------------------------------------------------
    // LOAD SCHOOL IMAGES
    // ----------------------------------------------------------

    pw.MemoryImage? headerImage;
    pw.MemoryImage? footerImage;

    try {
      final headerData = await rootBundle.load('assets/images/SchoolHeader.png');
      headerImage = pw.MemoryImage(headerData.buffer.asUint8List());
    } catch (_) {}

    try {
      final footerData = await rootBundle.load('assets/images/SchoolFooter.png');
      footerImage = pw.MemoryImage(footerData.buffer.asUint8List());
    } catch (_) {}

    // ----------------------------------------------------------
    // PAGE FORMAT & THEME SETUP
    // ----------------------------------------------------------

    const pageFormat = PdfPageFormat.a4; // 8.27" x 11.69"
    
    const horizontalMargin = 0.4 * PdfPageFormat.inch;
    const verticalMargin = 0.5 * PdfPageFormat.inch; // <--- 0.5" Bottom & Top Margin Base
    const bottomMargin = 0.25 * PdfPageFormat.inch; // Defined custom bottom margin

    final fullPageWidth = pageFormat.width;

    // Header/Footer heights scaled to full paper width for full bleed
    final headerHeight = fullPageWidth * (317 / 1270);
    final footerHeight = fullPageWidth * (154 / 1269);

    final pageTheme = pw.PageTheme(
      pageFormat: pageFormat,
      theme: pdfTheme,
      margin: const pw.EdgeInsets.only(
        left: horizontalMargin,
        right: horizontalMargin,
        top: verticalMargin,
        bottom: bottomMargin, // Your 0.25" bottom margin
      ),
      // ------------------------------------------------------
      // FULL-BLEED BACKGROUND IMAGES
      // ------------------------------------------------------
      buildBackground: (context) {
        final isLastPage = context.pageNumber == context.pagesCount;

        return pw.Stack(
          children: [
            // Full-bleed Footer on Last Page (Renders BEHIND content & page numbers)
            if (isLastPage && footerImage != null)
              pw.Positioned(
                bottom: -0.25 * PdfPageFormat.inch, // Offset bottom margin to touch page edge
                left: -horizontalMargin,            // Offset left margin for full width
                right: -horizontalMargin,           // Offset right margin for full width
                child: pw.SizedBox(
                  width: fullPageWidth,
                  height: footerHeight,
                  child: pw.Image(
                    footerImage,
                    fit: pw.BoxFit.fill,
                  ),
                ),
              ),
          ],
        );
      },
    );

    // Format Learner Full Name
    final learnerFullName = _formatLearnerFullName(learner);

    // ----------------------------------------------------------
    // BUILD DOCUMENT
    // ----------------------------------------------------------

    pdf.addPage(
      pw.MultiPage(
        pageTheme: pageTheme,

        // ------------------------------------------------------
        // HEADER 
        // ------------------------------------------------------

        header: (context) {
          // Page 1: Render Full-Bleed Header Image in the topmost layout flow
          if (context.pageNumber == 1) {
            if (headerImage == null) return pw.SizedBox();
            
            return pw.Container(
              width: fullPageWidth,
              height: headerHeight,
              // Negative margins break it out of the horizontal and top paddings for full-bleed
              margin: const pw.EdgeInsets.only(
                left: -horizontalMargin,
                right: -horizontalMargin,
                top: -verticalMargin,
                bottom: 8, // Spacing before the first box
              ),
              child: pw.Image(
                headerImage,
                fit: pw.BoxFit.fill,
              ),
            );
          }

          // Page 2+: Standard minimal text header
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (learnerFullName.isNotEmpty) ...[
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      learnerFullName.toUpperCase(),
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.blueGrey800,
                      ),
                    ),
                    pw.Text(
                      'ANECDOTAL RECORD',
                      style: const pw.TextStyle(
                        fontSize: 8,
                        color: PdfColors.grey600,
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 3),
                pw.Divider(thickness: 0.5, color: PdfColors.grey400),
                pw.SizedBox(height: 6),
              ],
            ],
          );
        },

        // ------------------------------------------------------
        // FOOTER (Page Numbers - Renders OVER the background image)
        // ------------------------------------------------------

        footer: (context) {
          return pw.Container(
            alignment: pw.Alignment.bottomRight,
            padding: const pw.EdgeInsets.only(bottom: 4), // Fine-tune text placement over image
            child: pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: pw.TextStyle(
                fontSize: 7.5,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey900, // Make sure color is visible over your footer image
              ),
            ),
          );
        },

        // ------------------------------------------------------
        // CONTENT
        // ------------------------------------------------------

        build: (context) {
          return [
            pw.Center(
              child: pw.Text(
                'ANECDOTAL RECORD',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.blueGrey900,
                ),
              ),
            ),
            pw.SizedBox(height: 8),
            _buildLearnerInformation(
              learner,
              schoolHistory,
              learnerFullName,
            ),
            pw.SizedBox(height: 8),
            _buildSchoolHistory(
              schoolHistory,
            ),
            pw.SizedBox(height: 8),
            _buildIncidentRecords(
              incidents,
            ),
          ];
        },
      ),
    );

    final bytes = await pdf.save();
    return Uint8List.fromList(bytes);
  }

  // ==========================================================
  // LEARNER INFORMATION
  // ==========================================================

  static pw.Widget _buildLearnerInformation(
    Map<String, Object?> learner,
    List<Map<String, Object?>> history,
    String learnerFullName,
  ) {
    final currentHistory = _findCurrentSchoolHistory(history);
    final grade = _displayGrade(currentHistory?['Grade']);
    final section = _text(currentHistory?['Section']);
    final schoolYear = _text(currentHistory?['SchoolYear']);

    return pw.Container(
      width: double.infinity,
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.blueGrey700, width: 0.6),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Colored Title Box Header
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            color: PdfColors.blueGrey800,
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  learnerFullName.isEmpty ? 'LEARNER INFORMATION' : learnerFullName.toUpperCase(),
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white,
                  ),
                ),
                pw.Text(
                  'Learner Details',
                  style: const pw.TextStyle(
                    fontSize: 7,
                    color: PdfColors.grey300,
                  ),
                ),
              ],
            ),
          ),

          // Content Box
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Row 1: LRN, Grade / Section, School Year
                pw.Row(
                  children: [
                    pw.Expanded(
                      flex: 4,
                      child: _field('LRN', _text(learner['LearnerReferenceNumber'])),
                    ),
                    pw.SizedBox(width: 8),
                    pw.Expanded(
                      flex: 4,
                      child: _field('Grade / Section', _formatGradeSection(grade, section)),
                    ),
                    pw.SizedBox(width: 8),
                    pw.Expanded(
                      flex: 3,
                      child: _field('School Year', schoolYear),
                    ),
                  ],
                ),
                pw.SizedBox(height: 4),

                // Row 2: Birth Date, Age, Sex
                pw.Row(
                  children: [
                    pw.Expanded(
                      flex: 4,
                      child: _field('Birth Date', _text(learner['BirthDate'])),
                    ),
                    pw.SizedBox(width: 8),
                    pw.Expanded(
                      flex: 4,
                      child: _field('Age', _text(learner['Age'])),
                    ),
                    pw.SizedBox(width: 8),
                    pw.Expanded(
                      flex: 3,
                      child: _field('Sex', _text(learner['Sex'])),
                    ),
                  ],
                ),
                pw.SizedBox(height: 4),

                // Row 3: Address, Learner Contact No.
                pw.Row(
                  children: [
                    pw.Expanded(
                      flex: 8,
                      child: _field('Address', _compactAddress(learner)),
                    ),
                    pw.SizedBox(width: 8),
                    pw.Expanded(
                      flex: 3,
                      child: _field('Contact No.', _text(learner['ContactNo'])),
                    ),
                  ],
                ),
                pw.SizedBox(height: 4),

                // Row 4: Parents, Guardian, Parents/Guardian Contact No.
                pw.Row(
                  children: [
                    pw.Expanded(
                      flex: 4,
                      child: _field('Parents', _text(learner['Parents'])),
                    ),
                    pw.SizedBox(width: 8),
                    pw.Expanded(
                      flex: 4,
                      child: _field('Guardian', _text(learner['Guardian'])),
                    ),
                    pw.SizedBox(width: 8),
                    pw.Expanded(
                      flex: 3,
                      child: _field(
                        'Parents Contact',
                        _text(learner['ParentsContactNo'] ?? learner['GuardianContactNo']),
                      ),
                    ),
                  ],
                ),
                                // Row 5: Notes / Details
                if (_text(learner['NotesDetails']).isNotEmpty) ...[
                  pw.SizedBox(height: 4),
                  _paragraphField(
                    'Notes / Details',
                    _text(learner['NotesDetails']),
                  ),
                ],
                
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // SCHOOL HISTORY
  // ==========================================================

  static pw.Widget _buildSchoolHistory(
    List<Map<String, Object?>> history,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _sectionHeader('SCHOOL HISTORY'),
        pw.SizedBox(height: 4),
        if (history.isEmpty)
          pw.Text(
            'No school history records.',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          )
        else
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
            columnWidths: const {
              0: pw.FlexColumnWidth(1.0),
              1: pw.FlexColumnWidth(0.6),
              2: pw.FlexColumnWidth(1.6),
              3: pw.FlexColumnWidth(1.4),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  _tableHeader('School Year'),
                  _tableHeader('Grade'),
                  _tableHeader('School / Section'),
                  _tableHeader('Adviser'),
                ],
              ),
              ...history.map(
                (row) {
                  final school = _text(row['School']);
                  final section = _text(row['Section']);
                  final schoolSection = section.isEmpty ? school : '$school / $section';

                  return pw.TableRow(
                    children: [
                      _tableCell(_text(row['SchoolYear'])),
                      _tableCell(_displayGrade(row['Grade'])),
                      _tableCell(schoolSection),
                      _tableCell(_text(row['Adviser'])),
                    ],
                  );
                },
              ),
            ],
          ),
      ],
    );
  }

  // ==========================================================
  // INCIDENT RECORDS
  // ==========================================================

  static pw.Widget _buildIncidentRecords(
    List<Map<String, Object?>> incidents,
  ) {
    if (incidents.isEmpty) {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _sectionHeader('ANECDOTAL RECORDS'),
          pw.SizedBox(height: 4),
          pw.Text(
            'No incident records found.',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        ],
      );
    }

    final ordered = List<Map<String, Object?>>.from(incidents);
    ordered.sort((a, b) {
      final aDate = _parseStoredDate(_text(a['IncidentDate']));
      final bDate = _parseStoredDate(_text(b['IncidentDate']));

      if (aDate == null && bDate == null) return 0;
      if (aDate == null) return 1;
      if (bDate == null) return -1;

      final dateCompare = bDate.compareTo(aDate);
      if (dateCompare != 0) return dateCompare;

      return _text(b['IncidentTime']).compareTo(_text(a['IncidentTime']));
    });

    final total = ordered.length;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _sectionHeader('ANECDOTAL RECORDS'),
        pw.SizedBox(height: 5),
        ...List.generate(
          ordered.length,
          (index) {
            final incident = ordered[index];
            final incidentNumber = total - index;
            final dateVal = _text(incident['IncidentDate']);
            final timeVal = _text(incident['IncidentTime']);

            return pw.Container(
              width: double.infinity,
              margin: const pw.EdgeInsets.only(bottom: 6),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // Incident Header Title Box with Fill Color
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    color: PdfColors.blueGrey100,
                    child: pw.Row(
                      children: [
                        pw.Expanded(
                          flex: 4,
                          child: pw.Text(
                            'Incident #$incidentNumber',
                            style: pw.TextStyle(
                              fontSize: 9,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.blueGrey900,
                            ),
                          ),
                        ),
                        pw.Expanded(
                          flex: 4,
                          child: pw.Text(
                            dateVal.isEmpty ? '-' : dateVal,
                            style: pw.TextStyle(
                              fontSize: 8,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.grey900,
                            ),
                          ),
                        ),
                        pw.Expanded(
                          flex: 3,
                          child: pw.Text(
                            timeVal.isEmpty ? '-' : timeVal,
                            style: pw.TextStyle(
                              fontSize: 8,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.grey900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Content
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(6),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        // Row 2: Grade / Section, School Year, Adviser
                        pw.Row(
                          children: [
                            pw.Expanded(
                              flex: 4,
                              child: _field(
                                'Grade / Section',
                                _formatGradeSection(
                                  _displayGrade(incident['IncidentGrade']),
                                  _text(incident['IncidentSection']),
                                ),
                              ),
                            ),
                            pw.SizedBox(width: 6),
                            pw.Expanded(
                              flex: 4,
                              child: _field('School Year', _text(incident['IncidentSchoolYear'])),
                            ),
                            pw.SizedBox(width: 6),
                            pw.Expanded(
                              flex: 3,
                              child: _field('Adviser', _text(incident['IncidentAdviser'])),
                            ),
                          ],
                        ),
                        pw.SizedBox(height: 2),

                        // Row 3: Behavior / Observation, Intervention, Remarks
                        pw.Row(
                          children: [
                            pw.Expanded(
                              flex: 4,
                              child: _field('Behavior / Observation', _text(incident['BehaviorProblem'])),
                            ),
                            pw.SizedBox(width: 6),
                            pw.Expanded(
                              flex: 4,
                              child: _field('Intervention', _text(incident['Intervention'])),
                            ),
                            pw.SizedBox(width: 6),
                            pw.Expanded(
                              flex: 3,
                              child: _field('Remarks', _text(incident['Remarks'])),
                            ),
                          ],
                        ),
                        pw.SizedBox(height: 2),

                        _field('Observer', _text(incident['Observer'])),
                        _paragraphField(
                          'Observation Details',
                          _text(incident['ObservationDetails']),
                        ),
                        _paragraphField(
                          'Action Taken',
                          _text(incident['ActionTaken']),
                        ),
                        _paragraphField(
                          'Note / Details',
                          _text(incident['Details']),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  // ==========================================================
  // UI HELPERS
  // ==========================================================

  static pw.Widget _sectionHeader(String title) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      color: PdfColors.blueGrey800,
      child: pw.Text(
        title,
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.white,
        ),
      ),
    );
  }

  static pw.Widget _field(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.RichText(
        text: pw.TextSpan(
          children: [
            pw.TextSpan(
              text: '$label: ',
              style: const pw.TextStyle(
                fontSize: 8,
                color: PdfColors.grey900,
              ),
            ),
            pw.TextSpan(
              text: value.isEmpty ? '-' : value,
              style: const pw.TextStyle(
                fontSize: 8,
                color: PdfColors.grey800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _paragraphField(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3, top: 1),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label,
            style: const pw.TextStyle(
              fontSize: 7.5,
              color: PdfColors.grey900,
            ),
          ),
          pw.SizedBox(height: 1),
          pw.Text(
            value.isEmpty ? '-' : value,
            style: const pw.TextStyle(
              fontSize: 7.5,
              color: PdfColors.grey800,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _tableHeader(String value) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Text(
        value,
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(
          fontSize: 7.5,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.blueGrey900,
        ),
      ),
    );
  }

  static pw.Widget _tableCell(String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Text(
        value.isEmpty ? '-' : value,
        style: const pw.TextStyle(
          fontSize: 7.5,
          color: PdfColors.grey800,
        ),
      ),
    );
  }

  // ==========================================================
  // UTILS
  // ==========================================================

  static String _formatLearnerFullName(Map<String, Object?> learner) {
    final lastName = _text(learner['LastName']);
    final firstName = _text(learner['FirstName']);
    final middleName = _text(learner['MiddleName']);

    final parts = [lastName, firstName, middleName].where((v) => v.isNotEmpty);
    return parts.join(', ');
  }

  static String _text(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text
        .replaceAll('—', '-')
        .replaceAll('–', '-')
        .replaceAll('•', '-')
        .replaceAll('“', '"')
        .replaceAll('”', '"')
        .replaceAll('‘', "'")
        .replaceAll('’', "'");
  }

  static String _displayGrade(Object? value) {
    final grade = _text(value);
    if (grade.isEmpty) return '';
    if (grade.toUpperCase() == 'SNED') return 'SNED';
    if (grade.toLowerCase().startsWith('grade ')) return grade;
    return 'Grade $grade';
  }

  static String _formatGradeSection(String grade, String section) {
    if (grade.isEmpty) return section;
    if (section.isEmpty) return grade;
    return '$grade - $section';
  }

  static Map<String, Object?>? _findCurrentSchoolHistory(
    List<Map<String, Object?>> history,
  ) {
    if (history.isEmpty) return null;

    Map<String, Object?>? current;
    var currentYear = -1;

    for (final row in history) {
      final year = _schoolYearStartYear(_text(row['SchoolYear']));
      if (current == null || year > currentYear) {
        current = row;
        currentYear = year;
      }
    }
    return current;
  }

  static int _schoolYearStartYear(String schoolYear) {
    final match = RegExp(r'^(\d{4})\s*-\s*(\d{4})$').firstMatch(schoolYear.trim());
    if (match == null) return 0;
    return int.tryParse(match.group(1)!) ?? 0;
  }

  static String _compactAddress(Map<String, Object?> learner) {
    final fields = [
      learner['HouseNo'],
      learner['Street'],
      learner['Purok'],
      learner['Barangay'],
      learner['TownMunicipality'],
      learner['Province'],
      learner['Region'],
    ];

    return fields
        .map(_text)
        .where((value) => value.isNotEmpty)
        .join(', ');
  }

  static DateTime? _parseStoredDate(String? value) {
    if (value == null) return null;
    final text = value.trim();
    if (text.isEmpty) return null;

    final iso = DateTime.tryParse(text);
    if (iso != null) {
      return DateTime(iso.year, iso.month, iso.day);
    }

    const months = {
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

    final match = RegExp(r'^([A-Za-z]+)\s+(\d{1,2}),?\s+(\d{4})$').firstMatch(text);
    if (match == null) return null;

    final month = months[match.group(1)!.toLowerCase()];
    final year = int.tryParse(match.group(3)!);
    final day = int.tryParse(match.group(2)!);

    if (month == null || year == null || day == null) return null;

    return DateTime(year, month, day);
  }
}