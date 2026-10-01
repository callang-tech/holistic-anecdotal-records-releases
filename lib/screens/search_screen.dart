import 'package:intl/intl.dart';
import 'package:flutter/material.dart';

import '../database/database_repository.dart';
import '../models/location_selection.dart';
import '../widgets/app_shell.dart';
import '../widgets/location_selector.dart';
import '../widgets/sync_status_bar.dart';
import 'add_learner_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, this.repository});

  final DatabaseRepository? repository;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late final DatabaseRepository _repository =
      widget.repository ?? DatabaseRepository.instance;

  Widget _buildIncidentResultLine(
    Map<String, Object?> record,
    String wholeName,
  ) {
    final lrn = record['LearnerReferenceNumber']?.toString();

    final grade = record['IncidentGrade']?.toString();

    final section = record['IncidentSection']?.toString();

    final date = record['IncidentDate']?.toString();

    final observer = record['Observer']?.toString();

    final behavior = record['BehaviorProblem']?.toString();

    final intervention = record['Intervention']?.toString();

    final remarks = record['Remarks']?.toString();

    final details = <String>[
      if (lrn != null && lrn.isNotEmpty) 'LRN: $lrn',
      if (grade != null && grade.isNotEmpty)
        'During: ${_displayGrade(grade)}'
            '${section == null || section.isEmpty ? '' : ' • $section'}',
      if (date != null && date.isNotEmpty) date,
      if (observer != null && observer.isNotEmpty) 'Observer: $observer',
      if (behavior != null && behavior.isNotEmpty) behavior,
      if (intervention != null && intervention.isNotEmpty) intervention,
      if (remarks != null && remarks.isNotEmpty) remarks,
    ];

    return Tooltip(
      message: 'Double-click to view learner record',
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: wholeName,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
            if (details.isNotEmpty)
              TextSpan(
                text: '  •  ${details.join('  •  ')}',
              ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
  // ============================================================
  // LEARNER TEXT FILTERS
  // ============================================================

  final _lastNameController = TextEditingController();

  final _firstNameController = TextEditingController();

  final _middleNameController = TextEditingController();

  final _lrnController = TextEditingController();

  final _ageController = TextEditingController();

  // ============================================================
  // INCIDENT DATE
  // ============================================================

  final _incidentDateFromController = TextEditingController();

  final _incidentDateToController = TextEditingController();

  bool _showIncidentDateTo = false;

  bool _hasIncidentSpecificCriteria() {
    return _incidentGradeLevel != null ||
        (_section != null && _section!.trim().isNotEmpty) ||
        _incidentDateFromController.text.trim().isNotEmpty ||
        _incidentDateToController.text.trim().isNotEmpty ||
        _observer != null ||
        _behaviors.isNotEmpty ||
        _interventions.isNotEmpty ||
        _remarks.isNotEmpty;
  }

  // ============================================================
  // GRADE / SECTION
  // ============================================================

  String? _currentGradeLevel;
  String? _incidentGradeLevel;

  String? _section;

  String? _schoolYear;

  String? _observer;

  // ============================================================
  // LOCATION
  // ============================================================

  LocationSelection _location = const LocationSelection();

  // ============================================================
  // DATA
  // ============================================================

  List<String> _sections = [];

  List<String> _schoolYears = [];

  List<String> _observers = [];

  // ============================================================
  // CHECKLISTS
  // ============================================================

  final Set<String> _behaviors = {};

  final Set<String> _interventions = {};

  final Set<String> _remarks = {};

  static const _behaviorOptions = [
    'Bullying',
    'Misbehavior',
    'Mental Health',
    'Personal',
    'Social',
    'Academic',
    'Career',
    'Others...',
  ];

  static const _interventionOptions = [
    'Counseling',
    'Referral',
    'Consultation',
    'Placement',
    'Others...',
  ];

  static const _remarkOptions = [
    'Follow-up',
    'Monitor',
    'Termination',
    'Referral',
    'Others...',
  ];

  // ============================================================
  // RESULTS
  // ============================================================

  List<Map<String, Object?>> _allResults = [];

  static const int _pageSize = 10;

  int _page = 0;

  int? _selectedLearnerId;

  int? _selectedIncidentId;

  bool _searching = false;

  bool _searched = false;
  int _searchRequest = 0;
  int _filterRevision = 0;
  int? _totalLearners;
  int? _matchingLearners;
  bool _appliedIncidentCriteria = false;

  bool _hasCriteria() =>
      _hasIncidentSpecificCriteria() ||
      [
        _lastNameController.text,
        _firstNameController.text,
        _middleNameController.text,
        _lrnController.text,
        _ageController.text,
        _currentGradeLevel,
        _schoolYear,
        _location.regionCode,
        _location.provinceCode,
        _location.cityMunicipalityCode,
        _location.barangayCode
      ].any((value) => value != null && value.trim().isNotEmpty);

  // ============================================================
  // INIT / DISPOSE
  // ============================================================

  @override
  void initState() {
    super.initState();

    _loadSearchData();

    _incidentDateFromController.addListener(_dateFromChanged);
  }

  @override
  void dispose() {
    _lastNameController.dispose();
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lrnController.dispose();
    _ageController.dispose();

    _incidentDateFromController.dispose();
    _incidentDateToController.dispose();

    super.dispose();
  }

  // ============================================================
  // REFRESH AFTER RETURNING FROM ANOTHER SCREEN
  // ============================================================

  Future<void> _refreshAfterReturn() async {
    if (!mounted) return;

    // Re-run the current search using the existing filters.
    // This automatically removes archived/deleted learners and
    // includes newly added or edited learners.
    await _search();
  }

  Future<void> _openAddLearner() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AddLearnerScreen(),
      ),
    );

    if (!mounted) return;
    await _refreshAfterReturn();
  }

  Future<void> _openLearnerView(int learnerId) async {
    await Navigator.pushNamed(
      context,
      '/view',
      arguments: learnerId,
    );

    if (!mounted) return;
    await _refreshAfterReturn();
  }

  // ============================================================
  // INITIAL DATA
  // ============================================================

  Future<void> _loadSearchData() async {
    final teachers = await _repository.getTeachers();

    final schoolYears = await _repository.getSchoolYearsForSearch();

    if (!mounted) return;

    setState(() {
      _observers = teachers
          .map(
            (item) => item['TeacherName']?.toString() ?? '',
          )
          .where(
            (name) => name.isNotEmpty,
          )
          .toList();

      _schoolYears = schoolYears
          .map(
            (item) => item['SchoolYear']?.toString() ?? '',
          )
          .where(
            (value) => value.isNotEmpty,
          )
          .toList();
    });

    await _loadSections();

    // On the first visit, show the first page of learners automatically.
    // The existing pagination keeps the visible result set at 10 records.
    if (mounted) {
      await _search();
    }
  }

  Future<void> _loadSections() async {
    final rows = await _repository.getSectionsForSearch(
      schoolYear: _schoolYear,
      gradeLevel: _incidentGradeLevel,
    );

    if (!mounted) return;

    final sections = rows
        .map(
          (row) => row['SectionName']?.toString() ?? '',
        )
        .where(
          (name) => name.isNotEmpty,
        )
        .toSet()
        .toList();

    sections.sort(
      (a, b) => a.toLowerCase().compareTo(
            b.toLowerCase(),
          ),
    );

    setState(() {
      _sections = sections;

      if (_section != null &&
          !_sections.contains(
            _section,
          )) {
        _section = null;
      }
    });
  }

  // ============================================================
  // INCIDENT DATE BEHAVIOR
  // ============================================================

  void _dateFromChanged() {
    final fromText = _incidentDateFromController.text.trim();

    if (fromText.isEmpty) {
      if (_showIncidentDateTo) {
        setState(() {
          _showIncidentDateTo = false;
          _incidentDateToController.clear();
        });
      }

      return;
    }

    final fromDate = _parseSearchDate(fromText);

    if (fromDate == null) {
      if (!_showIncidentDateTo) {
        setState(() {
          _showIncidentDateTo = true;
        });
      }

      return;
    }

    final formatted = _formatDate(fromDate);

    if (_incidentDateToController.text != formatted) {
      _incidentDateToController.text = formatted;
    }

    if (!_showIncidentDateTo) {
      setState(() {
        _showIncidentDateTo = true;
      });
    }
  }

  void _onDateToChanged(
    String value,
  ) {
    final from = _parseSearchDate(
      _incidentDateFromController.text,
    );

    final to = _parseSearchDate(value);

    if (from != null && to != null && to.isBefore(from)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        _incidentDateToController.text = _formatDate(from);

        _showMessage(
          'Incident Date To cannot be earlier than Incident Date From.',
        );
      });
    }
  }

  // ============================================================
  // SEARCH
  // ============================================================

  Future<void> _search() async {
    final age = int.tryParse(
      _ageController.text.trim(),
    );

    final dateFrom = _parseSearchDate(
      _incidentDateFromController.text,
    );

    final dateTo = _showIncidentDateTo
        ? _parseSearchDate(
            _incidentDateToController.text,
          )
        : null;

    if (_incidentDateFromController.text.trim().isNotEmpty &&
        dateFrom == null) {
      _showMessage(
        'Please enter a valid Incident Date From.',
      );
      return;
    }

    if (_showIncidentDateTo &&
        _incidentDateToController.text.trim().isNotEmpty &&
        dateTo == null) {
      _showMessage(
        'Please enter a valid Incident Date To.',
      );
      return;
    }

    if (dateFrom != null && dateTo != null && dateTo.isBefore(dateFrom)) {
      _showMessage(
        'Incident Date To cannot be earlier than Incident Date From.',
      );
      return;
    }

    setState(() {
      _searching = true;
      _selectedLearnerId = null;
      _selectedIncidentId = null;
      _page = 0;
    });

    final request = ++_searchRequest;
    final hasCriteria = _hasCriteria();
    final incidentCriteria = _hasIncidentSpecificCriteria();
    try {
      final results = await _repository.searchIncidentRecords(
        lastName: _lastNameController.text,
        firstName: _firstNameController.text,
        middleName: _middleNameController.text,
        lrn: _lrnController.text,
        currentGradeLevel: _currentGradeLevel,
        incidentGradeLevel: _incidentGradeLevel,
        section: _section,
        age: age,
        regionCode: _location.regionCode,
        provinceCode: _location.provinceCode,
        municipalityCode: _location.cityMunicipalityCode,
        barangayCode: _location.barangayCode,
        schoolYearLastEnrolled: _schoolYear,
        incidentDateFrom: dateFrom,
        incidentDateTo: dateTo,
        observer: _observer,
        behaviors: _behaviors.toList(),
        interventions: _interventions.toList(),
        remarks: _remarks.toList(),
      );

      final total = await _repository.countActiveLearners();
      if (!mounted || request != _searchRequest) return;

      setState(() {
        _allResults = results;
        _totalLearners = total;
        _matchingLearners = hasCriteria
            ? DatabaseRepository.matchingLearnerCount(results)
            : null;
        _appliedIncidentCriteria = incidentCriteria;
        _searched = true;
      });
    } catch (e) {
      if (!mounted || request != _searchRequest) return;

      _showMessage(
        'Search failed:\n$e',
      );
    } finally {
      if (mounted && request == _searchRequest) {
        setState(() {
          _searching = false;
        });
      }
    }
  }

  // ============================================================
  // RESET
  // ============================================================

  void _reset() {
    _filterRevision++;
    _lastNameController.clear();
    _firstNameController.clear();
    _middleNameController.clear();
    _lrnController.clear();
    _ageController.clear();

    _incidentDateFromController.clear();
    _incidentDateToController.clear();

    setState(() {
      _currentGradeLevel = null;
      _incidentGradeLevel = null;

      _section = null;
      _schoolYear = null;
      _observer = null;

      _location = const LocationSelection();

      _behaviors.clear();
      _interventions.clear();
      _remarks.clear();

      _allResults = [];
      _selectedLearnerId = null;
      _selectedIncidentId = null;

      _page = 0;
      _searched = false;
      _matchingLearners = null;

      _showIncidentDateTo = false;
    });
    _loadSections();
    _search();
  }

  // ============================================================
  // DATE PICKER
  // ============================================================

  Future<void> _pickDateFrom() async {
    final selected = await _showDatePicker(
      _parseSearchDate(
            _incidentDateFromController.text,
          ) ??
          DateTime.now(),
    );

    if (selected == null) {
      return;
    }

    _incidentDateFromController.text = _formatDate(selected);

    // From's listener will automatically
    // populate Date To.
  }

  Future<void> _pickDateTo() async {
    final from = _parseSearchDate(
      _incidentDateFromController.text,
    );

    final selected = await _showDatePicker(
      _parseSearchDate(
            _incidentDateToController.text,
          ) ??
          from ??
          DateTime.now(),
      firstDate: from ?? DateTime(1900),
    );

    if (selected == null) {
      return;
    }

    _incidentDateToController.text = _formatDate(selected);
  }

  Future<DateTime?> _showDatePicker(
    DateTime initialDate, {
    DateTime? firstDate,
  }) {
    return showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate ?? DateTime(1900),
      lastDate: DateTime.now(),
    );
  }

  // ============================================================
  // DATE PARSING
  // ============================================================

  DateTime? _parseSearchDate(
    String value,
  ) {
    final text = value.trim();

    if (text.isEmpty) {
      return null;
    }

    final months = <String, int>{
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

    final monthMatch = RegExp(
      r'^([A-Za-z]+)\s+(\d{1,2}),?\s+(\d{4})$',
    ).firstMatch(text);

    if (monthMatch != null) {
      final month = months[monthMatch.group(1)!.toLowerCase()];

      if (month != null) {
        return DateTime(
          int.parse(
            monthMatch.group(3)!,
          ),
          month,
          int.parse(
            monthMatch.group(2)!,
          ),
        );
      }
    }

    final slashMatch = RegExp(
      r'^(\d{1,2})/(\d{1,2})/(\d{4})$',
    ).firstMatch(text);

    if (slashMatch != null) {
      return DateTime(
        int.parse(
          slashMatch.group(3)!,
        ),
        int.parse(
          slashMatch.group(1)!,
        ),
        int.parse(
          slashMatch.group(2)!,
        ),
      );
    }

    return DateTime.tryParse(text);
  }

  String _formatDate(
    DateTime date,
  ) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    return '${months[date.month - 1]} '
        '${date.day}, ${date.year}';
  }

  // ============================================================
  // CHECKLIST
  // ============================================================

  Widget _checklistSection({
    required String title,
    required List<String> options,
    required Set<String> selected,
  }) {
    return ExpansionTile(
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
        ),
      ),
      children: [
        Wrap(
          children: options.map((option) {
            return SizedBox(
              width: 220,
              child: CheckboxListTile(
                dense: true,
                value: selected.contains(
                  option,
                ),
                title: Text(option),
                onChanged: (value) {
                  setState(() {
                    if (value == true) {
                      selected.add(
                        option,
                      );
                    } else {
                      selected.remove(
                        option,
                      );
                    }
                  });
                },
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ============================================================
  // RESULTS / PAGINATION
  // ============================================================

  List<Map<String, Object?>> get _pageResults {
    final start = _page * _pageSize;

    if (start >= _allResults.length) {
      return [];
    }

    final end = (start + _pageSize).clamp(
      0,
      _allResults.length,
    );

    return _allResults.sublist(
      start,
      end,
    );
  }

  int get _pageCount {
    if (_allResults.isEmpty) {
      return 0;
    }

    return (_allResults.length + _pageSize - 1) ~/ _pageSize;
  }

  void _nextPage() {
    if (_page + 1 >= _pageCount) {
      return;
    }

    setState(() {
      _page++;
      _selectedLearnerId = null;
      _selectedIncidentId = null;
    });
  }

  void _previousPage() {
    if (_page == 0) {
      return;
    }

    setState(() {
      _page--;
      _selectedLearnerId = null;
      _selectedIncidentId = null;
    });
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Search Records',
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildSearchPanel(),
                  const SizedBox(height: 12),
                  _buildResultsPanel(),
                ],
              ),
            ),
          ),
          const SyncStatusBar(),
        ],
      ),
    );
  }

  // ============================================================
  // SEARCH PANEL
  // ============================================================

  Widget _buildSearchPanel() {
    return Card(
      key: ValueKey(_filterRevision),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Search Learner / Incident',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            _buildThreeColumns([
              _field(
                _lastNameController,
                'Family Name',
              ),
              _field(
                _firstNameController,
                'Given Name',
              ),
              _field(
                _middleNameController,
                'Middle Name',
              ),
            ]),
            const SizedBox(height: 12),
            _buildThreeColumns([
              _field(
                _lrnController,
                'LRN',
              ),
              TextField(
                controller: _ageController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Age',
                  border: OutlineInputBorder(),
                ),
              ),
              _gradeDropdown(
                label: 'Current Grade Level',
                value: _currentGradeLevel,
                onChanged: (value) {
                  setState(() {
                    _currentGradeLevel = value;
                  });
                },
              ),
            ]),
            const SizedBox(height: 12),
            _buildThreeColumns([
              _gradeDropdown(
                label: 'Grade Level During Incident',
                value: _incidentGradeLevel,
                onChanged: (value) async {
                  setState(() {
                    _incidentGradeLevel = value;
                    _section = null;
                  });

                  await _loadSections();
                },
              ),
              DropdownButtonFormField<String>(
                initialValue: _section,
                decoration: InputDecoration(
                  labelText: 'Section During Incident',
                  border: const OutlineInputBorder(),
                  suffixIcon: _section != null
                      ? IconButton(
                          tooltip: 'Clear section',
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            setState(() {
                              _section = null;
                            });
                          },
                        )
                      : null,
                ),
                items: _sections
                    .map(
                      (value) => DropdownMenuItem<String>(
                        value: value,
                        child: Text(value),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    _section = value;
                  });
                },
              ),
              DropdownButtonFormField<String>(
                initialValue: _schoolYear,
                decoration: InputDecoration(
                  labelText: 'School Year Last Enrolled',
                  border: const OutlineInputBorder(),
                  suffixIcon: _schoolYear != null
                      ? IconButton(
                          tooltip: 'Clear school year',
                          icon: const Icon(Icons.clear),
                          onPressed: () async {
                            setState(() {
                              _schoolYear = null;
                              _section = null;
                            });

                            await _loadSections();
                          },
                        )
                      : null,
                ),
                items: _schoolYears
                    .map(
                      (value) => DropdownMenuItem<String>(
                        value: value,
                        child: Text(value),
                      ),
                    )
                    .toList(),
                onChanged: (value) async {
                  setState(() {
                    _schoolYear = value;
                    _section = null;
                  });

                  await _loadSections();
                },
              ),
            ]),
            const SizedBox(height: 16),
            const Text(
              'Address',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            LocationSelector(
              useDefaults: false,
              onChanged: (selection) {
                setState(() {
                  _location = selection;
                });
              },
            ),
            const SizedBox(height: 16),
            _buildThreeColumns([
              _dateFieldFrom(),
              if (_showIncidentDateTo) _dateFieldTo() else const SizedBox(),
              DropdownButtonFormField<String>(
                initialValue: _observer,
                decoration: InputDecoration(
                  labelText: 'Observer',
                  border: const OutlineInputBorder(),
                  suffixIcon: _observer != null
                      ? IconButton(
                          tooltip: 'Clear observer',
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            setState(() {
                              _observer = null;
                            });
                          },
                        )
                      : null,
                ),
                items: _observers
                    .map(
                      (value) => DropdownMenuItem<String>(
                        value: value,
                        child: Text(value),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    _observer = value;
                  });
                },
              ),
            ]),
            const Divider(height: 28),
            _checklistSection(
              title: 'Behavior / Observation',
              options: _behaviorOptions,
              selected: _behaviors,
            ),
            _checklistSection(
              title: 'Intervention',
              options: _interventionOptions,
              selected: _interventions,
            ),
            _checklistSection(
              title: 'Remarks',
              options: _remarkOptions,
              selected: _remarks,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: _reset,
                  icon: const Icon(
                    Icons.refresh,
                  ),
                  label: const Text('Reset'),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _searching ? null : _search,
                  icon: _searching
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(
                          Icons.search,
                        ),
                  label: Text(
                    _searching ? 'Searching...' : 'Search',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _openAddLearner,
                  icon: const Icon(
                    Icons.person_add_alt_1_rounded,
                  ),
                  label: const Text('Add Learner'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // GRADE DROPDOWN
  // ============================================================

  Widget _gradeDropdown({
    required String label,
    required String? value,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        suffixIcon: value != null
            ? IconButton(
                tooltip: 'Clear grade',
                icon: const Icon(
                  Icons.clear,
                ),
                onPressed: () {
                  onChanged(null);
                },
              )
            : null,
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
      onChanged: onChanged,
    );
  }

  // ============================================================
  // DATE FROM
  // ============================================================

  Widget _dateFieldFrom() {
    return TextField(
      controller: _incidentDateFromController,
      decoration: InputDecoration(
        labelText: 'Incident Date From',
        hintText: 'August 22, 2026',
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          tooltip: 'Select date',
          icon: const Icon(
            Icons.calendar_month,
          ),
          onPressed: _pickDateFrom,
        ),
      ),
    );
  }

  // ============================================================
  // DATE TO
  // ============================================================

  Widget _dateFieldTo() {
    return TextField(
      controller: _incidentDateToController,
      decoration: InputDecoration(
        labelText: 'Incident Date To',
        hintText: 'August 22, 2026',
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          tooltip: 'Select date',
          icon: const Icon(
            Icons.calendar_month,
          ),
          onPressed: _pickDateTo,
        ),
      ),
      onChanged: _onDateToChanged,
    );
  }

  // ============================================================
  // RESULTS
  // ============================================================

  Widget _buildResultsPanel() {
    final results = _pageResults;

    final incidentLevelSearch = _appliedIncidentCriteria;

    return Card(
      elevation: 2,
      child: Column(
        children: [
          ListTile(
            dense: true,
            leading: const Icon(
              Icons.list_alt_rounded,
            ),
            title: const Text(
              'Search Results',
              style: TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Text(
              _searched
                  ? incidentLevelSearch
                      ? '${_allResults.length} matching incident record(s)'
                      : '${_allResults.length} learner(s)'
                  : 'Enter search criteria and press Search.',
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Wrap(spacing: 24, children: [
              Text(
                  'Total Learners: ${_totalLearners == null ? "Loading..." : NumberFormat.decimalPattern('en_US').format(_totalLearners)}'),
              if (_matchingLearners != null)
                Text(
                    'Matching Learners: ${NumberFormat.decimalPattern('en_US').format(_matchingLearners)}'),
            ]),
          ),
          const Divider(height: 1),
          if (results.isEmpty)
            Padding(
              padding: const EdgeInsets.all(28),
              child: Text(
                _searched
                    ? 'No records satisfy the search criteria.'
                    : 'No search has been performed yet.',
              ),
            )
          else
            ...results.map(
              (record) => _buildResultRow(
                record,
                incidentLevelSearch: incidentLevelSearch,
              ),
            ),
          if (_allResults.isNotEmpty) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 10,
              ),
              child: Row(
                children: [
                  Text(
                    'Page ${_page + 1} of $_pageCount',
                  ),
                  const Spacer(),
                  OutlinedButton(
                    onPressed: _page == 0 ? null : _previousPage,
                    child: const Text(
                      'Previous',
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: (_page + 1) >= _pageCount ? null : _nextPage,
                    child: const Text(
                      'Next',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildResultRow(
    Map<String, Object?> record, {
    required bool incidentLevelSearch,
  }) {
    final learnerId = record['LearnerID'] as int;

    final incidentId = record['IncidentID'] as int?;

    final selected =
        _selectedLearnerId == learnerId && _selectedIncidentId == incidentId;

    final lastName = record['LastName']?.toString() ?? '';

    final firstName = record['FirstName']?.toString() ?? '';

    final middleName = record['MiddleName']?.toString() ?? '';

    final wholeName = [
      lastName,
      if (firstName.isNotEmpty) firstName,
      if (middleName.isNotEmpty) middleName,
    ].join(', ');

    return Material(
      color: selected
          ? Theme.of(context).colorScheme.primaryContainer
          : Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedLearnerId = learnerId;
            _selectedIncidentId = incidentId;
          });
        },
        onDoubleTap: () {
          _openLearnerView(learnerId);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 9,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: incidentLevelSearch
                    ? _buildIncidentResultLine(
                        record,
                        wholeName,
                      )
                    : _buildLearnerResultLine(
                        record,
                        wholeName,
                      ),
              ),
              const SizedBox(width: 10),
              if (selected)
                IconButton(
                  tooltip: 'View Record',
                  onPressed: () {
                    _openLearnerView(learnerId);
                  },
                  icon: const Icon(
                    Icons.visibility_rounded,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // COMMON FIELD
  // ============================================================

  Widget _field(
    TextEditingController controller,
    String label,
  ) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }

  // ============================================================
  // LAYOUT
  // ============================================================

  Widget _buildThreeColumns(
    List<Widget> children,
  ) {
    return LayoutBuilder(
      builder: (
        context,
        constraints,
      ) {
        if (constraints.maxWidth < 800) {
          return Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                children[i],
                if (i != children.length - 1)
                  const SizedBox(
                    height: 12,
                  ),
              ],
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              Expanded(
                child: children[i],
              ),
              if (i != children.length - 1)
                const SizedBox(
                  width: 12,
                ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildLearnerResultLine(
    Map<String, Object?> record,
    String wholeName,
  ) {
    final lrn = record['LearnerReferenceNumber']?.toString();

    final currentGrade = record['CurrentGrade']?.toString();

    final currentSection = record['CurrentSection']?.toString();

    final age = record['Age']?.toString();

    final address = [
      record['Barangay'],
      record['TownMunicipality'],
      record['Province'],
      record['Region'],
    ]
        .where(
          (value) => value != null && value.toString().trim().isNotEmpty,
        )
        .map(
          (value) => value.toString(),
        )
        .join(', ');

    final details = <String>[
      if (lrn != null && lrn.isNotEmpty) 'LRN: $lrn',
      if (currentGrade != null && currentGrade.isNotEmpty)
        'Current: ${_displayGrade(currentGrade)}'
            '${currentSection == null || currentSection.isEmpty ? '' : ' • $currentSection'}',
      if (age != null && age.isNotEmpty) 'Age: $age',
      if (address.isNotEmpty) address,
    ];

    return Tooltip(
      message: 'Double-click to view learner record',
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: wholeName,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
            if (details.isNotEmpty)
              TextSpan(
                text: '  •  ${details.join('  •  ')}',
              ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  // ============================================================
  // MESSAGE
  // ============================================================

  void _showMessage(
    String message,
  ) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }
}

String _displayGrade(
  Object? grade,
) {
  final value = grade?.toString() ?? '';

  if (value == 'SNED') {
    return 'SNED';
  }

  if (value.isEmpty) {
    return '';
  }

  return 'Grade $value';
}
