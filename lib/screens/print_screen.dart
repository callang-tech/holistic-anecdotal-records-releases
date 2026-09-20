import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../database/database_repository.dart';
import '../services/anecdotal_pdf_service.dart';

class PrintScreen extends StatefulWidget {
  const PrintScreen({
    super.key,
  });

  @override
  State<PrintScreen> createState() =>
      _PrintScreenState();
}

class _PrintScreenState
    extends State<PrintScreen> {
  final DatabaseRepository _repository =
      DatabaseRepository.instance;

  Map<String, Object?>? _learner;

  List<Map<String, Object?>> _schoolHistory =
      [];

  List<Map<String, Object?>> _incidents =
      [];

  int? _learnerId;

  bool _loading = true;

  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_learnerId != null) {
      return;
    }

    final argument =
        ModalRoute.of(context)
            ?.settings
            .arguments;

    if (argument is int) {
      _learnerId = argument;
      _loadRecord(argument);
    }
  }

  // ============================================================
  // LOAD RECORD
  // ============================================================

  Future<void> _loadRecord(
    int learnerId,
  ) async {
    try {
      final learner =
          await _repository.getLearner(
        learnerId,
      );

      if (learner == null) {
        throw StateError(
          'Learner record could not be found.',
        );
      }

      final schoolHistory =
          await _repository.getSchoolHistory(
        learnerId,
      );

      final incidents =
          await _repository.getIncidents(
        learnerId,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _learner = learner;
        _schoolHistory = schoolHistory;
        _incidents = incidents;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  // ============================================================
  // PDF GENERATION
  // ============================================================

  Future<Uint8List> _generatePdf() async {
    final learner = _learner;

    if (learner == null) {
      throw StateError(
        'The learner record has not finished loading.',
      );
    }

    return AnecdotalPdfService.generate(
      learner: learner,
      schoolHistory: List<Map<String, Object?>>.from(
        _schoolHistory,
      ),
      incidents: List<Map<String, Object?>>.from(
        _incidents,
      ),
    );
  }

  // ============================================================
  // PRINT
  // ============================================================

  Future<void> _printDocument() async {
    if (_learner == null) {
      return;
    }

    try {
      final bytes =
          await _generatePdf();

      if (!mounted) {
        return;
      }

      await Printing.layoutPdf(
        onLayout: (
          PdfPageFormat format,
        ) async {
          return bytes;
        },
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      _showMessage(
        'Unable to print the document.\n$e',
      );
    }
  }

  // ============================================================
  // SAVE PDF
  // ============================================================

  Future<void> _sharePdf() async {
    if (_learner == null) {
      return;
    }

    try {
      final bytes =
          await _generatePdf();

      final lastName =
          _text(
        _learner?['LastName'],
      );

      final firstName =
          _text(
        _learner?['FirstName'],
      );

      final fileName =
          [
            if (lastName.isNotEmpty)
              lastName,
            if (firstName.isNotEmpty)
              firstName,
          ].join('_');

      await Printing.sharePdf(
        bytes: bytes,
        filename:
            fileName.isEmpty
                ? 'Anecdotal_Record.pdf'
                : '${fileName}_Anecdotal_Record.pdf',
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      _showMessage(
        'Unable to export the PDF.\n$e',
      );
    }
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text(
            'Print Preview',
          ),
        ),
        body: const Center(
          child:
              CircularProgressIndicator(),
        ),
      );
    }

    if (_error != null ||
        _learner == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text(
            'Print Preview',
          ),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(
              maxWidth: 600,
            ),
            child: Card(
              child: Padding(
                padding:
                    const EdgeInsets.all(
                  24,
                ),
                child: Column(
                  mainAxisSize:
                      MainAxisSize.min,
                  children: [
                    Icon(
                      Icons
                          .error_outline_rounded,
                      size: 52,
                      color:
                          Theme.of(
                        context,
                      )
                              .colorScheme
                              .error,
                    ),

                    const SizedBox(
                      height: 12,
                    ),

                    const Text(
                      'Unable to load the printable record.',
                      textAlign:
                          TextAlign.center,
                      style:
                          TextStyle(
                        fontSize: 18,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),

                    const SizedBox(
                      height: 10,
                    ),

                    Text(
                      _error ??
                          'Unknown error.',
                      textAlign:
                          TextAlign.center,
                    ),

                    const SizedBox(
                      height: 20,
                    ),

                    FilledButton(
                      onPressed: () {
                        Navigator.pop(
                          context,
                        );
                      },
                      child:
                          const Text(
                        'Back',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    final learner =
        _learner!;

    final learnerName =
        _formatLearnerName(
      learner,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Print Preview',
        ),

        actions: [
          Tooltip(
            message:
                'Export PDF',
            child:
                IconButton(
              onPressed:
                  _sharePdf,
              icon:
                  const Icon(
                Icons
                    .picture_as_pdf_rounded,
              ),
            ),
          ),

          Tooltip(
            message:
                'Print',
            child:
                IconButton(
              onPressed:
                  _printDocument,
              icon:
                  const Icon(
                Icons.print_rounded,
              ),
            ),
          ),
        ],
      ),

      body: Column(
        children: [
          // ------------------------------------------------------
          // INFORMATION BAR
          // ------------------------------------------------------

          Container(
            width:
                double.infinity,
            padding:
                const EdgeInsets
                    .symmetric(
              horizontal: 16,
              vertical: 9,
            ),
            child:
                Row(
              children: [
                const Icon(
                  Icons
                      .description_rounded,
                  size: 20,
                ),

                const SizedBox(
                  width: 8,
                ),

                Expanded(
                  child:
                      Text(
                    'ANECDOTAL RECORD'
                    '${learnerName.isEmpty ? '' : ' • $learnerName'}',
                    maxLines: 1,
                    overflow:
                        TextOverflow
                            .ellipsis,
                    style:
                        const TextStyle(
                      fontWeight:
                          FontWeight.w600,
                    ),
                  ),
                ),

                Text(
                  '${_schoolHistory.length} school history • '
                  '${_incidents.length} incident(s)',
                  style:
                      TextStyle(
                    fontSize: 12,
                    color:
                        Theme.of(
                      context,
                    )
                            .colorScheme
                            .onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),

          const Divider(
            height: 1,
          ),

          // ------------------------------------------------------
          // PDF PREVIEW
          // ------------------------------------------------------

          Expanded(
            child:
                PdfPreview(
                  allowPrinting: false,
                  allowSharing: false,
                  canChangePageFormat: false,
                  canChangeOrientation: false,
                  canDebug: false,
                  pdfFileName: 'Anecdotal_Record.pdf',
                  pageFormats: const {
                    'A4': PdfPageFormat.a4,
                  },
                  build: (format) => _generatePdf(),
                ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // HELPERS
  // ============================================================

  String _text(
    Object? value,
  ) {
    return value
            ?.toString()
            .trim() ??
        '';
  }

  String _formatLearnerName(
    Map<String, Object?> learner,
  ) {
    final lastName =
        _text(
      learner['LastName'],
    );

    final firstName =
        _text(
      learner['FirstName'],
    );

    final middleName =
        _text(
      learner['MiddleName'],
    );

    if (lastName.isEmpty &&
        firstName.isEmpty &&
        middleName.isEmpty) {
      return '';
    }

    return [
      if (lastName.isNotEmpty)
        lastName,
      if (firstName.isNotEmpty)
        firstName,
      if (middleName.isNotEmpty)
        middleName,
    ].join(', ');
  }

  void _showMessage(
    String message,
  ) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(
      SnackBar(
        content:
            Text(message),
      ),
    );
  }
}