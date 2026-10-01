import 'package:flutter/material.dart';
import '../database/database_repository.dart';
import '../models/school_year.dart';
import 'school_year_field.dart';

/// Shared by Add Learner and Add/Edit School History. Loading maintenance data
/// never changes a stored history value; only deliberate selections do so.
class SchoolHistoryFields extends StatefulWidget {
  const SchoolHistoryFields(
      {super.key,
      required this.repository,
      required this.year,
      required this.section,
      required this.adviser,
      required this.grade,
      required this.onGradeChanged});
  final DatabaseRepository repository;
  final TextEditingController year, section, adviser;
  final String? grade;
  final ValueChanged<String?> onGradeChanged;

  @override
  State<SchoolHistoryFields> createState() => _SchoolHistoryFieldsState();
}

class _SchoolHistoryFieldsState extends State<SchoolHistoryFields> {
  List<Map<String, Object?>> _sections = [], _teachers = [];
  bool _loading = true;
  String? _error;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final request = ++_request;
    try {
      final sections = await widget.repository.getSections(
          schoolYear: widget.year.text, gradeLevel: widget.grade ?? '');
      final teachers = await widget.repository.getTeachers();
      if (!mounted || request != _request) return;
      setState(() {
        _sections = sections;
        _teachers = teachers;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted && request == _request) {
        setState(() {
          _loading = false;
          _error = 'Unable to load sections/advisers: $e';
        });
      }
    }
  }

  void _cascade() {
    ++_request;
    widget.section.clear();
    widget.adviser.clear();
    setState(() {
      _sections = [];
      _loading = true;
    });
    // The parent supplies the newly selected grade on its next build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Map<String, Object?>? get _selected {
    for (final row in _sections) {
      if (normalizedSchoolName(row['SectionName']) ==
          normalizedSchoolName(widget.section.text)) {
        return row;
      }
    }
    return null;
  }

  Future<void> _quickAdd(bool teacher) async {
    final selected = _selected;
    final result = await showDialog<Map<String, Object?>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _QuickAddDialog(
          repository: widget.repository,
          teacher: teacher,
          year: widget.year.text,
          grade: widget.grade ?? '',
          teachers: _teachers,
          sectionId: teacher ? (selected?['SectionID'] as int?) : null),
    );
    if (result == null || !mounted) return;
    if (teacher) {
      widget.adviser.text = result['TeacherName']!.toString();
    } else {
      widget.section.text = result['SectionName']!.toString();
      widget.adviser.text = result['Adviser']?.toString() ?? '';
    }
    await _load();
  }

  Widget _dropdown(String label, String value, List<String> choices,
      ValueChanged<String?> onChanged) {
    final values = <String>{'', ...choices, if (value.isNotEmpty) value};
    return DropdownButtonFormField<String>(
      key: ValueKey('$label:$value:${choices.join('|')}'),
      initialValue: value,
      isExpanded: true,
      decoration:
          InputDecoration(labelText: label, border: const OutlineInputBorder()),
      items: values
          .map((v) =>
              DropdownMenuItem(value: v, child: Text(v.isEmpty ? 'None' : v)))
          .toList(),
      onChanged: _loading ? null : onChanged,
      validator: label == 'Grade Level *'
          ? (value) => value == null || value.isEmpty ? 'Required' : null
          : null,
    );
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SchoolYearField(controller: widget.year, onChanged: _cascade),
          const SizedBox(height: 12),
          _dropdown('Grade Level *', widget.grade ?? '',
              const ['7', '8', '9', '10', '11', '12', 'SNED'], (value) {
            widget.onGradeChanged(value!.isEmpty ? null : value);
            _cascade();
          }),
          const SizedBox(height: 12),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null) ...[
            Text(_error!),
            TextButton(onPressed: _load, child: const Text('Retry'))
          ],
          _dropdown('Section', widget.section.text,
              _sections.map((r) => r['SectionName'].toString()).toList(),
              (value) {
            setState(() {
              widget.section.text = value ?? '';
              widget.adviser.text = _selected?['Adviser']?.toString() ?? '';
            });
          }),
          if (!_loading && _sections.isEmpty)
            const Text('No sections for this school year and grade.'),
          TextButton.icon(
              onPressed: _loading ||
                      (widget.grade ?? '').isEmpty ||
                      widget.year.text.isEmpty
                  ? null
                  : () => _quickAdd(false),
              icon: const Icon(Icons.add),
              label: const Text('Add New Section')),
          _dropdown('Adviser', widget.adviser.text,
              _teachers.map((r) => r['TeacherName'].toString()).toList(),
              (value) {
            setState(() => widget.adviser.text = value ?? '');
          }),
          TextButton.icon(
              onPressed: _loading ? null : () => _quickAdd(true),
              icon: const Icon(Icons.add),
              label: const Text('Add New Adviser')),
        ],
      );
}

class _QuickAddDialog extends StatefulWidget {
  const _QuickAddDialog(
      {required this.repository,
      required this.teacher,
      required this.year,
      required this.grade,
      required this.teachers,
      this.sectionId});
  final DatabaseRepository repository;
  final bool teacher;
  final String year, grade;
  final List<Map<String, Object?>> teachers;
  final int? sectionId;
  @override
  State<_QuickAddDialog> createState() => _QuickAddDialogState();
}

class _QuickAddDialogState extends State<_QuickAddDialog> {
  final _name = TextEditingController(), _mobile = TextEditingController();
  String _status = 'Active', _adviser = '';
  String? _error;
  bool _saving = false;
  @override
  void dispose() {
    _name.dispose();
    _mobile.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = widget.teacher
          ? 'Teacher name is required.'
          : 'Section name is required.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final Map<String, Object?> result;
      if (widget.teacher) {
        final id = await widget.repository.addTeacher(
            teacherName: _name.text,
            mobileNumber: _mobile.text,
            status: _status);
        result = (await widget.repository.getTeachers())
            .firstWhere((r) => r['TeacherID'] == id);
        if (widget.sectionId != null) {
          await widget.repository.updateSection(widget.sectionId!,
              adviser: result['TeacherName'].toString());
        }
      } else {
        final id = await widget.repository.addSection(
            schoolYear: widget.year,
            gradeLevel: widget.grade,
            sectionName: _name.text,
            adviser: _adviser);
        result = (await widget.repository.getSections())
            .firstWhere((r) => r['SectionID'] == id);
      }
      if (mounted) Navigator.pop(context, result);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Unable to save: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_saving,
        child: AlertDialog(
          title: Text(widget.teacher ? 'Add New Adviser' : 'Add New Section'),
          content: SizedBox(
              width: 430,
              child: SingleChildScrollView(
                  child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!widget.teacher)
                    Text('${widget.year} / Grade ${widget.grade}'),
                  TextField(
                      controller: _name,
                      decoration: InputDecoration(
                          labelText: widget.teacher
                              ? 'Teacher Name'
                              : 'Section Name')),
                  if (widget.teacher) ...[
                    TextField(
                        controller: _mobile,
                        keyboardType: TextInputType.phone,
                        decoration:
                            const InputDecoration(labelText: 'Mobile Number')),
                    DropdownButtonFormField<String>(
                        initialValue: _status,
                        decoration: const InputDecoration(labelText: 'Status'),
                        items: ['Active', 'Inactive']
                            .map((s) =>
                                DropdownMenuItem(value: s, child: Text(s)))
                            .toList(),
                        onChanged: (v) => _status = v!),
                  ] else
                    DropdownButtonFormField<String>(
                        initialValue: '',
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Adviser'),
                        items: <String>{
                          '',
                          ...widget.teachers
                              .map((t) => t['TeacherName'].toString())
                        }
                            .map((s) => DropdownMenuItem(
                                value: s, child: Text(s.isEmpty ? 'None' : s)))
                            .toList(),
                        onChanged: (v) => _adviser = v ?? ''),
                  if (_error != null) Text(_error!),
                ],
              ))),
          actions: [
            TextButton(
                onPressed: _saving ? null : () => Navigator.pop(context),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Saving...' : 'Save')),
          ],
        ),
      );
}
