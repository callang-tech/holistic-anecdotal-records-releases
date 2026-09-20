import 'package:flutter/material.dart';

import '../database/database_repository.dart';
import '../services/school_settings_service.dart';
import '../widgets/sync_status_bar.dart';

import '../models/location_selection.dart';
import '../widgets/location_selector.dart';


class AddLearnerScreen extends StatefulWidget {
  const AddLearnerScreen({super.key});

  @override
  State<AddLearnerScreen> createState() =>
      _AddLearnerScreenState();
}

class _AddLearnerScreenState
    extends State<AddLearnerScreen> {
  final DatabaseRepository _repository =
      DatabaseRepository.instance;

  final _formKey = GlobalKey<FormState>();

  LocationSelection _location =
      const LocationSelection();




  // ============================================================
  // LEARNER CONTROLLERS
  // ============================================================

  final _lrnController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _middleNameController = TextEditingController();

  final _birthDateController =
      TextEditingController();

  final _ageController = TextEditingController();

  final _contactController =
      TextEditingController();

  final _purokController =
      TextEditingController();

  final _streetController =
      TextEditingController();

  final _houseNoController =
      TextEditingController();

  final _parentsController =
      TextEditingController();

  final _guardianController =
      TextEditingController();

  final _relationshipController =
      TextEditingController();

  final _parentContactController =
      TextEditingController();

  final _notesController =
      TextEditingController();

  // ============================================================
  // BASIC STATE
  // ============================================================

  String? _sex;

  bool _saving = false;

  // ============================================================
  // SCHOOL HISTORY
  // ============================================================

  final List<_SchoolHistoryEntry> _schoolHistory =
      [];

  @override
  void initState() {
    super.initState();

    _birthDateController.addListener(
      _birthDateChanged,
    );

    _addSchoolHistoryEntry();
  }

  @override
  void dispose() {
    _lrnController.dispose();
    _lastNameController.dispose();
    _firstNameController.dispose();
    _middleNameController.dispose();
    _birthDateController.dispose();
    _ageController.dispose();
    _contactController.dispose();
    _purokController.dispose();
    _streetController.dispose();
    _houseNoController.dispose();
    _parentsController.dispose();
    _guardianController.dispose();
    _relationshipController.dispose();
    _parentContactController.dispose();
    _notesController.dispose();

    for (final entry in _schoolHistory) {
      entry.dispose();
    }

    super.dispose();
  }

  // ============================================================
  // DATE / AGE
  // ============================================================

  void _birthDateChanged() {
    final text = _birthDateController.text.trim();

    if (text.isEmpty) {
      _ageController.clear();
      if (mounted) setState(() {});
      return;
    }

    final date = _parseDate(text);

    if (date != null) {
      final age = _calculateAge(date);
      if (_ageController.text != age.toString()) {
        _ageController.text = age.toString();
      }
    } else {
      _ageController.clear();
    }

    if (mounted) setState(() {});
  }

  DateTime? _parseDate(String input) {
    var text = input.trim();
    if (text.isEmpty) return null;

    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();

    const months = <String, int>{
      'january': 1, 'jan': 1,
      'february': 2, 'feb': 2,
      'march': 3, 'mar': 3,
      'april': 4, 'apr': 4,
      'may': 5,
      'june': 6, 'jun': 6,
      'july': 7, 'jul': 7,
      'august': 8, 'aug': 8,
      'september': 9, 'sep': 9, 'sept': 9,
      'october': 10, 'oct': 10,
      'november': 11, 'nov': 11,
      'december': 12, 'dec': 12,
    };

    // Month name first: August 23, 2010 / Aug. 23 2010
    final monthFirst = RegExp(
      r'^([A-Za-z]+)\.?\s+(\d{1,2}),?\s+(\d{4})$',
    ).firstMatch(text);

    if (monthFirst != null) {
      final month = months[monthFirst.group(1)!.toLowerCase()];
      if (month != null) {
        return _validDate(
          int.parse(monthFirst.group(3)!),
          month,
          int.parse(monthFirst.group(2)!),
        );
      }
    }

    // Day first with month name: 23 August 2010 / 23 Aug, 2010
    final dayFirstName = RegExp(
      r'^(\d{1,2})\s+([A-Za-z]+)\.?[,]?\s+(\d{4})$',
    ).firstMatch(text);

    if (dayFirstName != null) {
      final month = months[dayFirstName.group(2)!.toLowerCase()];
      if (month != null) {
        return _validDate(
          int.parse(dayFirstName.group(3)!),
          month,
          int.parse(dayFirstName.group(1)!),
        );
      }
    }

    // yyyy-MM-dd / yyyy/MM/dd
    final yearFirst = RegExp(
      r'^(\d{4})[-/](\d{1,2})[-/](\d{1,2})$',
    ).firstMatch(text);

    if (yearFirst != null) {
      return _validDate(
        int.parse(yearFirst.group(1)!),
        int.parse(yearFirst.group(2)!),
        int.parse(yearFirst.group(3)!),
      );
    }

    // Numeric dates. MM/DD/YYYY is the default.
    // If the first number is > 12, treat it as DD/MM/YYYY.
    final numeric = RegExp(
      r'^(\d{1,2})[/\-](\d{1,2})[/\-](\d{4})$',
    ).firstMatch(text);

    if (numeric != null) {
      final first = int.parse(numeric.group(1)!);
      final second = int.parse(numeric.group(2)!);
      final year = int.parse(numeric.group(3)!);

      if (first > 12) {
        return _validDate(year, second, first);
      }

      return _validDate(year, first, second);
    }

    return DateTime.tryParse(text);
  }

  DateTime? _validDate(int year, int month, int day) {
    try {
      final date = DateTime(year, month, day);
      if (date.year != year ||
          date.month != month ||
          date.day != day) {
        return null;
      }
      return date;
    } catch (_) {
      return null;
    }
  }

  int _calculateAge(DateTime birthDate) {
    final today = DateTime.now();
    var age = today.year - birthDate.year;

    if (today.month < birthDate.month ||
        (today.month == birthDate.month &&
            today.day < birthDate.day)) {
      age--;
    }

    return age;
  }

  String _formatDate(DateTime date) {
    const months = [
      'January', 'February', 'March', 'April',
      'May', 'June', 'July', 'August',
      'September', 'October', 'November', 'December',
    ];

    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  Future<void> _selectBirthDate() async {
    final initialDate =
        _parseDate(_birthDateController.text) ??
            DateTime(
              DateTime.now().year - 12,
              DateTime.now().month,
              DateTime.now().day,
            );

    final selected = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );

    if (selected == null) {
      return;
    }

    _birthDateController.text =
        _formatDate(selected);

    _ageController.text =
        _calculateAge(selected).toString();

    setState(() {});
  }

  // ============================================================
  // SCHOOL HISTORY
  // ============================================================

  Future<void> _addSchoolHistoryEntry() async {
    final schoolName =
        await SchoolSettingsService.instance.getSchoolName();

    if (!mounted) return;

    final entry = _SchoolHistoryEntry(
      repository: _repository,
      schoolYear: _currentSchoolYear(),
      defaultSchoolName: schoolName,
    );

    setState(() {
      _schoolHistory.add(entry);
    });

    // The entry loads Sections/Teachers asynchronously. Rebuild after the
    // initial load so the first School History card already shows the
    // appropriate Section choices and adviser data.
    entry.loadInitialData().then((_) {
      if (mounted && _schoolHistory.contains(entry)) {
        setState(() {});
      }
    });
  }

  String _currentSchoolYear() {
    final now = DateTime.now();
    final startYear = now.month >= 6
        ? now.year
        : now.year - 1;
    return '$startYear-${startYear + 1}';
  }

  List<String> _schoolYearOptions() {
    final now = DateTime.now();
    final currentStartYear = now.month >= 6
        ? now.year
        : now.year - 1;

    // Current school year plus the six previous school years.
    return List<String>.generate(7, (index) {
      final startYear = currentStartYear - index;
      return '$startYear-${startYear + 1}';
    });
  }

  void _removeSchoolHistoryEntry(
    int index,
  ) {
    if (_schoolHistory.length == 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'At least one school history record is required.',
          ),
        ),
      );

      return;
    }

    final entry = _schoolHistory.removeAt(index);

    entry.dispose();

    setState(() {});
  }

 
  // ============================================================
  // TEXT CAPITALIZATION
  // ============================================================

  String _titleCase(String value) {
    return value
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .map((word) {
          if (word.length == 1) {
            return word.toUpperCase();
          }

          return '${word[0].toUpperCase()}'
              '${word.substring(1).toLowerCase()}';
        })
        .join(' ');
  }

  String? _optionalTitleCase(String value) {
    final text = value.trim();

    if (text.isEmpty) {
      return null;
    }

    return _titleCase(text);
  }

  // ============================================================
  // SAVE
  // ============================================================

  Future<void> _save() async {
    if (_saving) {
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    // ----------------------------------------------------------
    // Validate birth date
    // ----------------------------------------------------------

    final birthText =
        _birthDateController.text.trim();

    DateTime? birthDate;

    if (birthText.isNotEmpty) {
      birthDate = _parseDate(birthText);

      if (birthDate != null) {
        _birthDateController.text = _formatDate(birthDate);
      }

      if (birthDate == null) {
        _showError(
          'Please enter a valid birth date.',
        );

        return;
      }
    }

    // ----------------------------------------------------------
    // Determine age
    // ----------------------------------------------------------

    int? age;

    // Age is derived exclusively from Birth Date.
    if (birthDate != null) {
      age = _calculateAge(birthDate);
    }

    // ----------------------------------------------------------
    // Validate school history
    // ----------------------------------------------------------

    final history = <Map<String, Object?>>[];

    for (var i = 0;
        i < _schoolHistory.length;
        i++) {
      final entry = _schoolHistory[i];

      final schoolYear =
          entry.schoolYearController.text.trim();

      final school =
          entry.schoolController.text.trim();

      final section =
          entry.sectionController.text.trim();

      final adviser =
          entry.adviserController.text.trim();

      final grade = entry.grade;

      if (schoolYear.isEmpty) {
        _showError(
          'School Year is required for School History #${i + 1}.',
        );

        return;
      }

      if (grade == null) {
        _showError(
          'Grade Level is required for School History #${i + 1}.',
        );

        return;
      }

      if (school.isEmpty) {
        _showError(
          'School is required for School History #${i + 1}.',
        );
        return;
      }

      // Add a newly typed adviser to Teachers first, when requested.
      if (adviser.isNotEmpty &&
          entry.addTeacherToTable &&
          entry.findMatchingTeacher(adviser) == null) {
        try {
          await _repository.addTeacher(
            teacherName: _titleCase(adviser),
            mobileNumber: '',
            status: 'Active',
          );
          await entry.loadTeachers();
        } catch (e) {
          _showError('Unable to add adviser to Teachers table.\n$e');
          return;
        }
      }

      // Add a newly typed section for this exact school year + grade, when requested.
      if (section.isNotEmpty &&
          entry.addSectionToTable &&
          entry.findMatchingSection() == null) {
        try {
          await _repository.addSection(
            schoolYear: schoolYear,
            gradeLevel: grade,
            sectionName: _titleCase(section),
            adviser: adviser,
          );
          await entry.loadSections();
        } catch (e) {
          _showError('Unable to add section to Sections table.\n$e');
          return;
        }
      }

      history.add({
        'SchoolYear': schoolYear,
        'Grade': grade,
        'School': school,
        'Section':
            section.isEmpty ? null : _titleCase(section),
        'Adviser':
            adviser.isEmpty ? null : _titleCase(adviser),
        'Notes':
            entry.notesController.text.trim(),
      });
    }

    // ----------------------------------------------------------
    // Save
    // ----------------------------------------------------------

    setState(() {
      _saving = true;
    });

    try {
      final learnerId =
          await _repository.addLearnerWithSchoolHistory(
        lastName:
            _titleCase(_lastNameController.text),
        firstName:
            _titleCase(_firstNameController.text),
        middleName:
            _optionalTitleCase(_middleNameController.text) ?? '',
        lrn: _lrnController.text.trim(),
        sex: _sex!,
        birthDate: birthDate == null
            ? null
            : _formatDate(birthDate),
        age: age,
        contact:
            _contactController.text.trim(),
        
        
        regionCode:
            _location.regionCode,
        region:
            _location.regionName,

        provinceCode:
            _location.provinceCode,
        province:
            _location.provinceName,

        municipalityCode:
            _location.cityMunicipalityCode,
        municipality:
            _location.cityMunicipalityName,

        barangayCode:
            _location.barangayCode,
        barangay:
            _location.barangayName,
        
        
        purok:
            _purokController.text.trim(),
        street:
            _streetController.text.trim(),
        houseNo:
            _houseNoController.text.trim(),
        parents:
            _optionalTitleCase(_parentsController.text) ?? '',
        guardian:
            _optionalTitleCase(_guardianController.text) ?? '',
        relationship:
            _optionalTitleCase(_relationshipController.text) ?? '',
        parentContact:
            _parentContactController.text.trim(),
        notes:
            _notesController.text.trim(),
        schoolHistory: history,
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Learner saved successfully. '
            'Learner ID: $learnerId',
          ),
        ),
      );

      Navigator.pop(context, learnerId);
    } catch (e) {
      if (!mounted) {
        return;
      }

      _showError(
        'Unable to save learner.\n\n$e',
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add New Learner'),
      ),
      body: Column(
        children: [
          Expanded(
            child: Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: ConstrainedBox(
                    constraints:
                        const BoxConstraints(
                      maxWidth: 1200,
                    ),
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.stretch,
                      children: [
                        _buildLearnerInformation(),
                        const SizedBox(height: 24),
                        _buildSchoolHistory(),
                        const SizedBox(height: 32),
                        _buildActionButtons(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SyncStatusBar(),
        ],
      ),
    );
  }

  // ============================================================
  // LEARNER INFORMATION
  // ============================================================

  Widget _buildLearnerInformation() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            const Text(
              'Learner Information',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 20),

            _buildThreeColumns([
              TextFormField(
                controller: _lrnController,
                decoration:
                    const InputDecoration(
                  labelText: 'LRN',
                  border: OutlineInputBorder(),
                ),
              ),

              TextFormField(
                controller:
                    _lastNameController,
                decoration:
                    const InputDecoration(
                  labelText: 'Last Name *',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null ||
                      value.trim().isEmpty) {
                    return 'Required';
                  }

                  return null;
                },
              ),

              TextFormField(
                controller:
                    _firstNameController,
                decoration:
                    const InputDecoration(
                  labelText: 'First Name *',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null ||
                      value.trim().isEmpty) {
                    return 'Required';
                  }

                  return null;
                },
              ),
            ]),

            const SizedBox(height: 16),

            _buildThreeColumns([
              TextFormField(
                controller:
                    _middleNameController,
                decoration:
                    const InputDecoration(
                  labelText: 'Middle Name',
                  border: OutlineInputBorder(),
                ),
              ),

              DropdownButtonFormField<String>(
                initialValue: _sex,
                decoration:
                    const InputDecoration(
                  labelText: 'Sex *',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'Male',
                    child: Text('Male'),
                  ),
                  DropdownMenuItem(
                    value: 'Female',
                    child: Text('Female'),
                  ),
                ],
                onChanged: (value) {
                  setState(() {
                    _sex = value;
                  });
                },
                validator: (value) {
                  if (value == null) {
                    return 'Required';
                  }

                  return null;
                },
              ),

              TextFormField(
                controller:
                    _contactController,
                keyboardType:
                    TextInputType.phone,
                decoration:
                    const InputDecoration(
                  labelText:
                      'Learner Contact Number',
                  border: OutlineInputBorder(),
                ),
              ),
            ]),

            const SizedBox(height: 16),

            _buildThreeColumns([
              TextFormField(
                controller:
                    _birthDateController,
                decoration:
                    InputDecoration(
                  labelText: 'Birth Date',
                  hintText:
                      'August 22, 2012',
                  border:
                      const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip:
                        'Select birth date',
                    onPressed:
                        _selectBirthDate,
                    icon: const Icon(
                      Icons.calendar_month,
                    ),
                  ),
                ),
              ),

              TextFormField(
                controller: _ageController,
                readOnly: _birthDateController.text.trim().isNotEmpty,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Age',
                  border: const OutlineInputBorder(),
                  helperText: _birthDateController.text.trim().isNotEmpty
                      ? 'Automatically calculated from birth date'
                      : 'Enter age if birth date is not provided',
                ),
              ),

              const SizedBox(),
            ]),

            const SizedBox(height: 24),

            const Text(
              'Address',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 12),

            
          LocationSelector(
            onChanged: (selection) {
              setState(() {
                _location = selection;
              });
            },
          ),


            const SizedBox(height: 16),

            _buildThreeColumns([
              TextFormField(
                controller:
                    _purokController,
                decoration:
                    const InputDecoration(
                  labelText: 'Purok',
                  border: OutlineInputBorder(),
                ),
              ),

              TextFormField(
                controller:
                    _streetController,
                decoration:
                    const InputDecoration(
                  labelText: 'Street',
                  border: OutlineInputBorder(),
                ),
              ),
            ]),

            const SizedBox(height: 16),

            _buildThreeColumns([
              TextFormField(
                controller:
                    _houseNoController,
                decoration:
                    const InputDecoration(
                  labelText: 'House No.',
                  border: OutlineInputBorder(),
                ),
              ),

              TextFormField(
                controller:
                    _parentsController,
                decoration:
                    const InputDecoration(
                  labelText:
                      'Parents',
                  border: OutlineInputBorder(),
                ),
              ),

              TextFormField(
                controller:
                    _guardianController,
                decoration:
                    const InputDecoration(
                  labelText:
                      'Guardian',
                  border: OutlineInputBorder(),
                ),
              ),
            ]),

            const SizedBox(height: 16),

            _buildThreeColumns([
              TextFormField(
                controller:
                    _relationshipController,
                decoration:
                    const InputDecoration(
                  labelText:
                      'Relationship to Guardian',
                  border: OutlineInputBorder(),
                ),
              ),

              TextFormField(
                controller:
                    _parentContactController,
                keyboardType:
                    TextInputType.phone,
                decoration:
                    const InputDecoration(
                  labelText:
                      'Parents/Guardian Contact',
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(),
            ]),

            const SizedBox(height: 16),

            TextFormField(
              controller: _notesController,
              minLines: 3,
              maxLines: 6,
              decoration:
                  const InputDecoration(
                labelText:
                    'Additional Notes / Details',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // SCHOOL HISTORY
  // ============================================================

  Widget _buildSchoolHistory() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        'School History',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Add the learner\'s school history records.',
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed:
                      _addSchoolHistoryEntry,
                  icon: const Icon(Icons.add),
                  label: const Text(
                    'Add School History',
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            ...List.generate(
              _schoolHistory.length,
              (index) {
                return Padding(
                  padding:
                      const EdgeInsets.only(
                    bottom: 16,
                  ),
                  child:
                      _buildSchoolHistoryCard(
                    index,
                    _schoolHistory[index],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSchoolHistoryCard(
  int index,
  _SchoolHistoryEntry entry,
) {
  return Card(
    elevation: 0,
    color: Theme.of(context)
        .colorScheme
        .surfaceContainerHighest,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                child: Text('${index + 1}'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'School History #${index + 1}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Remove this history',
                onPressed: () =>
                    _removeSchoolHistoryEntry(index),
                icon: const Icon(
                  Icons.delete_outline,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ------------------------------------------------------
          // SCHOOL YEAR / GRADE / SCHOOL
          // ------------------------------------------------------

          _buildThreeColumns([
            DropdownMenu<String>(
              controller: entry.schoolYearController,
              initialSelection: _schoolYearOptions().contains(
                entry.schoolYearController.text.trim(),
              )
                  ? entry.schoolYearController.text.trim()
                  : null,
              dropdownMenuEntries: _schoolYearOptions()
                  .map(
                    (year) => DropdownMenuEntry<String>(
                      value: year,
                      label: year,
                    ),
                  )
                  .toList(),
              enableFilter: true,
              enableSearch: true,
              label: const Text('School Year *'),
              hintText: 'Select or type School Year',
              onSelected: (value) async {
                if (value == null) return;

                entry.sectionController.clear();
                entry.adviserController.clear();
                await entry.loadSections();

                if (mounted) {
                  setState(() {});
                }
              },
            ),

            DropdownButtonFormField<String>(
              key: ValueKey<String?>(entry.grade),
              initialValue: entry.grade,
              decoration: const InputDecoration(
                labelText: 'Grade Level *',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: '7',
                  child: Text('Grade 7'),
                ),
                DropdownMenuItem(
                  value: '8',
                  child: Text('Grade 8'),
                ),
                DropdownMenuItem(
                  value: '9',
                  child: Text('Grade 9'),
                ),
                DropdownMenuItem(
                  value: '10',
                  child: Text('Grade 10'),
                ),
                DropdownMenuItem(
                  value: '11',
                  child: Text('Grade 11'),
                ),
                DropdownMenuItem(
                  value: '12',
                  child: Text('Grade 12'),
                ),
                DropdownMenuItem(
                  value: 'SNED',
                  child: Text('SNED'),
                ),
              ],
              onChanged: (value) async {
                entry.grade = value;

                entry.sectionController.clear();
                entry.adviserController.clear();
                entry.addSectionToTable = false;
                entry.addTeacherToTable = false;

                await entry.loadSections();

                if (mounted) {
                  setState(() {});
                }
              },
              validator: (value) {
                if (value == null ||
                    value.trim().isEmpty) {
                  return 'Required';
                }

                return null;
              },
            ),

            TextFormField(
              controller:
                  entry.schoolController,
              decoration: const InputDecoration(
                labelText: 'School *',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null ||
                    value.trim().isEmpty) {
                  return 'Required';
                }

                return null;
              },
            ),
          ]),

          const SizedBox(height: 16),

          // ------------------------------------------------------
          // SECTION / ADVISER / NOTES
          // ------------------------------------------------------

          _buildThreeColumns([
            _buildSectionField(entry),
            _buildAdviserField(entry),
            TextFormField(
              controller:
                  entry.notesController,
              decoration: const InputDecoration(
                labelText: 'Notes / Details',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ]),
        ],
      ),
    ),
  );
}

  Widget _buildSectionField(
    _SchoolHistoryEntry entry,
  ) {
    final sectionNames = entry.sections
        .map((row) => row['SectionName']?.toString().trim() ?? '')
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final sectionExists = entry.findMatchingSection() != null;
    final typedSection = entry.sectionController.text.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Autocomplete<String>(
          initialValue: TextEditingValue(
            text: entry.sectionController.text,
          ),
          optionsBuilder: (value) {
            final query = value.text.trim().toLowerCase();
            if (query.isEmpty) return sectionNames;
            return sectionNames.where(
              (name) => name.toLowerCase().contains(query),
            );
          },
          onSelected: (value) {
            entry.sectionController.text = value;
            final match = entry.findMatchingSection();
            final adviser = match?['Adviser']?.toString().trim() ?? '';
            entry.adviserController.text = adviser;
            entry.addSectionToTable = false;
            setState(() {});
          },
          fieldViewBuilder: (
            context,
            textController,
            focusNode,
            onFieldSubmitted,
          ) {
            return TextFormField(
              controller: textController,
              focusNode: focusNode,
              decoration: InputDecoration(
                labelText: 'Section',
                hintText: sectionNames.isEmpty
                    ? 'Type a section'
                    : 'Select or type section',
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) {
                entry.sectionController.text = value;
                setState(() {});
              },
              onFieldSubmitted: (_) => onFieldSubmitted(),
            );
          },
        ),
        if (typedSection.isNotEmpty && !sectionExists)
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: entry.addSectionToTable,
            onChanged: (value) {
              setState(() {
                entry.addSectionToTable = value ?? false;
              });
            },
            title: Text(
              'Add "$typedSection" to Sections for ${entry.schoolYearController.text.trim()} / Grade ${entry.grade ?? ''}',
            ),
            subtitle: const Text(
              'This section will be available for this school year and grade level.',
            ),
          ),
      ],
    );
  }

  Widget _buildAdviserField(
    _SchoolHistoryEntry entry,
  ) {
    final teacherNames = entry.teachers
        .map((row) => row['TeacherName']?.toString().trim() ?? '')
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final typedAdviser = entry.adviserController.text.trim();
    final teacherExists = entry.findMatchingTeacher(typedAdviser) != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Autocomplete<String>(
          // Recreate the Autocomplete when the section supplies a new
          // adviser. Autocomplete owns the TextEditingController supplied
          // to fieldViewBuilder, so changing entry.adviserController alone
          // does not update the visible field.
          key: ValueKey<String>(
            entry.adviserController.text,
          ),
          initialValue: TextEditingValue(
            text: entry.adviserController.text,
          ),
          optionsBuilder: (value) {
            final query = value.text.trim().toLowerCase();
            if (query.isEmpty) return teacherNames;
            return teacherNames.where(
              (name) => name.toLowerCase().contains(query),
            );
          },
          onSelected: (value) {
            entry.adviserController.text = value;
            entry.addTeacherToTable = false;
            setState(() {});
          },
          fieldViewBuilder: (
            context,
            textController,
            focusNode,
            onFieldSubmitted,
          ) {
            return TextFormField(
              controller: textController,
              focusNode: focusNode,
              decoration: InputDecoration(
                labelText: 'Adviser',
                hintText: teacherNames.isEmpty
                    ? 'Type an adviser'
                    : 'Select or type adviser',
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) {
                entry.adviserController.text = value;
                setState(() {});
              },
              onFieldSubmitted: (_) => onFieldSubmitted(),
            );
          },
        ),
        if (typedAdviser.isNotEmpty && !teacherExists)
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: entry.addTeacherToTable,
            onChanged: (value) {
              setState(() {
                entry.addTeacherToTable = value ?? false;
              });
            },
            title: Text('Add "$typedAdviser" to Teachers'),
            subtitle: const Text(
              'The teacher will be added as an Active teacher. The section assignment remains school-year specific.',
            ),
          ),
      ],
    );
  }

  // ============================================================
  // BUTTONS
  // ============================================================

  Widget _buildActionButtons() {
    return Row(
      mainAxisAlignment:
          MainAxisAlignment.end,
      children: [
        OutlinedButton(
          onPressed: _saving
              ? null
              : () {
                  Navigator.pop(context);
                },
          child: const Text('Cancel'),
        ),

        const SizedBox(width: 12),

        FilledButton.icon(
          onPressed:
              _saving ? null : _save,
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
                  Icons.save,
                ),
          label: Text(
            _saving
                ? 'Saving...'
                : 'Save Learner',
          ),
        ),
      ],
    );
  }

  // ============================================================
  // RESPONSIVE THREE-COLUMN LAYOUT
  // ============================================================

  Widget _buildThreeColumns(
    List<Widget> children,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 750) {
          return Column(
            children: [
              for (var i = 0;
                  i < children.length;
                  i++) ...[
                children[i],
                if (i != children.length - 1)
                  const SizedBox(height: 16),
              ],
            ],
          );
        }

        return Row(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            for (var i = 0;
                i < children.length;
                i++) ...[
              Expanded(
                child: children[i],
              ),
              if (i != children.length - 1)
                const SizedBox(width: 16),
            ],
          ],
        );
      },
    );
  }
}

// ================================================================
// SCHOOL HISTORY ENTRY
// ================================================================

class _SchoolHistoryEntry {
  _SchoolHistoryEntry({
    required this.repository,
    required String schoolYear,
    required String defaultSchoolName,
  }) {
    schoolYearController.text = schoolYear;
    schoolController.text = defaultSchoolName;
  }

  final DatabaseRepository repository;
  final TextEditingController schoolYearController = TextEditingController();
  final TextEditingController schoolController = TextEditingController();
  final TextEditingController sectionController = TextEditingController();
  final TextEditingController adviserController = TextEditingController();
  final TextEditingController notesController = TextEditingController();

  String? grade = '7';
  List<Map<String, Object?>> allSections = [];
  List<Map<String, Object?>> sections = [];
  List<Map<String, Object?>> teachers = [];
  bool loadingSections = false;
  bool addSectionToTable = false;
  bool addTeacherToTable = false;

  String _normalizeGrade(Object? value) {
    final text = value?.toString().trim() ?? '';
    final match = RegExp(r'^grade\s*(7|8|9|10|11|12)$', caseSensitive: false).firstMatch(text);
    if (match != null) return match.group(1)!;
    return text.toUpperCase() == 'SNED' ? 'SNED' : text;
  }

  String _normalizeText(Object? value) =>
      value?.toString().trim().toLowerCase() ?? '';

  Future<void> loadInitialData() async {
    await Future.wait([loadTeachers(), loadSections()]);
    _syncAdviserFromSection();
  }

  Future<void> loadTeachers() async {
    try {
      teachers = await repository.getTeachers();
    } catch (_) {
      teachers = [];
    }
  }

  Future<void> loadSections() async {
    loadingSections = true;
    try {
      // Load the complete Sections table, then filter locally. This is
      // important because the repository's getSections() is not school-year aware.
      allSections = await repository.getSections();
      final year = schoolYearController.text.trim();
      final selectedGrade = _normalizeGrade(grade);
      sections = allSections.where((row) {
        final rowYear = row['SchoolYear']?.toString().trim() ?? '';
        final rowGrade = _normalizeGrade(row['GradeLevel']);
        return rowYear == year && rowGrade == selectedGrade;
      }).toList();
    } catch (_) {
      allSections = [];
      sections = [];
    }
    loadingSections = false;
  }

  Map<String, Object?>? findMatchingSection() {
    final name = _normalizeText(sectionController.text);
    if (name.isEmpty) return null;
    for (final row in sections) {
      if (_normalizeText(row['SectionName']) == name) return row;
    }
    return null;
  }

  Map<String, Object?>? findMatchingTeacher(String name) {
    final normalized = _normalizeText(name);
    if (normalized.isEmpty) return null;
    for (final row in teachers) {
      if (_normalizeText(row['TeacherName']) == normalized) return row;
    }
    return null;
  }

  void _syncAdviserFromSection() {
    final match = findMatchingSection();
    final adviser = match?['Adviser']?.toString().trim() ?? '';
    if (adviser.isNotEmpty) adviserController.text = adviser;
  }

  void dispose() {
    schoolYearController.dispose();
    schoolController.dispose();
    sectionController.dispose();
    adviserController.dispose();
    notesController.dispose();
  }
}