import 'package:flutter/material.dart';

import '../database/database_repository.dart';
import '../widgets/app_shell.dart';
import '../widgets/sync_status_bar.dart';

class AdminTaskScreen extends StatefulWidget {
  const AdminTaskScreen({super.key});

  @override
  State<AdminTaskScreen> createState() => _AdminTaskScreenState();
}

class _AdminTaskScreenState extends State<AdminTaskScreen> {
  final DatabaseRepository _repository = DatabaseRepository.instance;

  List<Map<String, Object?>> _teachers = [];
  List<Map<String, Object?>> _sections = [];

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // ---------------------------------------------------------------------------
  // DATA
  // ---------------------------------------------------------------------------

  Future<void> _loadData() async {
    if (mounted) {
      setState(() {
        _loading = true;
      });
    }

    try {
      final teachers = await _repository.getTeachers();
      final sections = await _repository.getSections();

      if (!mounted) return;

      setState(() {
        _teachers = teachers;
        _sections = sections;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
      });

      _showError(
        'Unable to load teachers and sections.\n\n'
        '${_friendlyError(e)}',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // TEACHERS
  // ---------------------------------------------------------------------------

  Future<void> _addTeacher() async {
    final result = await _showTeacherDialog();

    if (result == null) return;

    try {
      await _repository.addTeacher(
        teacherName: result.teacherName,
        mobileNumber: result.mobileNumber,
        status: result.status,
      );

      await _loadData();
    } catch (e) {
      if (!mounted) return;

      _showError(
        'Unable to add teacher.\n\n'
        '${_friendlyError(e)}',
      );
    }
  }

  Future<void> _editTeacher(
    Map<String, Object?> teacher,
  ) async {
    final result = await _showTeacherDialog(
      teacher: teacher,
    );

    if (result == null) return;

    final teacherId = _asInt(
      teacher['TeacherID'],
    );

    if (teacherId == null) {
      _showError(
        'The selected teacher does not have a valid TeacherID.',
      );
      return;
    }

    try {
      await _repository.updateTeacher(
        teacherId,
        teacherName: result.teacherName,
        mobileNumber: result.mobileNumber,
        status: result.status,
      );

      await _loadData();
    } catch (e) {
      if (!mounted) return;

      _showError(
        'Unable to update teacher.\n\n'
        '${_friendlyError(e)}',
      );
    }
  }

  Future<void> _deleteTeacher(
    Map<String, Object?> teacher,
  ) async {
    final teacherName =
        (teacher['TeacherName'] ?? '').toString().trim();

    final confirmed = await _showDeleteConfirmation(
      title: 'Delete Teacher',
      message:
          'Delete "$teacherName"?\n\n'
          'This will remove the teacher from the local database. '
          'Existing anecdotal records will not be deleted.',
    );

    if (!confirmed) return;

    final teacherId = _asInt(
      teacher['TeacherID'],
    );

    if (teacherId == null) {
      _showError(
        'The selected teacher does not have a valid TeacherID.',
      );
      return;
    }

    try {
      await _repository.deleteTeacher(
        teacherId,
      );

      await _loadData();
    } catch (e) {
      if (!mounted) return;

      _showError(
        'Unable to delete teacher.\n\n'
        '${_friendlyError(e)}',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // SECTIONS
  // ---------------------------------------------------------------------------

  Future<void> _addSection() async {
    final result = await _showSectionDialog();

    if (result == null) return;

    try {
      await _repository.addSection(
        schoolYear: result.schoolYear,
        gradeLevel: result.gradeLevel,
        sectionName: result.sectionName,
        adviser: result.adviser,
      );

      await _loadData();
    } catch (e) {
      if (!mounted) return;

      _showError(
        'Unable to add section.\n\n'
        '${_friendlyError(e)}',
      );
    }
  }

  Future<void> _editSection(
    Map<String, Object?> section,
  ) async {
    final result = await _showSectionDialog(
      section: section,
    );

    if (result == null) return;

    final sectionId = _asInt(
      section['SectionID'],
    );

    if (sectionId == null) {
      _showError(
        'The selected section does not have a valid SectionID.',
      );
      return;
    }

    try {
      await _repository.updateSection(
        sectionId,
        schoolYear: result.schoolYear,
        gradeLevel: result.gradeLevel,
        sectionName: result.sectionName,
        adviser: result.adviser,
      );

      await _loadData();
    } catch (e) {
      if (!mounted) return;

      _showError(
        'Unable to update section.\n\n'
        '${_friendlyError(e)}',
      );
    }
  }

  Future<void> _deleteSection(
    Map<String, Object?> section,
  ) async {
    final sectionName =
        (section['SectionName'] ?? '').toString().trim();

    final confirmed = await _showDeleteConfirmation(
      title: 'Delete Section',
      message:
          'Delete "$sectionName"?\n\n'
          'This will remove the section from the local database.',
    );

    if (!confirmed) return;

    final sectionId = _asInt(
      section['SectionID'],
    );

    if (sectionId == null) {
      _showError(
        'The selected section does not have a valid SectionID.',
      );
      return;
    }

    try {
      await _repository.deleteSection(
        sectionId,
      );

      await _loadData();
    } catch (e) {
      if (!mounted) return;

      _showError(
        'Unable to delete section.\n\n'
        '${_friendlyError(e)}',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // TEACHER DIALOG
  // ---------------------------------------------------------------------------

  Future<_TeacherFormResult?> _showTeacherDialog({
    Map<String, Object?>? teacher,
  }) async {
    final nameController =
        TextEditingController(
      text:
          teacher?['TeacherName']?.toString() ??
              '',
    );

    final mobileController =
        TextEditingController(
      text:
          teacher?['MobileNumber']?.toString() ??
              '',
    );

    String status =
        teacher?['Status']?.toString().trim().isNotEmpty ==
                true
            ? teacher!['Status'].toString()
            : 'Active';

    try {
      return await showDialog<_TeacherFormResult>(
        context: context,
        builder: (context) {
          return StatefulBuilder(
            builder: (
              context,
              setDialogState,
            ) {
              return AlertDialog(
                title: Text(
                  teacher == null
                      ? 'Add Teacher'
                      : 'Edit Teacher',
                ),
                content: SizedBox(
                  width: 430,
                  child:
                      SingleChildScrollView(
                    child: Column(
                      mainAxisSize:
                          MainAxisSize.min,
                      children: [
                        TextField(
                          controller:
                              nameController,
                          autofocus: true,
                          textCapitalization:
                              TextCapitalization.words,
                          decoration:
                              const InputDecoration(
                            labelText:
                                'Teacher Name',
                            hintText:
                                'e.g. Juan Dela Cruz',
                            prefixIcon:
                                Icon(
                              Icons
                                  .person_outline,
                            ),
                          ),
                        ),
                        const SizedBox(
                          height: 14,
                        ),
                        TextField(
                          controller:
                              mobileController,
                          keyboardType:
                              TextInputType.phone,
                          decoration:
                              const InputDecoration(
                            labelText:
                                'Mobile Number',
                            prefixIcon:
                                Icon(
                              Icons
                                  .phone_outlined,
                            ),
                          ),
                        ),
                        const SizedBox(
                          height: 14,
                        ),
                        DropdownButtonFormField<
                            String>(
                          initialValue:
                              status,
                          decoration:
                              const InputDecoration(
                            labelText:
                                'Status',
                            prefixIcon:
                                Icon(
                              Icons
                                  .toggle_on_outlined,
                            ),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'Active',
                              child:
                                  Text('Active'),
                            ),
                            DropdownMenuItem(
                              value:
                                  'Inactive',
                              child:
                                  Text('Inactive'),
                            ),
                          ],
                          onChanged:
                              (value) {
                            if (value ==
                                null) {
                              return;
                            }

                            setDialogState(
                              () {
                                status =
                                    value;
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () =>
                        Navigator.pop(
                      context,
                    ),
                    child:
                        const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () {
                      final name =
                          nameController
                              .text
                              .trim();

                      if (name.isEmpty) {
                        ScaffoldMessenger
                            .of(context)
                            .showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Teacher name is required.',
                            ),
                          ),
                        );
                        return;
                      }

                      Navigator.pop(
                        context,
                        _TeacherFormResult(
                          teacherName:
                              name,
                          mobileNumber:
                              mobileController
                                  .text
                                  .trim(),
                          status: status,
                        ),
                      );
                    },
                    child:
                        const Text('Save'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      nameController.dispose();
      mobileController.dispose();
    }
  }

  // ---------------------------------------------------------------------------
  // SECTION DIALOG
  // ---------------------------------------------------------------------------

  Future<_SectionFormResult?> _showSectionDialog({
    Map<String, Object?>? section,
  }) async {
    final schoolYearController =
        TextEditingController(
      text:
          section?['SchoolYear']?.toString() ??
              '',
    );

    final sectionNameController =
        TextEditingController(
      text:
          section?['SectionName']?.toString() ??
              '',
    );

    final adviserController =
        TextEditingController(
      text:
          section?['Adviser']?.toString() ??
              '',
    );

    // GradeLevel is TEXT in both DatabaseRepository and AppDatabase.
    String gradeLevel =
        section?['GradeLevel']?.toString().trim().isNotEmpty ==
                true
            ? section!['GradeLevel']
                .toString()
                .trim()
            : '7';

    try {
      return await showDialog<_SectionFormResult>(
        context: context,
        builder: (context) {
          return StatefulBuilder(
            builder: (
              context,
              setDialogState,
            ) {
              return AlertDialog(
                title: Text(
                  section == null
                      ? 'Add Section'
                      : 'Edit Section',
                ),
                content: SizedBox(
                  width: 430,
                  child:
                      SingleChildScrollView(
                    child: Column(
                      mainAxisSize:
                          MainAxisSize.min,
                      children: [
                        TextField(
                          controller:
                              schoolYearController,
                          decoration:
                              const InputDecoration(
                            labelText:
                                'School Year',
                            hintText:
                                'e.g. 2026-2027',
                            prefixIcon:
                                Icon(
                              Icons
                                  .calendar_today_outlined,
                            ),
                          ),
                        ),
                        const SizedBox(
                          height: 14,
                        ),
                        DropdownButtonFormField<
                            String>(
                          initialValue:
                              _validGradeValue(
                            gradeLevel,
                          ),
                          decoration:
                              const InputDecoration(
                            labelText:
                                'Grade Level',
                            prefixIcon:
                                Icon(
                              Icons
                                  .school_outlined,
                            ),
                          ),
                          items: List.generate(
                            6,
                            (index) {
                              final grade =
                                  '${index + 7}';

                              return DropdownMenuItem<
                                  String>(
                                value: grade,
                                child: Text(
                                  'Grade $grade',
                                ),
                              );
                            },
                          ),
                          onChanged:
                              (value) {
                            if (value ==
                                null) {
                              return;
                            }

                            setDialogState(
                              () {
                                gradeLevel =
                                    value;
                              },
                            );
                          },
                        ),
                        const SizedBox(
                          height: 14,
                        ),
                        TextField(
                          controller:
                              sectionNameController,
                          textCapitalization:
                              TextCapitalization.words,
                          decoration:
                              const InputDecoration(
                            labelText:
                                'Section Name',
                            hintText:
                                'e.g. Rizal',
                            prefixIcon:
                                Icon(
                              Icons
                                  .groups_outlined,
                            ),
                          ),
                        ),
                        const SizedBox(
                          height: 14,
                        ),
                        TextField(
                          controller:
                              adviserController,
                          textCapitalization:
                              TextCapitalization.words,
                          decoration:
                              const InputDecoration(
                            labelText:
                                'Adviser',
                            hintText:
                                'Optional',
                            prefixIcon:
                                Icon(
                              Icons
                                  .person_outline,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () =>
                        Navigator.pop(
                      context,
                    ),
                    child:
                        const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () {
                      final schoolYear =
                          schoolYearController
                              .text
                              .trim();

                      final sectionName =
                          sectionNameController
                              .text
                              .trim();

                      if (schoolYear.isEmpty) {
                        ScaffoldMessenger
                            .of(context)
                            .showSnackBar(
                          const SnackBar(
                            content: Text(
                              'School Year is required.',
                            ),
                          ),
                        );
                        return;
                      }

                      if (sectionName.isEmpty) {
                        ScaffoldMessenger
                            .of(context)
                            .showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Section name is required.',
                            ),
                          ),
                        );
                        return;
                      }

                      Navigator.pop(
                        context,
                        _SectionFormResult(
                          schoolYear:
                              schoolYear,
                          gradeLevel:
                              gradeLevel,
                          sectionName:
                              sectionName,
                          adviser:
                              adviserController
                                  .text
                                  .trim(),
                        ),
                      );
                    },
                    child:
                        const Text('Save'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      schoolYearController.dispose();
      sectionNameController.dispose();
      adviserController.dispose();
    }
  }

  String _validGradeValue(
    String value,
  ) {
    const validGrades = [
      '7',
      '8',
      '9',
      '10',
      '11',
      '12',
    ];

    return validGrades.contains(value)
        ? value
        : '7';
  }

  // ---------------------------------------------------------------------------
  // CONFIRMATION / MESSAGE DIALOGS
  // ---------------------------------------------------------------------------

  Future<bool> _showConfirmation({
    required String title,
    required String message,
    required String confirmText,
    IconData? icon,
  }) async {
    final result =
        await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Row(
            children: [
              if (icon != null) ...[
                Icon(icon),
                const SizedBox(
                  width: 10,
                ),
              ],
              Expanded(
                child: Text(title),
              ),
            ],
          ),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(
                context,
                false,
              ),
              child:
                  const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(
                context,
                true,
              ),
              child:
                  Text(confirmText),
            ),
          ],
        );
      },
    );

    return result ?? false;
  }

  Future<bool> _showDeleteConfirmation({
    required String title,
    required String message,
  }) {
    return _showConfirmation(
      title: title,
      message: message,
      confirmText: 'Delete',
      icon:
          Icons.delete_outline_rounded,
    );
  }

  void _showError(
    String message,
  ) {
    if (!mounted) return;

    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(
                Icons.error_outline_rounded,
              ),
              SizedBox(
                width: 10,
              ),
              Text('Operation Failed'),
            ],
          ),
          content:
              SelectableText(message),
          actions: [
            FilledButton(
              onPressed: () =>
                  Navigator.pop(
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

  String _friendlyError(
    Object error,
  ) {
    final text = error.toString();

    if (text.startsWith(
      'Exception: ',
    )) {
      return text.substring(
        'Exception: '.length,
      );
    }

    if (text.startsWith(
      'Bad state: ',
    )) {
      return text.substring(
        'Bad state: '.length,
      );
    }

    return text;
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(
    BuildContext context,
  ) {
    return AppShell(
      title: 'Teachers / Sections',
      child: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(
                    child:
                        CircularProgressIndicator(),
                  )
                : RefreshIndicator(
                    onRefresh: _loadData,
                    child: ListView(
                      physics:
                          const AlwaysScrollableScrollPhysics(),
                      padding:
                          const EdgeInsets.fromLTRB(
                        20,
                        20,
                        20,
                        24,
                      ),
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _buildTeachersCard(),
                            ),
                            const SizedBox(width: 20),
                            Expanded(
                              child: _buildSectionsCard(),
                            ),
                          ],
                        ),
                        const SizedBox(
                          height: 20,
                        ),
                        _buildBulkImportCard(),
                      ],
                    ),
                  ),
          ),
          const SyncStatusBar(),
        ],
      ),
    );
  }

  Widget _buildBulkImportCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            const Icon(
              Icons.table_view_rounded,
              size: 28,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'BULK IMPORT',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Paste multiple teacher and section records from a '
                    'spreadsheet. Section records include adviser assignments.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            FilledButton.icon(
              onPressed: _openBulkImport,
              icon: const Icon(
                Icons.upload_file_rounded,
              ),
              label: const Text(
                'Bulk Import',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openBulkImport() async {
    await Navigator.pushNamed(
      context,
      '/admin-import',
    );

    if (!mounted) return;
    await _loadData();
  }

  Widget _buildTeachersCard() {
    return Card(
      child: Padding(
        padding:
            const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.people_alt_outlined,
                ),
                const SizedBox(
                  width: 10,
                ),
                const Expanded(
                  child: Text(
                    'TEACHERS',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _addTeacher,
                  icon: const Icon(
                    Icons.add,
                    size: 18,
                  ),
                  label:
                      const Text(
                    'Add Teacher',
                  ),
                ),
              ],
            ),
            const SizedBox(
              height: 14,
            ),
            if (_teachers.isEmpty)
              _buildEmptyMessage(
                'No teachers have been added yet.',
              )
            else
              ..._teachers.map(
                _buildTeacherTile,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTeacherTile(
    Map<String, Object?> teacher,
  ) {
    final name =
        (teacher['TeacherName'] ?? '')
            .toString()
            .trim();

    final mobile =
        (teacher['MobileNumber'] ?? '')
            .toString()
            .trim();

    final status =
        (teacher['Status'] ?? 'Active')
            .toString()
            .trim();

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        child: Text(
          name.isEmpty
              ? '?'
              : name
                  .substring(0, 1)
                  .toUpperCase(),
        ),
      ),
      title: Text(
        name.isEmpty
            ? 'Unnamed Teacher'
            : name,
      ),
      subtitle: Text(
        [
          if (mobile.isNotEmpty) mobile,
          status,
        ].join(' • '),
      ),
      trailing:
          PopupMenuButton<String>(
        onSelected: (value) {
          switch (value) {
            case 'edit':
              _editTeacher(teacher);
              break;

            case 'delete':
              _deleteTeacher(teacher);
              break;
          }
        },
        itemBuilder: (context) =>
            const [
          PopupMenuItem(
            value: 'edit',
            child: ListTile(
              leading: Icon(
                Icons.edit_outlined,
              ),
              title: Text('Edit'),
              contentPadding:
                  EdgeInsets.zero,
            ),
          ),
          PopupMenuItem(
            value: 'delete',
            child: ListTile(
              leading: Icon(
                Icons.delete_outline,
              ),
              title: Text('Delete'),
              contentPadding:
                  EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionsCard() {
    return Card(
      child: Padding(
        padding:
            const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.class_outlined,
                ),
                const SizedBox(
                  width: 10,
                ),
                const Expanded(
                  child: Text(
                    'SECTIONS',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _addSection,
                  icon: const Icon(
                    Icons.add,
                    size: 18,
                  ),
                  label:
                      const Text(
                    'Add Section',
                  ),
                ),
              ],
            ),
            const SizedBox(
              height: 14,
            ),
            if (_sections.isEmpty)
              _buildEmptyMessage(
                'No sections have been added yet.',
              )
            else
              ..._sections.map(
                _buildSectionTile,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTile(
    Map<String, Object?> section,
  ) {
    final schoolYear =
        (section['SchoolYear'] ?? '')
            .toString()
            .trim();

    final grade =
        (section['GradeLevel'] ?? '')
            .toString()
            .trim();

    final sectionName =
        (section['SectionName'] ?? '')
            .toString()
            .trim();

    final adviser =
        (section['Adviser'] ?? '')
            .toString()
            .trim();

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        child: Text(
          grade.isEmpty ? '?' : grade,
          style: const TextStyle(
            fontSize: 13,
            fontWeight:
                FontWeight.bold,
          ),
        ),
      ),
      title: Text(
        sectionName.isEmpty
            ? 'Unnamed Section'
            : sectionName,
      ),
      subtitle: Text(
        [
          if (grade.isNotEmpty)
            'Grade $grade',
          if (schoolYear.isNotEmpty)
            schoolYear,
          if (adviser.isNotEmpty)
            'Adviser: $adviser',
        ].join(' • '),
      ),
      trailing:
          PopupMenuButton<String>(
        onSelected: (value) {
          switch (value) {
            case 'edit':
              _editSection(section);
              break;

            case 'delete':
              _deleteSection(section);
              break;
          }
        },
        itemBuilder: (context) =>
            const [
          PopupMenuItem(
            value: 'edit',
            child: ListTile(
              leading: Icon(
                Icons.edit_outlined,
              ),
              title: Text('Edit'),
              contentPadding:
                  EdgeInsets.zero,
            ),
          ),
          PopupMenuItem(
            value: 'delete',
            child: ListTile(
              leading: Icon(
                Icons.delete_outline,
              ),
              title: Text('Delete'),
              contentPadding:
                  EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyMessage(
    String message,
  ) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(
        vertical: 18,
      ),
      child: Center(
        child: Text(
          message,
          textAlign:
              TextAlign.center,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // HELPERS
  // ---------------------------------------------------------------------------

  int? _asInt(
    Object? value,
  ) {
    if (value == null) {
      return null;
    }

    if (value is int) {
      return value;
    }

    return int.tryParse(
      value.toString(),
    );
  }
}

// =============================================================================
// FORM RESULT CLASSES
// =============================================================================

class _TeacherFormResult {
  final String teacherName;
  final String mobileNumber;
  final String status;

  const _TeacherFormResult({
    required this.teacherName,
    required this.mobileNumber,
    required this.status,
  });
}

class _SectionFormResult {
  final String schoolYear;
  final String gradeLevel;
  final String sectionName;
  final String adviser;

  const _SectionFormResult({
    required this.schoolYear,
    required this.gradeLevel,
    required this.sectionName,
    required this.adviser,
  });
}