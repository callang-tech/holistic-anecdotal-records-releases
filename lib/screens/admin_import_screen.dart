import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../database/database_repository.dart';

enum _ImportType {
  teachers,
  sections,
}

class AdminImportScreen extends StatefulWidget {
  const AdminImportScreen({
    super.key,
  });

  @override
  State<AdminImportScreen> createState() =>
      _AdminImportScreenState();
}

class _AdminImportScreenState
    extends State<AdminImportScreen> {
  final DatabaseRepository _repository =
      DatabaseRepository.instance;

  _ImportType _type =
      _ImportType.teachers;

  List<String> _headers = [];
  final List<List<String>> _rows = [];

  bool _saving = false;

  final List<List<TextEditingController>>
    _cellControllers = [];

    int? _selectedRow;
    int? _selectedColumn;

  final ScrollController _verticalScrollController =
      ScrollController();

  final ScrollController _horizontalScrollController =
      ScrollController();

  static const List<String> _teacherHeaders = [
    'TeacherName',
    'MobileNumber',
    'Status',
  ];

  static const List<String> _sectionHeaders = [
    'SchoolYear',
    'GradeLevel',
    'SectionName',
    'Adviser',
  ];

  @override
  void initState() {
    super.initState();

    _headers =
        List<String>.from(
      _teacherHeaders,
    );
  }

  // ============================================================
  // CURRENT IMPORT TYPE
  // ============================================================

  String get _title {
    switch (_type) {
      case _ImportType.teachers:
        return 'Import Teachers';

      case _ImportType.sections:
        return 'Import Sections';

    }
  }

  List<String> get _currentHeaders {
    switch (_type) {
      case _ImportType.teachers:
        return _teacherHeaders;

      case _ImportType.sections:
        return _sectionHeaders;

    }
  }

  void _changeImportType(
    _ImportType type,
  ) {
    setState(() {
      _type = type;
      _headers =
          List<String>.from(
        _currentHeaders,
      );
      _rows.clear();
    });
  }

  void _rebuildCellControllers() {
    for (final row in _cellControllers) {
      for (final controller in row) {
        controller.dispose();
      }
    }

    _cellControllers.clear();

    for (final row in _rows) {
      _cellControllers.add(
        List.generate(
          _headers.length,
          (columnIndex) {
            final value = columnIndex < row.length
                ? row[columnIndex]
                : '';

            return TextEditingController(
              text: value,
            );
          },
        ),
      );
    }
  }

  

  void _selectCell(
    int row,
    int column,
  ) {
    setState(() {
      _selectedRow = row;
      _selectedColumn = column;
    });
  }


  bool _isHeaderRow(
    List<String> row,
  ) {
    if (row.isEmpty) {
      return false;
    }

    var matches = 0;

    for (
      var i = 0;
      i < row.length &&
          i < _headers.length;
      i++
    ) {
      final actual =
          _normalizeHeader(row[i]);

      if (actual.isEmpty) {
        continue;
      }

      final expected =
          _normalizeHeader(_headers[i]);

      if (actual == expected) {
        matches++;
      }
    }

    // For a 3-column teacher table,
    // 2 matching headers is enough.
    //
    // For larger tables, 2+ also works.
    return matches >= 2;
  }

  String _normalizeHeader(
    String value,
  ) {
    return value
        .toLowerCase()
        .replaceAll(
          RegExp(r'[^a-z0-9]'),
          '',
        );
  }

  // ============================================================
  // GRID
  // ============================================================

  void _addBlankRow() {
    setState(() {
      _rows.add(
        List<String>.filled(
          _headers.length,
          '',
        ),
      );
    });

    _rebuildCellControllers();
  }

  void _deleteRow(
    int index,
  ) {
    if (index < 0 ||
        index >= _rows.length) {
      return;
    }

    setState(() {
      _rows.removeAt(index);

      if (_selectedRow == index) {
        _selectedRow = null;
        _selectedColumn = null;
      } else if (_selectedRow != null &&
          _selectedRow! > index) {
        _selectedRow =
            _selectedRow! - 1;
      }
    });

    _rebuildCellControllers();
  }

  void _clearRows() {
    setState(() {
      _rows.clear();
    });
  }

  void _updateCell(
    int row,
    int column,
    String value,
  ) {
    _rows[row][column] = value;
  }

  // ============================================================
  // VALIDATION
  // ============================================================

  List<String> _validateRows() {
    final errors =
        <String>[];

    for (
      var rowIndex = 0;
      rowIndex < _rows.length;
      rowIndex++
    ) {
      final row =
          _rows[rowIndex];

      String value(
        String header,
      ) {
        final index =
            _headers.indexOf(
          header,
        );

        if (index < 0 ||
            index >= row.length) {
          return '';
        }

        return row[index]
            .trim();
      }

      final displayRow =
          rowIndex + 1;

      switch (_type) {
        case _ImportType.teachers:
          if (value(
            'TeacherName',
          ).isEmpty) {
            errors.add(
              'Row $displayRow: TeacherName is required.',
            );
          }

          final mobile =
              value(
            'MobileNumber',
          );

          if (mobile.isNotEmpty &&
              !RegExp(
                r'^\d{11}$',
              ).hasMatch(mobile)) {
            errors.add(
              'Row $displayRow: MobileNumber must contain 11 digits.',
            );
          }

        case _ImportType.sections:
          if (value(
            'SchoolYear',
          ).isEmpty) {
            errors.add(
              'Row $displayRow: SchoolYear is required.',
            );
          } else if (!_validSchoolYear(
            value(
              'SchoolYear',
            ),
          )) {
            errors.add(
              'Row $displayRow: SchoolYear must use YYYY-YYYY.',
            );
          }

          if (value(
            'GradeLevel',
          ).isEmpty) {
            errors.add(
              'Row $displayRow: GradeLevel is required.',
            );
          }

          if (value(
            'SectionName',
          ).isEmpty) {
            errors.add(
              'Row $displayRow: SectionName is required.',
            );
          }

}
    }

    return errors;
  }

  bool _validSchoolYear(
    String value,
  ) {
    final match = RegExp(
      r'^(\d{4})-(\d{4})$',
    ).firstMatch(
      value.trim(),
    );

    if (match == null) {
      return false;
    }

    final first =
        int.parse(
      match.group(1)!,
    );

    final second =
        int.parse(
      match.group(2)!,
    );

    return second ==
        first + 1;
  }

  // ============================================================
  // IMPORT
  // ============================================================

  Future<void> _importRecords() async {
    if (_rows.isEmpty) {
      _showMessage(
        'There are no rows to import.',
      );
      return;
    }

    final errors =
        _validateRows();

    if (errors.isNotEmpty) {
      await _showValidationErrors(
        errors,
      );
      return;
    }

    final confirmed =
        await _confirmImport();

    if (confirmed != true) {
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      final records =
          _rows.map(
        (row) {
          final map =
              <String, Object?>{};

          for (
            var i = 0;
            i < _headers.length;
            i++
          ) {
            map[_headers[i]] =
                row[i].trim();
          }

          return map;
        },
      ).toList();

      int inserted;

      switch (_type) {
        case _ImportType.teachers:
          inserted =
              await _repository
                  .bulkAddTeachers(
            records,
          );
          break;

        case _ImportType.sections:
          inserted =
              await _repository
                  .bulkAddSections(
            records,
          );
          break;

      }

      if (!mounted) {
        return;
      }

      setState(() {
        _rows.clear();
      });

      _showMessage(
        '$inserted record(s) imported successfully.',
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      _showMessage(
        'Import failed.\n$e',
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<bool?> _confirmImport() {
    final label =
        switch (_type) {
      _ImportType.teachers =>
        'teachers',
      _ImportType.sections =>
        'sections',
    };

    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title:
              const Text(
            'Confirm Import',
          ),
          content: Text(
            'Import ${_rows.length} $label record(s) into the local database?',
          ),
          actions: [
            TextButton(
              onPressed:
                  () => Navigator.pop(
                context,
                false,
              ),
              child:
                  const Text('Cancel'),
            ),
            FilledButton(
              onPressed:
                  () => Navigator.pop(
                context,
                true,
              ),
              child:
                  const Text('Import'),
            ),
          ],
        );
      },
    );
  }

  Future<void>
      _showValidationErrors(
    List<String> errors,
  ) async {
    final visible =
        errors.take(15).toList();

    final remaining =
        errors.length -
            visible.length;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            'Import Validation',
          ),
          content: SizedBox(
            width: 600,
            child:
                SingleChildScrollView(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment
                        .start,
                children: [
                  const Text(
                    'Please correct these rows before importing:',
                  ),
                  const SizedBox(
                    height: 12,
                  ),
                  ...visible.map(
                    (error) => Padding(
                      padding:
                          const EdgeInsets
                              .only(
                        bottom: 6,
                      ),
                      child: Text(
                        '• $error',
                      ),
                    ),
                  ),
                  if (remaining > 0)
                    Padding(
                      padding:
                          const EdgeInsets
                              .only(
                        top: 6,
                      ),
                      child: Text(
                        '...and $remaining more error(s).',
                        style:
                            const TextStyle(
                          fontStyle:
                              FontStyle.italic,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            FilledButton(
              onPressed:
                  () => Navigator.pop(
                context,
              ),
              child:
                  const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _pasteIntoGrid({
    int? startRow,
    int? startColumn,
  }) async {
    final row =
      startRow ?? _selectedRow ?? 0;

    final column =
      startColumn ?? _selectedColumn ?? 0;

    final clipboard =
        await Clipboard.getData(
      Clipboard.kTextPlain,
    );

    final text =
        clipboard?.text ?? '';

    if (text.isEmpty) {
      _showMessage(
        'The clipboard is empty.',
      );
      return;
    }

    final normalized =
        text.replaceAll(
      '\r\n',
      '\n',
    ).replaceAll(
      '\r',
      '\n',
    );

    final lines =
        normalized.split('\n');

    final clipboardRows =
        <List<String>>[];

    for (final line in lines) {
      if (line.isEmpty) {
        continue;
      }

      clipboardRows.add(
        line.split('\t'),
      );
    }

    if (clipboardRows.isEmpty) {
      return;
    }

    // ------------------------------------------------------------
    // If the copied range includes the application's headers,
    // skip the header row.
    // ------------------------------------------------------------

    if (_isHeaderRow(
      clipboardRows.first
          .map(
            (e) => e.trim(),
          )
          .toList(),
    )) {
      clipboardRows.removeAt(0);
    }

    if (clipboardRows.isEmpty) {
      return;
    }

    final requiredRowCount =
        row + clipboardRows.length;

    // ------------------------------------------------------------
    // Automatically create additional grid rows if necessary.
    // ------------------------------------------------------------

    while (_rows.length <
        requiredRowCount) {
      _rows.add(
        List<String>.filled(
          _headers.length,
          '',
        ),
      );
    }

    _rebuildCellControllers();

    // ------------------------------------------------------------
    // Populate the grid.
    // ------------------------------------------------------------

    var pastedCells = 0;

    for (
      var sourceRow = 0;
      sourceRow < clipboardRows.length;
      sourceRow++
    ) {
      final targetRow =
          row + sourceRow;

      final sourceCells =
          clipboardRows[sourceRow];

      for (
        var sourceColumn = 0;
        sourceColumn <
                sourceCells.length;
        sourceColumn++
      ) {
        final targetColumn =
            column + sourceColumn;

        if (targetColumn >=
            _headers.length) {
          break;
        }

        final value =
            sourceCells[sourceColumn]
                .trim();

        _rows[targetRow]
            [targetColumn] = value;

        if (targetRow <
                _cellControllers.length &&
            targetColumn <
                _cellControllers[
                    targetRow].length) {
          _cellControllers[
                  targetRow]
              [targetColumn]
              .value =
              TextEditingValue(
            text: value,
            selection:
                TextSelection.collapsed(
              offset: value.length,
            ),
          );
        }

        pastedCells++;
      }
    }

    setState(() {
      _selectedRow = row;
      _selectedColumn = column;
    });

    _showMessage(
      'Pasted $pastedCells cell(s) into the grid.',
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      appBar: AppBar(
        title:
            const Text('Import from Excel'),
      ),
      body: Column(
        children: [
          _buildImportToolbar(),
          Expanded(
            child: _buildGrid(),
          ),
          _buildBottomBar(),
        ],
      ),
    );
  }

  @override
  void dispose() {
    for (final row in _cellControllers) {
      for (final controller in row) {
        controller.dispose();
      }
    }

    super.dispose();
  }



  Widget _buildImportToolbar() {
    return Padding(
      padding:
          const EdgeInsets.fromLTRB(
        16,
        4,
        16,
        10,
      ),
      child: Row(
        children: [
          SegmentedButton<_ImportType>(
            segments: const [
              ButtonSegment(
                value:
                    _ImportType.teachers,
                label:
                    Text('Teachers'),
                icon: Icon(
                  Icons.school_rounded,
                ),
              ),
              ButtonSegment(
                value:
                    _ImportType.sections,
                label:
                    Text('Sections'),
                icon: Icon(
                  Icons.class_rounded,
                ),
              ),
            ],
            selected: {_type},
            onSelectionChanged:
                (selection) {
              _changeImportType(
                selection.first,
              );
            },
          ),
          const Spacer(),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed:
                _addBlankRow,
            icon: const Icon(
              Icons.add_rounded,
            ),
            label:
                const Text('Add Row'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed:
                _clearRows,
            icon: const Icon(
              Icons.clear_all_rounded,
            ),
            label:
                const Text('Clear'),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid() {
    if (_rows.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize:
              MainAxisSize.min,
          children: [
            Icon(
              Icons.table_view_rounded,
              size: 56,
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant,
            ),
            const SizedBox(
              height: 12,
            ),
            Text(
              _title,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(
                    fontWeight:
                        FontWeight.bold,
                  ),
            ),
            const SizedBox(
              height: 6,
            ),
            const Text(
              'Copy cells from Excel, click a cell, '
              'then press Ctrl+V.',
            ),
          ],
        ),
      );
    }

    if (_cellControllers.length !=
        _rows.length) {
      _rebuildCellControllers();
    }

    return Scrollbar(
      controller:
          _verticalScrollController,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller:
            _verticalScrollController,
        scrollDirection:
            Axis.vertical,
        child: Scrollbar(
          controller:
              _horizontalScrollController,
          thumbVisibility: true,
          notificationPredicate:
              (notification) =>
                  notification.depth == 1,
          child: SingleChildScrollView(
            controller:
                _horizontalScrollController,
            scrollDirection:
                Axis.horizontal,
            child: DataTable(
              border:
                  TableBorder.all(
                color: Theme.of(context)
                    .dividerColor,
              ),
              headingRowHeight: 42,
              dataRowMinHeight: 48,
              dataRowMaxHeight: 70,
              columns: [
                const DataColumn(
                  label: Text(
                    '#',
                    style: TextStyle(
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                ),

                ..._headers.map(
                  (header) =>
                      DataColumn(
                    label: Text(
                      header,
                      style:
                          const TextStyle(
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                const DataColumn(
                  label: Text(''),
                ),
              ],
              rows: List.generate(
                _rows.length,
                (rowIndex) {
                  return DataRow(
                    cells: [
                      DataCell(
                        Text(
                          '${rowIndex + 1}',
                        ),
                      ),

                      ...List.generate(
                        _headers.length,
                        (columnIndex) {
                          final selected =
                              _selectedRow ==
                                  rowIndex &&
                              _selectedColumn ==
                                  columnIndex;

                          return DataCell(
                            SizedBox(
                              width: 180,
                              child: Focus(
                                onKeyEvent:
                                    (
                                  node,
                                  event,
                                ) {
                                  return _handleGridKey(
                                    event,
                                    rowIndex,
                                    columnIndex,
                                  );
                                },
                                child:
                                    TextFormField(
                                  controller:
                                      _cellControllers[
                                              rowIndex]
                                          [
                                          columnIndex],
                                  maxLines: 2,

                                  onTap: () {
                                    _selectCell(
                                      rowIndex,
                                      columnIndex,
                                    );
                                  },

                                  onChanged:
                                      (value) {
                                    _updateCell(
                                      rowIndex,
                                      columnIndex,
                                      value,
                                    );
                                  },

                                  decoration:
                                      InputDecoration(
                                    filled:
                                        selected,
                                    fillColor:
                                        selected
                                            ? Theme.of(
                                                context,
                                              )
                                                .colorScheme
                                                .primaryContainer
                                            : null,
                                    border:
                                        const OutlineInputBorder(),
                                    isDense:
                                        true,
                                    contentPadding:
                                        const EdgeInsets
                                            .symmetric(
                                      horizontal:
                                          8,
                                      vertical:
                                          8,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),

                      DataCell(
                        IconButton(
                          tooltip:
                              'Delete row',
                          onPressed: () {
                            _deleteRow(
                              rowIndex,
                            );
                          },
                          icon:
                              const Icon(
                            Icons
                                .delete_outline_rounded,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding:
          const EdgeInsets.all(12),
      decoration:
          BoxDecoration(
        border: Border(
          top: BorderSide(
            color: Theme.of(context)
                .dividerColor,
          ),
        ),
      ),
      child: Row(
        children: [
          Text(
            '${_rows.length} row(s) ready',
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed:
                _saving
                    ? null
                    : _importRecords,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child:
                        CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(
                    Icons.save_alt_rounded,
                  ),
            label: Text(
              _saving
                  ? 'Importing...'
                  : 'Import Records',
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // MESSAGE
  // ============================================================

  void _showMessage(
    String message,
  ) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

KeyEventResult _handleGridKey(
  KeyEvent event,
  int row,
  int column,
) {
  if (event is KeyDownEvent &&
      event.logicalKey ==
          LogicalKeyboardKey.keyV &&
      HardwareKeyboard.instance
          .isControlPressed) {
    _selectedRow = row;
    _selectedColumn = column;

    _pasteIntoGrid(
      startRow: row,
      startColumn: column,
    );

    return KeyEventResult.handled;
  }

  return KeyEventResult.ignored;
}

}