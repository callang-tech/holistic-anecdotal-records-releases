import 'package:flutter/material.dart';

import '../database/app_database.dart';
import '../database/database_repository.dart';
import '../models/location_selection.dart';
import '../services/sync_service.dart';
import '../widgets/location_selector.dart';

class ViewScreen extends StatefulWidget {
  const ViewScreen({
    super.key,
  });

  @override
  State<ViewScreen> createState() =>
      _ViewScreenState();
}

class _ViewScreenState extends State<ViewScreen> {
  final DatabaseRepository _repository =
      DatabaseRepository.instance;

  Map<String, Object?>? _learner;

  List<Map<String, Object?>> _schoolHistory = [];

  List<Map<String, Object?>> _incidents = [];

  bool _loading = true;

  int? _learnerId;

  int? _selectedIncidentId;

  Map<String, Object?>? _selectedIncident;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (!_loading) {
      return;
    }

    final argument =
        ModalRoute.of(context)
            ?.settings
            .arguments;

    if (argument is int) {
      _learnerId = argument;
      _load(argument);
    }
  }

  // ============================================================
  // LOAD
  // ============================================================

  Future<void> _load(
    int learnerId,
  ) async {
    try {
      final learner =
          await _repository.getLearner(
        learnerId,
      );

      final history =
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
        _schoolHistory = history;
        _incidents = incidents;
        _selectedIncidentId = null;
        _selectedIncident = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
      });

      _showMessage(
        'Unable to load learner record.\n$e',
      );
    }
  }

  Future<void> _reloadAfterChange() async {
    final learnerId = _learnerId;

    if (learnerId == null) {
      return;
    }

    await _load(learnerId);
  }

  Future<bool> _autoSyncAfterLocalChange() async {
    try {
      final result = await SyncService.instance
          .syncPendingToGoogleSheets()
          .timeout(const Duration(seconds: 10));
      return result.success;
    } catch (_) {
      return false;
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
      return const Scaffold(
        body: Center(
          child:
              CircularProgressIndicator(),
        ),
      );
    }

    if (_learner == null ||
        _learnerId == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text(
            'Learner Record',
          ),
        ),
        body: const Center(
          child: Text(
            'Learner record not found.',
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Learner Record',
        ),
        actions: [
          IconButton(
            tooltip: 'Archived Learners',
            onPressed: _showArchivedLearners,
            icon: const Icon(
              Icons.archive_outlined,
            ),
          ),
          IconButton(
            tooltip: 'Print Record',
            onPressed:
                _printRecord,
            icon:
                const Icon(
              Icons.print_rounded,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              flex: 4,
              child:
                  _buildUpperInformation(),
            ),
            const Divider(
              height: 1,
              thickness: 1,
            ),
            Expanded(
              flex: 6,
              child:
                  _buildIncidentArea(),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // UPPER INFORMATION
  // ============================================================

  Widget _buildUpperInformation() {
    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.fromLTRB(
        14,
        10,
        14,
        10,
      ),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 55,
            child:
                _buildLearnerInformation(),
          ),
          const SizedBox(
            width: 12,
          ),
          Expanded(
            flex: 45,
            child:
                _buildSchoolHistory(),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // LEARNER INFORMATION
  // ============================================================

  Widget _buildLearnerInformation() {
    final learner = _learner!;

    final lrn = _text(
      learner[
          'LearnerReferenceNumber'],
    );

    final lastName = _text(
      learner['LastName'],
    );

    final firstName = _text(
      learner['FirstName'],
    );

    final middleName = _text(
      learner['MiddleName'],
    );

    final birthDate = _text(
      learner['BirthDate'],
    );

    final age = _text(
      learner['Age'],
    );

    final sex = _text(
      learner['Sex'],
    );

    final address =
        _compactAddress(
      learner,
    );

    final parents = _text(
      learner['Parents'],
    );

    final guardian = _text(
      learner['Guardian'],
    );

    final relationship = _text(
      learner[
          'RelationshipToGuardian'],
    );

    final notesDetails = _text(
      learner['NotesDetails'],
    );

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding:
            const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Learner Information',
                  style:
                      Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(
                            fontWeight:
                                FontWeight.bold,
                          ),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed:
                      _editLearner,
                  icon:
                      const Icon(
                    Icons.edit_rounded,
                    size: 17,
                  ),
                  label:
                      const Text(
                    'Edit',
                  ),
                ),
                const SizedBox(width: 6),
                OutlinedButton.icon(
                  onPressed: _archiveCurrentLearner,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                  icon: const Icon(
                    Icons.archive_outlined,
                    size: 17,
                  ),
                  label: const Text('Delete'),
                ),
                const SizedBox(width: 6),

              ],
            ),

            const SizedBox(
              height: 6,
            ),

            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [

            _informationLine(
              label: 'LRN',
              value: lrn.isEmpty
                  ? '—'
                  : lrn,
            ),

            const SizedBox(
              height: 4,
            ),

            Wrap(
              spacing: 18,
              runSpacing: 3,
              crossAxisAlignment:
                  WrapCrossAlignment
                      .center,
              children: [
                _inlineInformation(
                  label: 'Name',
                  value: [
                    lastName,
                    firstName,
                    middleName,
                  ]
                      .where(
                        (value) =>
                            value.isNotEmpty,
                      )
                      .join(', '),
                  bold: true,
                ),
                _inlineInformation(
                  label:
                      'Birth Date',
                  value:
                      birthDate.isEmpty
                          ? '—'
                          : birthDate,
                ),
                _inlineInformation(
                  label: 'Age',
                  value: age.isEmpty
                      ? '—'
                      : age,
                ),
                _inlineInformation(
                  label: 'Sex',
                  value: sex.isEmpty
                      ? '—'
                      : sex,
                ),
              ],
            ),

            const SizedBox(
              height: 5,
            ),

            _informationLine(
              label: 'Address',
              value:
                  address.isEmpty
                      ? '—'
                      : address,
              maxLines: 2,
            ),

            const SizedBox(
              height: 5,
            ),

            Wrap(
              spacing: 18,
              runSpacing: 3,
              children: [
                _inlineInformation(
                  label: 'Parents',
                  value:
                      parents.isEmpty
                          ? '—'
                          : parents,
                ),
                if (guardian.isNotEmpty)
                  _inlineInformation(
                    label: 'Guardian',
                    value: guardian,
                  ),
                if (guardian.isNotEmpty &&
                    relationship.isNotEmpty)
                  _inlineInformation(
                    label: 'Relationship',
                    value: relationship,
                  ),
              ],
            ),

            if (notesDetails.isNotEmpty) ...[
              const SizedBox(height: 5),
              _informationLine(
                label: 'Notes / Details',
                value: notesDetails,
                maxLines: 4,
              ),
            ],
                  ],
                ),
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
      margin: EdgeInsets.zero,
      child: Padding(
        padding:
            const EdgeInsets.all(11),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'School History',
                  style:
                      Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(
                            fontWeight:
                                FontWeight.bold,
                          ),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: _editSchoolHistory,
                  icon: const Icon(
                    Icons.edit_note_rounded,
                    size: 18,
                  ),
                  label: const Text('Edit History'),
                ),
              ],
            ),

            const SizedBox(
              height: 7,
            ),

            Container(
              padding:
                  const EdgeInsets.symmetric(
                horizontal: 7,
                vertical: 5,
              ),
              decoration:
                  BoxDecoration(
                color:
                    Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                borderRadius:
                    BorderRadius.circular(
                  6,
                ),
              ),
              child: const Row(
                children: [
                  Expanded(
                    flex: 22,
                    child: Text(
                      'School Year',
                      style:
                          TextStyle(
                        fontWeight:
                            FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 13,
                    child: Text(
                      'Grade',
                      style:
                          TextStyle(
                        fontWeight:
                            FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 29,
                    child: Text(
                      'Grade & Section',
                      style:
                          TextStyle(
                        fontWeight:
                            FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 36,
                    child: Text(
                      'Adviser',
                      style:
                          TextStyle(
                        fontWeight:
                            FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(
              height: 3,
            ),

            Expanded(
              child:
                  _schoolHistory.isEmpty
                      ? const Center(
                          child:
                              Text(
                            'No school history.',
                            style:
                                TextStyle(
                              fontSize: 12,
                            ),
                          ),
                        )
                      : ListView.separated(
                          itemCount:
                              _schoolHistory.length,
                          separatorBuilder:
                              (_, __) =>
                                  const Divider(
                            height: 1,
                          ),
                          itemBuilder:
                              (_, index) {
                            final row =
                                _schoolHistory[
                                    index];

                            return Padding(
                              padding:
                                  const EdgeInsets
                                      .symmetric(
                                horizontal: 7,
                                vertical: 5,
                              ),
                              child:
                                  Row(
                                children: [
                                  Expanded(
                                    flex: 22,
                                    child:
                                        _compactText(
                                      _text(
                                        row[
                                            'SchoolYear'],
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 13,
                                    child:
                                        _compactText(
                                      _displayGrade(
                                        row[
                                            'Grade'],
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 29,
                                    child:
                                        _compactText(
                                      _text(
                                        row[
                                            'Section'],
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 36,
                                    child:
                                        _compactText(
                                      _text(
                                        row[
                                            'Adviser'],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // ============================================================
  // SCHOOL HISTORY MANAGEMENT
  // ============================================================

  Future<void> _editSchoolHistory() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (
            context,
            setDialogState,
          ) {
            return AlertDialog(
              title: const Text(
                'Edit School History',
              ),
              content: SizedBox(
                width: 900,
                height: 520,
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed: () async {
                          Navigator.pop(
                            dialogContext,
                          );

                          await _addSchoolHistoryRecord();
                        },
                        icon: const Icon(
                          Icons.add_rounded,
                          size: 18,
                        ),
                        label: const Text(
                          'Add School History',
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: _schoolHistory.isEmpty
                          ? const Center(
                              child: Text(
                                'No school history records.',
                              ),
                            )
                          : ListView.separated(
                              itemCount:
                                  _schoolHistory.length,
                              separatorBuilder:
                                  (_, __) =>
                                      const Divider(
                                height: 1,
                              ),
                              itemBuilder:
                                  (_, index) {
                                final history =
                                    _schoolHistory[index];

                                final id = _asInt(
                                  history[
                                      'SchoolHistoryID'],
                                );

                                final schoolYear = _text(
                                  history['SchoolYear'],
                                );
                                final grade = _displayGrade(
                                  history['Grade'],
                                );
                                final school = _text(
                                  history['School'],
                                );
                                final section = _text(
                                  history['Section'],
                                );
                                final adviser = _text(
                                  history['Adviser'],
                                );

                                return ListTile(
                                  contentPadding:
                                      const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  title: Text(
                                    '$schoolYear  •  $grade',
                                    style:
                                        const TextStyle(
                                      fontWeight:
                                          FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Text(
                                    [
                                      if (school.isNotEmpty)
                                        school,
                                      if (section.isNotEmpty)
                                        section,
                                      if (adviser.isNotEmpty)
                                        'Adviser: $adviser',
                                    ].join('  •  '),
                                    maxLines: 2,
                                    overflow:
                                        TextOverflow.ellipsis,
                                  ),
                                  trailing: Row(
                                    mainAxisSize:
                                        MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: 'Edit',
                                        onPressed: id == null
                                            ? null
                                            : () async {
                                                Navigator.pop(
                                                  dialogContext,
                                                );
                                                await _editOneSchoolHistory(
                                                  history,
                                                );
                                              },
                                        icon: const Icon(
                                          Icons.edit_rounded,
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Delete',
                                        color: Theme.of(context)
                                            .colorScheme
                                            .error,
                                        onPressed: id == null
                                            ? null
                                            : () async {
                                                final confirmed =
                                                    await _confirmDeleteSchoolHistory();
                                                if (!confirmed) {
                                                  return;
                                                }

                                                try {
                                                  await _repository
                                                      .deleteSchoolHistory(id);
                                                  final synced =
                                                      await _autoSyncAfterLocalChange();
                                                  await _reloadAfterChange();

                                                  if (!mounted) {
                                                    return;
                                                  }

                                                  setDialogState(() {});

                                                  _showMessage(
                                                    synced
                                                        ? 'School history deleted and synced successfully.'
                                                        : 'School history deleted locally. It will sync when internet is available.',
                                                  );
                                                } catch (e) {
                                                  if (!context.mounted) {
                                                    return;
                                                  }

                                                  ScaffoldMessenger.of(
                                                    context,
                                                  ).showSnackBar(
                                                    SnackBar(
                                                      content: Text(
                                                        'Unable to delete school history.\\n$e',
                                                      ),
                                                    ),
                                                  );
                                                }
                                              },
                                        icon: const Icon(
                                          Icons.delete_outline_rounded,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                FilledButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                  },
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _addSchoolHistoryRecord() async {
    if (_learnerId == null) {
      return;
    }

    final result =
        await _showSchoolHistoryEditor();

    if (result == null) {
      return;
    }

    try {
      await _repository.addSchoolHistory(
        learnerId: _learnerId!,
        schoolYear:
            result['schoolYear'] as String,
        grade:
            result['grade'] as String,
        school:
            result['school'] as String,
        section:
            result['section'] as String?,
        adviser:
            result['adviser'] as String?,
        notes:
            result['notes'] as String?,
      );

      final synced = await _autoSyncAfterLocalChange();
      await _reloadAfterChange();

      if (!mounted) {
        return;
      }

      _showMessage(
        synced
            ? 'School history added and synced successfully.'
            : 'School history added locally. It will sync when internet is available.',
      );
    } catch (e) {
      _showMessage(
        'Unable to add school history.\\n$e',
      );
    }
  }

  Future<void> _editOneSchoolHistory(
    Map<String, Object?> history,
  ) async {
    final schoolHistoryId = _asInt(
      history['SchoolHistoryID'],
    );

    if (schoolHistoryId == null) {
      _showMessage(
        'School history ID could not be determined.',
      );
      return;
    }

    final result =
        await _showSchoolHistoryEditor(
      existing: history,
    );

    if (result == null) {
      return;
    }

    try {
      await _repository.updateSchoolHistory(
        schoolHistoryId:
            schoolHistoryId,
        schoolYear:
            result['schoolYear'] as String,
        grade:
            result['grade'] as String,
        school:
            result['school'] as String,
        section:
            result['section'] as String?,
        adviser:
            result['adviser'] as String?,
        notes:
            result['notes'] as String?,
      );

      final synced = await _autoSyncAfterLocalChange();
      await _reloadAfterChange();

      if (!mounted) {
        return;
      }

      _showMessage(
        synced
            ? 'School history updated and synced successfully.'
            : 'School history updated locally. It will sync when internet is available.',
      );
    } catch (e) {
      _showMessage(
        'Unable to update school history.\\n$e',
      );
    }
  }

  Future<bool> _confirmDeleteSchoolHistory() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            'Delete School History?',
          ),
          content: const Text(
            'This school history record will be removed from the active records.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  false,
                );
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor:
                    Theme.of(context)
                        .colorScheme
                        .error,
              ),
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  true,
                );
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    return result == true;
  }

  Future<Map<String, Object?>?>
      _showSchoolHistoryEditor({
    Map<String, Object?>? existing,
  }) async {
    final learner = _learner ?? {};

    // For a new history record, use the learner's current grade.
    // For an existing history record, preserve the grade saved in that
    // particular history record.
    final currentGrade = _normalizeGradeValue(
      _text(learner['GradeLevel']),
    );
    final savedHistoryGrade = existing == null
        ? ''
        : _normalizeGradeValue(
            _text(existing['Grade']),
          );

    final currentSection = _text(
      learner['SectionName'],
    );

    final currentAdviser = _text(
      learner['Adviser'],
    );

    final initialSchoolYear = existing == null
        ? _currentSchoolYear()
        : _text(existing['SchoolYear']);

    final schoolYearController =
        TextEditingController(
      text: initialSchoolYear,
    );

    final schoolController =
        TextEditingController(
      text: existing == null
          ? 'Callang National High School'
          : _text(existing['School']),
    );

    final sectionController =
        TextEditingController(
      text: existing == null
          ? currentSection
          : _text(existing['Section']),
    );

    final adviserController =
        TextEditingController(
      text: existing == null
          ? currentAdviser
          : _text(existing['Adviser']),
    );

    final notesController =
        TextEditingController(
      text: _text(existing?['NotesDetails']),
    );

    final initialGrade = existing == null
        ? currentGrade
        : savedHistoryGrade;

    String? grade = initialGrade.isEmpty
        ? null
        : initialGrade;

    final formKey = GlobalKey<FormState>();

    List<Map<String, Object?>> allSections = [];
    List<Map<String, Object?>> matchingSections = [];
    List<Map<String, Object?>> teachers = [];

    bool loadingLists = true;
    bool saveNewSectionToList = false;
    bool updateSectionAdviser = false;
    bool addTeacherToList = false;

    String normalizeText(Object? value) =>
        _text(value).toLowerCase();

    String? normalizeGrade(Object? value) {
      final text = _text(value);
      if (text.isEmpty) return null;
      return _normalizeGradeValue(text);
    }

    List<Map<String, Object?>> filterSections() {
      final year = schoolYearController.text.trim();
      final selectedGrade = grade?.trim() ?? '';

      if (year.isEmpty || selectedGrade.isEmpty) {
        return [];
      }

      return allSections.where((row) {
        final rowYear = _text(row['SchoolYear']);
        final rowGrade = normalizeGrade(row['GradeLevel']);

        return rowYear == year &&
            rowGrade == selectedGrade;
      }).toList();
    }

    Map<String, Object?>? findMatchingSection() {
      final name = normalizeText(sectionController.text);
      if (name.isEmpty) return null;

      for (final row in matchingSections) {
        if (normalizeText(row['SectionName']) == name) {
          return row;
        }
      }

      return null;
    }

    Map<String, Object?>? findMatchingTeacher(String name) {
      final normalized = normalizeText(name);
      if (normalized.isEmpty) return null;
      for (final row in teachers) {
        if (normalizeText(row['TeacherName']) == normalized) {
          return row;
        }
      }
      return null;
    }

    void refreshSectionState(
      void Function(void Function()) setDialogState, {
      bool clearSection = false,
      bool clearAdviser = false,
    }) {
      setDialogState(() {
        matchingSections = filterSections();

        if (clearSection) {
          sectionController.clear();
        }

        if (clearAdviser) {
          adviserController.clear();
        }

        final match = findMatchingSection();
        if (match != null) {
          final sectionAdviser =
              _text(match['Adviser']);
          if (sectionAdviser.isNotEmpty) {
            adviserController.text = sectionAdviser;
          }
        }

        saveNewSectionToList = false;
        updateSectionAdviser = false;
      });
    }

    try {
      final loadedSections =
          await _repository.getSections();
      final loadedTeachers =
          await _repository.getTeachers();

      allSections = loadedSections;
      teachers = loadedTeachers;
      matchingSections = filterSections();
      loadingLists = false;

      final initialMatch = findMatchingSection();
      if (initialMatch != null) {
        final sectionAdviser =
            _text(initialMatch['Adviser']);
        if (sectionAdviser.isNotEmpty) {
          adviserController.text = sectionAdviser;
        }
      }
    } catch (_) {
      loadingLists = false;
    }

    if (!mounted) return null;

    final result = await showDialog<
        Map<String, Object?>>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (
            context,
            setDialogState,
          ) {
            final schoolYears = List<String>.generate(
              6,
              (index) {
                final now = DateTime.now();
                final startYear =
                    (now.month >= 6 ? now.year : now.year - 1) -
                        index;
                return '$startYear-${startYear + 1}';
              },
            );

            
            final matchingSection = findMatchingSection();
            final typedSection = sectionController.text.trim();
            final sectionExists = matchingSection != null;
            final typedAdviser = adviserController.text.trim();
            final assignedAdviser = matchingSection == null
                ? ''
                : _text(matchingSection['Adviser']);
            final adviserDiffers =
                sectionExists &&
                typedAdviser.isNotEmpty &&
                normalizeText(typedAdviser) !=
                    normalizeText(assignedAdviser);
            final adviserExists =
                findMatchingTeacher(typedAdviser) != null;

            if (loadingLists) {
              return const AlertDialog(
                title: Text('Loading School History'),
                content: SizedBox(
                  height: 90,
                  child: Center(
                    child: CircularProgressIndicator(),
                  ),
                ),
              );
            }

            return AlertDialog(
              title: Text(
                existing == null
                    ? 'Add School History'
                    : 'Edit School History',
              ),
              content: SizedBox(
                width: 800,
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        DropdownMenu<String>(
                          controller: schoolYearController,
                          initialSelection:
                              schoolYears.contains(
                            schoolYearController.text.trim(),
                          )
                                  ? schoolYearController.text.trim()
                                  : null,
                          dropdownMenuEntries: schoolYears
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
                          width: 800,
                          onSelected: (value) {
                            if (value == null) return;
                            refreshSectionState(
                              setDialogState,
                              clearSection: true,
                              clearAdviser: true,
                            );
                          },
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          key: ValueKey<String?>(grade),
                          initialValue: [
                            '7', '8', '9', '10', '11', '12', 'SNED'
                          ].contains(grade)
                              ? grade
                              : null,
                          decoration: const InputDecoration(
                            labelText: 'Grade Level *',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(value: '7', child: Text('Grade 7')),
                            DropdownMenuItem(value: '8', child: Text('Grade 8')),
                            DropdownMenuItem(value: '9', child: Text('Grade 9')),
                            DropdownMenuItem(value: '10', child: Text('Grade 10')),
                            DropdownMenuItem(value: '11', child: Text('Grade 11')),
                            DropdownMenuItem(value: '12', child: Text('Grade 12')),
                            DropdownMenuItem(value: 'SNED', child: Text('SNED')),
                          ],
                          onChanged: (value) {
                            setDialogState(() {
                              grade = value;
                              matchingSections = filterSections();
                              sectionController.clear();
                              adviserController.clear();
                              saveNewSectionToList = false;
                              updateSectionAdviser = false;
                            });
                          },
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Required';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: schoolController,
                          decoration: const InputDecoration(
                            labelText: 'School *',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Required';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 10),
                        Autocomplete<String>(
                          initialValue: TextEditingValue(
                            text: sectionController.text,
                          ),
                          optionsBuilder: (value) {
                            final query = value.text.trim().toLowerCase();
                            final names = matchingSections
                                .map((row) => _text(row['SectionName']))
                                .where((name) => name.isNotEmpty)
                                .toSet()
                                .toList()
                              ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
                            if (query.isEmpty) return names;
                            return names.where((name) => name.toLowerCase().contains(query));
                          },
                          onSelected: (value) {
                            final match = matchingSections.firstWhere(
                              (row) => normalizeText(row['SectionName']) == normalizeText(value),
                              orElse: () => <String, Object?>{},
                            );
                            setDialogState(() {
                              sectionController.text = value;
                              final selectedAdviser = _text(match['Adviser']);
                              adviserController.text = selectedAdviser;
                              saveNewSectionToList = false;
                              updateSectionAdviser = false;
                            });
                          },
                          fieldViewBuilder: (context, textController, focusNode, onFieldSubmitted) {
                            return TextFormField(
                              controller: textController,
                              focusNode: focusNode,
                              decoration: InputDecoration(
                                labelText: 'Section',
                                hintText: matchingSections.isEmpty
                                    ? 'Type a section'
                                    : 'Select or type a section',
                                border: const OutlineInputBorder(),
                              ),
                              onChanged: (value) {
                                sectionController.text = value;
                                setDialogState(() {});
                              },
                              onFieldSubmitted: (_) => onFieldSubmitted(),
                            );
                          },
                        ),
                        if (typedSection.isNotEmpty && !sectionExists) ...[
                          const SizedBox(height: 5),
                          CheckboxListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            value: saveNewSectionToList,
                            onChanged: (value) {
                              setDialogState(() {
                                saveNewSectionToList = value ?? false;
                              });
                            },
                            title: Text(
                              'Add "$typedSection" to Sections for ${schoolYearController.text.trim()} / Grade ${grade ?? ''}',
                            ),
                            subtitle: const Text(
                              'The section will be saved for this exact school year and grade level.',
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        Autocomplete<String>(
                          // Recreate the Autocomplete whenever the selected
                          // section supplies a new adviser. The visible field
                          // controller is owned by Autocomplete, so changing
                          // adviserController alone does not update the field.
                          key: ValueKey<String>(
                            adviserController.text,
                          ),
                          initialValue: TextEditingValue(
                            text: adviserController.text,
                          ),
                          optionsBuilder: (value) {
                            final query = value.text.trim().toLowerCase();
                            final names = teachers
                                .map((row) => _text(row['TeacherName']))
                                .where((name) => name.isNotEmpty)
                                .toSet()
                                .toList()
                              ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
                            if (query.isEmpty) return names;
                            return names.where((name) => name.toLowerCase().contains(query));
                          },
                          onSelected: (value) {
                            setDialogState(() {
                              adviserController.text = value;
                              addTeacherToList = false;
                            });
                          },
                          fieldViewBuilder: (context, textController, focusNode, onFieldSubmitted) {
                            return TextFormField(
                              controller: textController,
                              focusNode: focusNode,
                              decoration: const InputDecoration(
                                labelText: 'Adviser',
                                hintText: 'Select or type adviser',
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (value) {
                                adviserController.text = value;
                                setDialogState(() {});
                              },
                              onFieldSubmitted: (_) => onFieldSubmitted(),
                            );
                          },
                        ),
                        if (typedAdviser.isNotEmpty && !adviserExists) ...[
                          const SizedBox(height: 5),
                          CheckboxListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            value: addTeacherToList,
                            onChanged: (value) {
                              setDialogState(() {
                                addTeacherToList = value ?? false;
                              });
                            },
                            title: Text('Add "$typedAdviser" to Teachers table'),
                            subtitle: const Text(
                              'The teacher will be added as Active. The section assignment remains school-year specific.',
                            ),
                          ),
                        ],
                        if (adviserDiffers) ...[
                          const SizedBox(height: 5),
                          CheckboxListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            value: updateSectionAdviser,
                            onChanged: (value) {
                              setDialogState(() {
                                updateSectionAdviser = value ?? false;
                              });
                            },
                            title: Text(
                              'Update the adviser of "$typedSection" in the Sections table',
                            ),
                            subtitle: Text(
                              'Current table assignment: ${assignedAdviser.isEmpty ? 'None' : assignedAdviser}',
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: notesController,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            labelText: 'Notes / Details',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                  },
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    final schoolYear = schoolYearController.text.trim();
                    if (schoolYear.isEmpty ||
                        !RegExp(r'^\d{4}-\d{4}$').hasMatch(schoolYear)) {
                      if (!dialogContext.mounted) return;
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(
                          content: Text('Use YYYY-YYYY format for School Year.'),
                        ),
                      );
                      return;
                    }

                    if (!(formKey.currentState?.validate() ?? false)) {
                      return;
                    }

                    final sectionName = sectionController.text.trim();
                    final adviser = adviserController.text.trim();
                    final selectedGrade = grade?.trim() ?? '';
                    final currentMatch = findMatchingSection();

                    if (adviser.isNotEmpty &&
                        addTeacherToList &&
                        findMatchingTeacher(adviser) == null) {
                      try {
                        await _repository.addTeacher(
                          teacherName: _titleCase(adviser),
                          mobileNumber: '',
                          status: 'Active',
                        );
                      } catch (e) {
                        if (!dialogContext.mounted) return;
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          SnackBar(content: Text('Unable to add adviser to Teachers table.\n$e')),
                        );
                        return;
                      }
                    }

                    if (sectionName.isNotEmpty &&
                        currentMatch == null &&
                        saveNewSectionToList) {
                      try {
                        await _repository.addSection(
                          schoolYear: schoolYear,
                          gradeLevel: selectedGrade,
                          sectionName: _titleCase(sectionName),
                          adviser: adviser,
                        );
                      } catch (e) {
                        if (!dialogContext.mounted) return;
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Unable to add section to the Sections table.\n$e',
                            ),
                          ),
                        );
                        return;
                      }
                    } else if (currentMatch != null &&
                        updateSectionAdviser &&
                        adviser.isNotEmpty) {
                      final sectionId = _asInt(
                        currentMatch['SectionID'],
                      );

                      if (sectionId != null) {
                        try {
                          await _repository.updateSection(
                            sectionId,
                            schoolYear: schoolYear,
                            gradeLevel: selectedGrade,
                            sectionName: _text(
                              currentMatch['SectionName'],
                            ),
                            adviser: adviser,
                          );
                        } catch (e) {
                          if (!dialogContext.mounted) return;
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Unable to update the adviser in the Sections table.\n$e',
                              ),
                            ),
                          );
                          return;
                        }
                      }
                    }

                    if (!dialogContext.mounted) return;

                    Navigator.pop(
                      dialogContext,
                      <String, Object?>{
                        'schoolYear': schoolYear,
                        'grade': selectedGrade,
                        'school': schoolController.text.trim(),
                        'section': _optionalTitleCase(sectionName),
                        'adviser': _optionalTitleCase(adviser),
                        'notes': _optionalText(notesController.text),
                      },
                    );
                  },
                  child: Text(
                    existing == null ? 'Add' : 'Save Changes',
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    // Do not dispose these controllers here. The dialog route can still be
    // rebuilding/animating immediately after showDialog returns, and its
    // TextFormFields may still reference the controllers. Disposing them here
    // causes 'TextEditingController was used after being disposed' errors.
    // They are local to this dialog and will be garbage-collected after the
    // dialog is fully gone.

    return result;
  }

  String _normalizeGradeValue(String value) {
    final text = value.trim();
    if (text.isEmpty) return '';

    final match = RegExp(r'^grade\s*(7|8|9|10|11|12)$',
            caseSensitive: false)
        .firstMatch(text);

    if (match != null) {
      return match.group(1)!;
    }

    return text.toUpperCase() == 'SNED'
        ? 'SNED'
        : text;
  }

  String _currentSchoolYear() {
    final now = DateTime.now();

    // Philippine school year normally begins around June.
    final startYear =
        now.month >= 6 ? now.year : now.year - 1;

    return '$startYear-${startYear + 1}';
  }


  // ============================================================

  // INCIDENT AREA
  // ============================================================

  Widget _buildIncidentArea() {
    return Padding(
      padding:
          const EdgeInsets.fromLTRB(
        12,
        8,
        12,
        12,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                'Incident Records',
                style:
                    Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(
                          fontWeight:
                              FontWeight.bold,
                        ),
              ),

              const SizedBox(
                width: 8,
              ),

              Text(
                '${_incidents.length} record(s)',
                style:
                    TextStyle(
                  color:
                      Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant,
                  fontSize: 12,
                ),
              ),

              const Spacer(),

              FilledButton.icon(
                onPressed:
                    _addIncident,
                icon:
                    const Icon(
                  Icons.add_rounded,
                  size: 18,
                ),
                label:
                    const Text(
                  'Add Incident',
                ),
              ),

              const SizedBox(
                width: 6,
              ),

              OutlinedButton.icon(
                onPressed:
                    _selectedIncidentId ==
                            null
                        ? null
                        : _showSelectedIncident,
                icon:
                    const Icon(
                  Icons.visibility_rounded,
                  size: 18,
                ),
                label:
                    const Text(
                  'View Details',
                ),
              ),

              const SizedBox(
                width: 6,
              ),

              OutlinedButton.icon(
                onPressed:
                    _selectedIncidentId ==
                            null
                        ? null
                        : _editIncident,
                icon:
                    const Icon(
                  Icons.edit_rounded,
                  size: 18,
                ),
                label:
                    const Text(
                  'Edit',
                ),
              ),

              const SizedBox(
                width: 6,
              ),

              OutlinedButton.icon(
                onPressed:
                    _selectedIncidentId ==
                            null
                        ? null
                        : _deleteIncident,
                style:
                    OutlinedButton.styleFrom(
                  foregroundColor:
                      Theme.of(context)
                          .colorScheme
                          .error,
                ),
                icon:
                    const Icon(
                  Icons
                      .delete_outline_rounded,
                  size: 18,
                ),
                label:
                    const Text(
                  'Delete',
                ),
              ),

              const SizedBox(
                width: 6,
              ),

              IconButton(
                tooltip:
                    'Print Record',
                onPressed:
                    _printRecord,
                icon:
                    const Icon(
                  Icons.print_rounded,
                ),
              ),
            ],
          ),

          const SizedBox(
            height: 7,
          ),

          Expanded(
            child:
                _incidents.isEmpty
                    ? _buildNoIncidents()
                    : _buildIncidentTable(),
          ),
        ],
      ),
    );
  }

  Widget _buildNoIncidents() {
    return Card(
      margin: EdgeInsets.zero,
      child: Center(
        child: Column(
          mainAxisSize:
              MainAxisSize.min,
          children: [
            Icon(
              Icons
                  .event_note_outlined,
              size: 44,
              color:
                  Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant,
            ),
            const SizedBox(
              height: 8,
            ),
            const Text(
              'No incident records for this learner.',
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // INCIDENT TABLE
  // ============================================================

  Widget _buildIncidentTable() {
    const tableWidth =
        1230.0;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior:
          Clip.antiAlias,
      child: Column(
        children: [
          SingleChildScrollView(
            scrollDirection:
                Axis.horizontal,
            child: SizedBox(
              width:
                  tableWidth,
              child:
                  Container(
                color:
                    Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                child:
                    Row(
                  children: [
                    _headerBox(
                      'Date',
                      82,
                    ),
                    _headerBox(
                      'Time',
                      68,
                    ),
                    _headerBox(
                      'Grade / Section',
                      120,
                    ),
                    _headerBox(
                      'Observer',
                      120,
                    ),
                    _headerBox(
                      'Behavior / Observation',
                      150,
                    ),
                    _headerBox(
                      'Observation Details',
                      150,
                    ),
                    _headerBox(
                      'Intervention',
                      130,
                    ),
                    _headerBox(
                      'Action Taken',
                      145,
                    ),
                    _headerBox(
                      'Remarks',
                      120,
                    ),
                    _headerBox(
                      'Details',
                      145,
                    ),
                  ],
                ),
              ),
            ),
          ),

          const Divider(
            height: 1,
          ),

          Expanded(
            child:
                SingleChildScrollView(
              scrollDirection:
                  Axis.horizontal,
              child: SizedBox(
                width:
                    tableWidth,
                child:
                    ListView.separated(
                  itemCount:
                      _incidents.length,
                  separatorBuilder:
                      (_, __) =>
                          const Divider(
                    height: 1,
                  ),
                  itemBuilder:
                      (_, index) {
                    return _buildIncidentRow(
                      _incidents[index],
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerBox(
    String text,
    double width,
  ) {
    return SizedBox(
      width: width,
      child: Padding(
        padding:
            const EdgeInsets.symmetric(
          horizontal: 8,
          vertical: 8,
        ),
        child:
            _TableHeader(text),
      ),
    );
  }

  Widget _buildIncidentRow(
    Map<String, Object?> incident,
  ) {
    final incidentId =
        _asInt(
      incident['IncidentID'],
    );

    final selected =
        incidentId != null &&
        incidentId ==
            _selectedIncidentId;

    final grade =
        _displayGrade(
      incident['IncidentGrade'],
    );

    final section =
        _text(
      incident['IncidentSection'],
    );

    return Material(
      color: selected
          ? Theme.of(context)
              .colorScheme
              .primaryContainer
          : Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedIncidentId =
                incidentId;
            _selectedIncident =
                incident;
          });
        },
        onDoubleTap: () {
          setState(() {
            _selectedIncidentId =
                incidentId;
            _selectedIncident =
                incident;
          });

          _showSelectedIncident();
        },
        child: SizedBox(
          width: 1230,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(
              vertical: 7,
            ),
            child: Row(
              crossAxisAlignment:
                  CrossAxisAlignment
                      .start,
              children: [
                _dataBox(
                  _text(
                    incident[
                        'IncidentDate'],
                  ),
                  82,
                ),

                _dataBox(
                  _text(
                    incident[
                        'IncidentTime'],
                  ),
                  68,
                ),

                _dataBox(
                  _formatGradeSection(
                    grade,
                    section,
                  ),
                  120,
                  maxLines: 2,
                ),

                _dataBox(
                  _text(
                    incident[
                        'Observer'],
                  ),
                  120,
                  maxLines: 2,
                ),

                _dataBox(
                  _text(
                    incident[
                        'BehaviorProblem'],
                  ),
                  150,
                  maxLines: 2,
                ),

                _dataBox(
                  _text(
                    incident[
                        'ObservationDetails'],
                  ),
                  150,
                  maxLines: 2,
                ),

                _dataBox(
                  _text(
                    incident[
                        'Intervention'],
                  ),
                  130,
                  maxLines: 2,
                ),

                _dataBox(
                  _text(
                    incident[
                        'ActionTaken'],
                  ),
                  145,
                  maxLines: 2,
                ),

                _dataBox(
                  _text(
                    incident['Remarks'],
                  ),
                  120,
                  maxLines: 2,
                ),

                _dataBox(
                  _text(
                    incident['Details'],
                  ),
                  145,
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dataBox(
    String value,
    double width, {
    int maxLines = 1,
  }) {
    return SizedBox(
      width: width,
      child: Padding(
        padding:
            const EdgeInsets.symmetric(
          horizontal: 8,
        ),
        child: _compactText(
          value,
          maxLines:
              maxLines,
        ),
      ),
    );
  }

  // ============================================================
  // INCIDENT DETAILS
  // ============================================================

  void _showSelectedIncident() {
    final incident =
        _selectedIncident;

    if (incident == null) {
      return;
    }

    _showIncidentDetails(
      incident,
    );
  }

  Future<void> _showIncidentDetails(
    Map<String, Object?> incident,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            'Incident Details',
          ),
          content: SizedBox(
            width: 720,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  _dialogInfo(
                    'Incident Date',
                    _text(
                      incident['IncidentDate'],
                    ),
                  ),

                  _dialogInfo(
                    'Incident Time',
                    _text(
                      incident['IncidentTime'],
                    ),
                  ),

                  _dialogInfo(
                    'Grade / Section',
                    _formatGradeSection(
                      _displayGrade(
                        incident['IncidentGrade'],
                      ),
                      _text(
                        incident['IncidentSection'],
                      ),
                    ),
                  ),

                  _dialogInfo(
                    'School Year',
                    _text(
                      incident['IncidentSchoolYear'],
                    ),
                  ),

                  _dialogInfo(
                    'Adviser',
                    _text(
                      incident['IncidentAdviser'],
                    ),
                  ),

                  _dialogInfo(
                    'Observer',
                    _text(
                      incident['Observer'],
                    ),
                  ),

                  _dialogInfo(
                    'Behavior / Observation',
                    _text(
                      incident['BehaviorProblem'],
                    ),
                  ),

                  _dialogParagraph(
                    'Observation Details',
                    _text(
                      incident[
                          'ObservationDetails'],
                    ),
                  ),

                  _dialogInfo(
                    'Intervention',
                    _text(
                      incident['Intervention'],
                    ),
                  ),

                  _dialogParagraph(
                    'Action Taken',
                    _text(
                      incident['ActionTaken'],
                    ),
                  ),

                  _dialogInfo(
                    'Remarks',
                    _text(
                      incident['Remarks'],
                    ),
                  ),

                  _dialogParagraph(
                    'Note / Details',
                    _text(
                      incident['Details'],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.pop(
                  dialogContext,
                );

                await Future<void>.delayed(
                  Duration.zero,
                );

                if (!mounted) {
                  return;
                }

                _selectedIncidentId =
                    _asInt(
                  incident['IncidentID'],
                );

                _selectedIncident =
                    incident;

                await _editIncident();
              },
              child: const Text(
                'Edit Incident',
              ),
            ),

            FilledButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                );
              },
              child: const Text(
                'Close',
              ),
            ),
          ],
        );
      },
    );
  }

  // ============================================================
  // ADD INCIDENT
  // ============================================================

  Future<void> _addIncident()
      async {
    final learnerId =
        _learnerId;

    if (learnerId == null) {
      return;
    }

    final result =
        await _showIncidentEditor();

    if (result == null) {
      return;
    }

    try {
      await _repository.addIncident(
        learnerId:
            learnerId,
        incidentDate:
            result[
                    'incidentDate']
                as String,
        incidentTime:
            result[
                    'incidentTime']
                as String?,
        observer:
            result[
                    'observer']
                as String?,
        behaviorProblem:
            result[
                    'behaviorProblem']
                as String,
        observationDetails:
            result[
                    'observationDetails']
                as String?,
        intervention:
            result[
                    'intervention']
                as String?,
        actionTaken:
            result[
                    'actionTaken']
                as String?,
        remarks:
            result[
                    'remarks']
                as String?,
        details:
            result[
                    'details']
                as String?,
      );

      final synced = await _autoSyncAfterLocalChange();
      await _reloadAfterChange();

      if (!mounted) {
        return;
      }

      _showMessage(
        synced
            ? 'Incident added and synced successfully.'
            : 'Incident added locally. It will sync when internet is available.',
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      _showMessage(
        'Unable to add incident.\n$e',
      );
    }
  }

  // ============================================================
  // EDIT INCIDENT
  // ============================================================

  Future<void> _editIncident()
      async {
    final incident =
        _selectedIncident;

    final incidentId =
        _selectedIncidentId;

    if (incident == null ||
        incidentId == null) {
      return;
    }

    final result =
        await _showIncidentEditor(
      existing:
          incident,
    );

    if (result == null) {
      return;
    }

    try {
      await _repository.updateIncident(
        incidentId,
        incidentDate:
            result[
                    'incidentDate']
                as String,
        incidentTime:
            result[
                    'incidentTime']
                as String?,
        observer:
            result[
                    'observer']
                as String?,
        behaviorProblem:
            result[
                    'behaviorProblem']
                as String,
        observationDetails:
            result[
                    'observationDetails']
                as String?,
        intervention:
            result[
                    'intervention']
                as String?,
        actionTaken:
            result[
                    'actionTaken']
                as String?,
        remarks:
            result[
                    'remarks']
                as String?,
        details:
            result[
                    'details']
                as String?,
      );

      final synced = await _autoSyncAfterLocalChange();
      await _reloadAfterChange();

      if (!mounted) {
        return;
      }

      _showMessage(
        synced
            ? 'Incident updated and synced successfully.'
            : 'Incident updated locally. It will sync when internet is available.',
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      _showMessage(
        'Unable to update incident.\n$e',
      );
    }
  }

  // ============================================================
  // DELETE INCIDENT
  // ============================================================

  Future<void> _deleteIncident()
      async {
    final incidentId =
        _selectedIncidentId;

    if (incidentId == null) {
      return;
    }

    final confirmed =
        await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) {
        return AlertDialog(
          title:
              const Text(
            'Delete Incident?',
          ),
          content:
              const Text(
            'This incident will be removed from the active records.',
          ),
          actions: [
            TextButton(
              onPressed:
                  () {
                Navigator.pop(
                  dialogContext,
                  false,
                );
              },
              child:
                  const Text(
                'Cancel',
              ),
            ),
            FilledButton(
              onPressed:
                  () {
                Navigator.pop(
                  dialogContext,
                  true,
                );
              },
              child:
                  const Text(
                'Delete',
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await _repository
          .deleteIncident(
        incidentId,
      );

      final synced = await _autoSyncAfterLocalChange();
      await _reloadAfterChange();

      if (!mounted) {
        return;
      }

      _showMessage(
        synced
            ? 'Incident deleted and synced successfully.'
            : 'Incident deleted locally. It will sync when internet is available.',
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      _showMessage(
        'Unable to delete incident.\n$e',
      );
    }
  }

  // ============================================================
  // INCIDENT EDITOR
  // ============================================================

  Future<Map<String, Object?>?>
      _showIncidentEditor({
    Map<String, Object?>? existing,
  }) {
    return showDialog<
        Map<String, Object?>>(
      context: context,
      barrierDismissible:
          false,
      builder: (_) {
        return _IncidentEditorDialog(
          existing:
              existing,
        );
      },
    );
  }


  // ============================================================
  // LEARNER ARCHIVE / RESTORE / PERMANENT DELETE
  // ============================================================

  Future<void> _archiveCurrentLearner() async {
    final learnerId = _learnerId;
    if (learnerId == null) return;

    final learner = _learner;
    final name = learner == null
        ? 'this learner'
        : [
            _text(learner['LastName']),
            _text(learner['FirstName']),
            _text(learner['MiddleName']),
          ].where((value) => value.isNotEmpty).join(', ');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Archive Learner?'),
        content: Text(
          '"$name" will be moved to Archived Learners. '
          'The record will not be permanently deleted and can be restored later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _repository.archiveLearner(learnerId: learnerId);
      final synced = await _autoSyncAfterLocalChange();

      if (!mounted) return;

      _showMessage(
        synced
            ? 'Learner archived and synced successfully.'
            : 'Learner archived locally. It will sync when internet is available.',
      );

      // The normal learner view only displays Deleted = 0 records.
      // Leave this screen after archiving so the list screen can refresh.
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      _showMessage('Unable to archive learner.\n$e');
    }
  }

  Future<void> _showArchivedLearners() async {
    var archived = await _repository.getArchivedLearners();

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> restore(int learnerId) async {
              try {
                await _repository.restoreLearner(learnerId: learnerId);
                final synced = await _autoSyncAfterLocalChange();
                archived = await _repository.getArchivedLearners();

                if (!dialogContext.mounted) return;
                setDialogState(() {});

                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  SnackBar(
                    content: Text(
                      synced
                          ? 'Learner restored and synced successfully.'
                          : 'Learner restored locally. It will sync when internet is available.',
                    ),
                  ),
                );
              } catch (e) {
                if (!dialogContext.mounted) return;
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  SnackBar(content: Text('Unable to restore learner.\n$e')),
                );
              }
            }

            Future<void> permanentlyDelete(int learnerId, String name) async {
              final confirmed = await showDialog<bool>(
                context: dialogContext,
                builder: (confirmContext) => AlertDialog(
                  title: const Text('Permanently Delete Learner?'),
                  content: Text(
                    'This will permanently remove "$name" from the local database '
                    'and from the connected Google Spreadsheet after synchronization. '
                    'This action cannot be undone.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(confirmContext, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Theme.of(dialogContext).colorScheme.error,
                      ),
                      onPressed: () => Navigator.pop(confirmContext, true),
                      child: const Text('Permanently Delete'),
                    ),
                  ],
                ),
              );

              if (confirmed != true) return;

              try {
                await _repository.permanentlyDeleteLearner(
                  learnerId: learnerId,
                );
                final synced = await _autoSyncAfterLocalChange();
                archived = await _repository.getArchivedLearners();

                if (!dialogContext.mounted) return;
                setDialogState(() {});

                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  SnackBar(
                    content: Text(
                      synced
                          ? 'Learner permanently deleted and synced successfully.'
                          : 'Learner marked for permanent deletion locally. It will be removed from Google Sheets when synchronization succeeds.',
                    ),
                  ),
                );
              } catch (e) {
                if (!dialogContext.mounted) return;
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  SnackBar(
                    content: Text('Unable to permanently delete learner.\n$e'),
                  ),
                );
              }
            }

            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.archive_outlined),
                  SizedBox(width: 10),
                  Expanded(child: Text('Archived Learners')),
                ],
              ),
              content: SizedBox(
                width: 760,
                height: 500,
                child: archived.isEmpty
                    ? const Center(
                        child: Text('There are no archived learners.'),
                      )
                    : ListView.separated(
                        itemCount: archived.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final learner = archived[index];
                          final id = _asInt(learner['LearnerID']);
                          final name = [
                            _text(learner['LastName']),
                            _text(learner['FirstName']),
                            _text(learner['MiddleName']),
                          ].where((value) => value.isNotEmpty).join(', ');

                          return ListTile(
                            title: Text(
                              name.isEmpty ? 'Unnamed learner' : name,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              'LRN: ${_text(learner['LearnerReferenceNumber']).isEmpty ? '—' : _text(learner['LearnerReferenceNumber'])}',
                            ),
                            trailing: SizedBox(
                              width: 300,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: id == null
                                          ? null
                                          : () => restore(id),
                                      icon: const Icon(
                                        Icons.restore_rounded,
                                        size: 18,
                                      ),
                                      label: const Text('Restore'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: id == null
                                          ? null
                                          : () => permanentlyDelete(id, name),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor:
                                            Theme.of(context).colorScheme.error,
                                      ),
                                      icon: const Icon(
                                        Icons.delete_forever_rounded,
                                        size: 18,
                                      ),
                                      label: const Text('Permanent Delete'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ============================================================
  // EDIT LEARNER
  // ============================================================

  Future<void> _editLearner()
      async {
    final learner =
        _learner;

    if (learner == null) {
      return;
    }

      debugPrint('========== EDIT LEARNER DEBUG ==========');
      debugPrint('Address fields:');
      debugPrint('HouseNo: ${learner['HouseNo']}');
      debugPrint('Street: ${learner['Street']}');
      debugPrint('Purok: ${learner['Purok']}');
      debugPrint('Barangay: ${learner['Barangay']}');
      debugPrint('TownMunicipality: ${learner['TownMunicipality']}');
      debugPrint('Province: ${learner['Province']}');
      debugPrint('Region: ${learner['Region']}');

      debugPrint('PSGC codes:');
      debugPrint('RegionCode: ${learner['RegionCode']}');
      debugPrint('ProvinceCode: ${learner['ProvinceCode']}');
      debugPrint(
        'CityMunicipalityCode: ${learner['CityMunicipalityCode']}',
      );
      debugPrint('BarangayCode: ${learner['BarangayCode']}');
      debugPrint('========================================');


    final lastNameController =
        TextEditingController(
      text:
          _text(
        learner['LastName'],
      ),
    );

    final firstNameController =
        TextEditingController(
      text:
          _text(
        learner['FirstName'],
      ),
    );

    final middleNameController =
        TextEditingController(
      text:
          _text(
        learner['MiddleName'],
      ),
    );

    final lrnController =
        TextEditingController(
      text:
          _text(
        learner[
            'LearnerReferenceNumber'],
      ),
    );

    final birthDateController =
        TextEditingController(
      text:
          _text(
        learner['BirthDate'],
      ),
    );

    final ageController =
        TextEditingController(
      text:
          _text(
        learner['Age'],
      ),
    );

    // When a birth date exists, age must always be derived from it.
    final initialBirthDate = _parseDate(
      birthDateController.text,
    );
    if (initialBirthDate != null) {
      ageController.text =
          _calculateAge(initialBirthDate).toString();
    }

    final schoolYearController =
        TextEditingController(
      text:
          _text(
        learner[
            'SchoolYearLastEnrolled'],
      ),
    );

    final houseNoController =
        TextEditingController(
      text:
          _text(
        learner['HouseNo'],
      ),
    );

    final streetController =
        TextEditingController(
      text:
          _text(
        learner['Street'],
      ),
    );

    final purokController =
        TextEditingController(
      text:
          _text(
        learner['Purok'],
      ),
    );

    final barangayController =
        TextEditingController(
      text:
          _text(
        learner['Barangay'],
      ),
    );

    final municipalityController =
        TextEditingController(
      text:
          _text(
        learner[
            'TownMunicipality'],
      ),
    );

    final provinceController =
        TextEditingController(
      text:
          _text(
        learner['Province'],
      ),
    );

    final regionController =
        TextEditingController(
      text:
          _text(
        learner['Region'],
      ),
    );

    final parentsController =
        TextEditingController(
      text:
          _text(
        learner['Parents'],
      ),
    );

    final guardianController =
        TextEditingController(
      text:
          _text(
        learner['Guardian'],
      ),
    );

    final relationshipController =
        TextEditingController(
      text:
          _text(
        learner[
            'RelationshipToGuardian'],
      ),
    );

    final contactController =
        TextEditingController(
      text:
          _text(
        learner[
            'PersonalContactNumber'],
      ),
    );

    final parentContactController =
        TextEditingController(
      text:
          _text(
        learner[
            'ParentsContactNumber'],
      ),
    );

    final notesController =
        TextEditingController(
      text:
          _text(
        learner['NotesDetails'],
      ),
    );

    String sex =
        _text(learner['Sex']);

    LocationSelection? location;

    final formKey =
        GlobalKey<FormState>();

    void updateAgeFromBirthDate() {
      final text = birthDateController.text.trim();
      if (text.isEmpty) {
        ageController.clear();
      } else {
        final date = _parseDate(text);
        if (date != null) {
          ageController.text =
              _calculateAge(date).toString();
        } else {
          ageController.clear();
        }
      }
    }

    birthDateController.addListener(updateAgeFromBirthDate);

    final result =
        await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) {
        return StatefulBuilder(
          builder:
              (
            context,
            setDialogState,
          ) {
            return AlertDialog(
              title:
                  const Text(
                'Edit Learner Information',
              ),
              content:
                  SizedBox(
                width: 900,
                child:
                    Form(
                  key:
                      formKey,
                  child:
                      SingleChildScrollView(
                    child:
                        Column(
                      crossAxisAlignment:
                          CrossAxisAlignment
                              .start,
                      children: [
                        _dialogTextField(
                          controller:
                              lrnController,
                          label:
                              'LRN',
                        ),

                        const SizedBox(
                          height: 10,
                        ),

                        Row(
                          children: [
                            Expanded(
                              child:
                                  _dialogTextField(
                                controller:
                                    lastNameController,
                                label:
                                    'Last Name *',
                                validator:
                                    (value) {
                                  if (value ==
                                          null ||
                                      value
                                          .trim()
                                          .isEmpty) {
                                    return 'Required';
                                  }

                                  return null;
                                },
                              ),
                            ),

                            const SizedBox(
                              width: 10,
                            ),

                            Expanded(
                              child:
                                  _dialogTextField(
                                controller:
                                    firstNameController,
                                label:
                                    'First Name *',
                                validator:
                                    (value) {
                                  if (value ==
                                          null ||
                                      value
                                          .trim()
                                          .isEmpty) {
                                    return 'Required';
                                  }

                                  return null;
                                },
                              ),
                            ),

                            const SizedBox(
                              width: 10,
                            ),

                            Expanded(
                              child:
                                  _dialogTextField(
                                controller:
                                    middleNameController,
                                label:
                                    'Middle Name',
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(
                          height: 10,
                        ),

                        Row(
                          children: [
                            Expanded(
                              child:
                                  DropdownButtonFormField<
                                      String>(
                                initialValue:
                                    sex.isEmpty
                                        ? null
                                        : sex,
                                decoration:
                                    const InputDecoration(
                                  labelText:
                                      'Sex *',
                                  border:
                                      OutlineInputBorder(),
                                ),
                                items:
                                    const [
                                  DropdownMenuItem(
                                    value:
                                        'Male',
                                    child:
                                        Text(
                                      'Male',
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value:
                                        'Female',
                                    child:
                                        Text(
                                      'Female',
                                    ),
                                  ),
                                ],
                                onChanged:
                                    (value) {
                                  setDialogState(
                                    () {
                                      sex =
                                          value ??
                                              '';
                                    },
                                  );
                                },
                                validator:
                                    (value) {
                                  if (value ==
                                      null) {
                                    return 'Required';
                                  }

                                  return null;
                                },
                              ),
                            ),

                            const SizedBox(
                              width: 10,
                            ),

                            Expanded(
                              child:
                                  _dialogTextField(
                                controller:
                                    birthDateController,
                                label:
                                    'Birth Date',
                                onChanged: (value) {
                                  final date = _parseDate(value.trim());
                                  if (date != null) {
                                    ageController.text =
                                        _calculateAge(date).toString();
                                  } else {
                                    ageController.clear();
                                  }
                                  setDialogState(() {});
                                },
                              ),
                            ),

                            const SizedBox(
                              width: 10,
                            ),

                            Expanded(
                              child:
                                  _dialogTextField(
                                controller:
                                    ageController,
                                label:
                                    'Age',
                                keyboardType:
                                    TextInputType
                                        .number,
                                readOnly:
                                    birthDateController
                                        .text
                                        .trim()
                                        .isNotEmpty,
                                helperText:
                                    birthDateController
                                            .text
                                            .trim()
                                            .isNotEmpty
                                        ? 'Automatically calculated from birth date'
                                        : 'Enter age if birth date is not provided',
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(
                          height: 10,
                        ),

                        _dialogTextField(
                          controller:
                              schoolYearController,
                          label:
                              'School Year Last Enrolled',
                        ),

                        const SizedBox(
                          height: 16,
                        ),

                        const Text(
                          'Address',
                          style:
                              TextStyle(
                            fontWeight:
                                FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),

                        const SizedBox(
                          height: 8,
                        ),

                        Row(
                          children: [
                            Expanded(
                              child:
                                  _dialogTextField(
                                controller:
                                    houseNoController,
                                label:
                                    'House No.',
                              ),
                            ),

                            const SizedBox(
                              width: 10,
                            ),

                            Expanded(
                              flex: 2,
                              child:
                                  _dialogTextField(
                                controller:
                                    streetController,
                                label:
                                    'Street',
                              ),
                            ),

                            const SizedBox(
                              width: 10,
                            ),

                            Expanded(
                              child:
                                  _dialogTextField(
                                controller:
                                    purokController,
                                label:
                                    'Purok',
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(
                          height: 10,
                        ),

                        LocationSelector(
                          key: ValueKey<String>(
                            '${_text(learner['RegionCode'])}|${_text(learner['ProvinceCode'])}|${_text(learner['CityMunicipalityCode'])}|${_text(learner['BarangayCode'])}',
                          ),
                          initialRegionCode:
                              _optionalText(_text(learner['RegionCode'])),
                          initialProvinceCode:
                              _optionalText(_text(learner['ProvinceCode'])),
                          initialCityMunicipalityCode:
                              _optionalText(_text(learner['CityMunicipalityCode'])),
                          initialBarangayCode:
                              _optionalText(_text(learner['BarangayCode'])),
                          useDefaults: false,
                          onChanged: (selection) {
                            setDialogState(() {
                              location = selection;

                              if (selection.barangayName != null &&
                                  selection.barangayName!.trim().isNotEmpty) {
                                barangayController.text =
                                    selection.barangayName!;
                              }

                              if (selection.cityMunicipalityName != null &&
                                  selection.cityMunicipalityName!.trim().isNotEmpty) {
                                municipalityController.text =
                                    selection.cityMunicipalityName!;
                              }

                              if (selection.provinceName != null &&
                                  selection.provinceName!.trim().isNotEmpty) {
                                provinceController.text =
                                    selection.provinceName!;
                              }

                              if (selection.regionName != null &&
                                  selection.regionName!.trim().isNotEmpty) {
                                regionController.text =
                                    selection.regionName!;
                              }
                            });
                          },
                        ),

                        const SizedBox(
                          height: 16,
                        ),

                        const Text(
                          'Parent / Guardian',
                          style:
                              TextStyle(
                            fontWeight:
                                FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),

                        const SizedBox(
                          height: 8,
                        ),

                        _dialogTextField(
                          controller:
                              parentsController,
                          label:
                              'Parents',
                        ),

                        const SizedBox(
                          height: 10,
                        ),

                        Row(
                          children: [
                            Expanded(
                              child:
                                  _dialogTextField(
                                controller:
                                    guardianController,
                                label:
                                    'Guardian',
                              ),
                            ),

                            const SizedBox(
                              width: 10,
                            ),

                            Expanded(
                              child:
                                  _dialogTextField(
                                controller:
                                    relationshipController,
                                label:
                                    'Relationship to Guardian',
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(
                          height: 10,
                        ),

                        _dialogTextField(
                          controller:
                              contactController,
                          label:
                              'Learner Contact Number',
                        ),

                        const SizedBox(
                          height: 10,
                        ),

                        _dialogTextField(
                          controller:
                              parentContactController,
                          label:
                              'Parents / Guardian Contact Number',
                        ),

                        const SizedBox(
                          height: 10,
                        ),

                        _dialogTextField(
                          controller:
                              notesController,
                          label:
                              'Notes / Details',
                          maxLines: 4,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed:
                      () {
                    Navigator.pop(
                      dialogContext,
                      false,
                    );
                  },
                  child:
                      const Text(
                    'Cancel',
                  ),
                ),

                FilledButton(
                  onPressed:
                      () async {
                    if (!formKey
                        .currentState!
                        .validate()) {
                      return;
                    }

                    final learnerId = _learnerId;

                    if (learnerId == null) {
                      if (!dialogContext
                          .mounted) {
                        return;
                      }

                      ScaffoldMessenger.of(
                        dialogContext,
                      ).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Learner record ID could not be determined.',
                          ),
                        ),
                      );

                      return;
                    }

                    try {
                      await _repository
                          .updateLearnerFields(
                        learnerId:
                            learnerId,
                        lrn:
                            _optionalText(
                          lrnController.text,
                        ),
                        lastName:
                            _titleCase(lastNameController.text),
                        firstName:
                            _titleCase(firstNameController.text),
                        middleName:
                            _optionalTitleCase(
                          middleNameController.text,
                        ),
                        sex:
                            _optionalText(
                          sex,
                        ),
                        birthDate:
                            _optionalText(
                          birthDateController
                              .text,
                        ),
                        age:
                            int.tryParse(
                          ageController
                              .text
                              .trim(),
                        ),
                        schoolYearLastEnrolled:
                            _optionalText(
                          schoolYearController
                              .text,
                        ),
                        houseNo:
                            _optionalText(
                          houseNoController
                              .text,
                        ),
                        street:
                            _optionalText(
                          streetController
                              .text,
                        ),
                        purok:
                            _optionalText(
                          purokController
                              .text,
                        ),
                        barangay:
                            _optionalText(
                          barangayController
                              .text,
                        ),
                        townMunicipality:
                            _optionalText(
                          municipalityController
                              .text,
                        ),
                        province:
                            _optionalText(
                          provinceController
                              .text,
                        ),
                        region:
                            _optionalText(
                          regionController
                              .text,
                        ),
                        parents:
                            _optionalTitleCase(
                          parentsController.text,
                        ),
                        guardian:
                            _optionalTitleCase(
                          guardianController.text,
                        ),
                        relationshipToGuardian:
                            _optionalTitleCase(
                          relationshipController.text,
                        ),
                        contactNumber:
                            _optionalText(
                          contactController
                              .text,
                        ),
                        notesDetails:
                            _optionalText(
                          notesController
                              .text,
                        ),
                      );

                      if (location != null) {
                        final selectedLocation = location!;
                        final currentVersion =
                            _asInt(learner['Version']) ?? 1;
                        await AppDatabase.instance.database.update(
                          'LEARNERS_Table',
                          <String, Object?>{
                            'RegionCode': selectedLocation.regionCode,
                            'ProvinceCode': selectedLocation.provinceCode,
                            'CityMunicipalityCode': selectedLocation.cityMunicipalityCode,
                            'BarangayCode': selectedLocation.barangayCode,
                            'UpdatedAt': DateTime.now().toUtc().toIso8601String(),
                            'DeviceID': SyncService.instance.deviceId,
                            'Version': currentVersion + 1,
                          },
                          where: 'LearnerID = ?',
                          whereArgs: [learnerId],
                        );
                      }

                      if (!dialogContext
                          .mounted) {
                        return;
                      }

                      Navigator.pop(
                        dialogContext,
                        true,
                      );
                    } catch (e) {
                      if (!dialogContext
                          .mounted) {
                        return;
                      }

                      ScaffoldMessenger.of(
                        dialogContext,
                      ).showSnackBar(
                        SnackBar(
                          content:
                              Text(
                            'Unable to save learner.\n$e',
                          ),
                        ),
                      );
                    }
                  },
                  child:
                      const Text(
                    'Save',
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == true) {
      final synced = await _autoSyncAfterLocalChange();
      await _reloadAfterChange();

      if (mounted) {
        _showMessage(
          synced
              ? 'Learner information updated and synced successfully.'
              : 'Learner information updated locally. It will sync when internet is available.',
        );
      }
    }

    birthDateController.removeListener(updateAgeFromBirthDate);

    lastNameController.dispose();
    firstNameController.dispose();
    middleNameController.dispose();
    lrnController.dispose();
    birthDateController.dispose();
    ageController.dispose();
    schoolYearController.dispose();
    houseNoController.dispose();
    streetController.dispose();
    purokController.dispose();
    barangayController.dispose();
    municipalityController.dispose();
    provinceController.dispose();
    regionController.dispose();
    parentsController.dispose();
    guardianController.dispose();
    relationshipController.dispose();
    contactController.dispose();
    parentContactController.dispose();
    notesController.dispose();

    if (result == true &&
        mounted) {
      await _reloadAfterChange();

      if (!mounted) {
        return;
      }

      _showMessage(
        'Learner information updated.',
      );
    }
  }

  // ============================================================
  // PRINT
  // ============================================================

  void _printRecord() {
    final learnerId =
        _learnerId;

    if (learnerId == null) {
      return;
    }

    Navigator.pushNamed(
      context,
      '/print',
      arguments:
          learnerId,
    );
  }

  // ============================================================
  // UI HELPERS
  // ============================================================

  Widget _informationLine({
    required String label,
    required String value,
    int maxLines = 1,
  }) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text:
                '$label: ',
            style: TextStyle(
              color:
                  Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant,
              fontSize: 11,
            ),
          ),
          TextSpan(
            text: value,
            style:
                const TextStyle(
              fontWeight:
                  FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
      maxLines:
          maxLines,
      overflow:
          TextOverflow.ellipsis,
    );
  }

  Widget _inlineInformation({
    required String label,
    required String value,
    bool bold = false,
  }) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text:
                '$label: ',
            style: TextStyle(
              color:
                  Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant,
              fontSize: 11,
            ),
          ),
          TextSpan(
            text: value,
            style: TextStyle(
              fontWeight:
                  bold
                      ? FontWeight.w700
                      : FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _compactText(
    String value, {
    int maxLines = 1,
  }) {
    return Text(
      value,
      maxLines:
          maxLines,
      overflow:
          TextOverflow.ellipsis,
      style:
          const TextStyle(
        fontSize: 12,
      ),
    );
  }

  Widget _dialogInfo(
    String label,
    String value,
  ) {
    return Padding(
      padding:
          const EdgeInsets.only(
        bottom: 8,
      ),
      child:
          Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text:
                  '$label\n',
              style:
                  TextStyle(
                color:
                    Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant,
                fontSize: 12,
              ),
            ),
            TextSpan(
              text:
                  value.isEmpty
                      ? '—'
                      : value,
              style:
                  const TextStyle(
                fontWeight:
                    FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dialogParagraph(
    String label,
    String value,
  ) {
    return Padding(
      padding:
          const EdgeInsets.only(
        bottom: 10,
      ),
      child:
          Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style:
                TextStyle(
              color:
                  Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant,
              fontSize: 12,
            ),
          ),
          const SizedBox(
            height: 3,
          ),
          Text(
            value.isEmpty
                ? '—'
                : value,
            style:
                const TextStyle(
              fontSize: 14,
              fontWeight:
                  FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _dialogTextField({
    required TextEditingController
        controller,
    required String label,
    String? hint,
    String? Function(String?)?
        validator,
    int maxLines = 1,
    TextInputType? keyboardType,
    bool readOnly = false,
    String? helperText,
    ValueChanged<String>? onChanged,
  }) {
    return TextFormField(
      controller:
          controller,
      maxLines:
          maxLines,
      keyboardType:
          keyboardType,
      readOnly:
          readOnly,
      onChanged:
          onChanged,
      validator:
          validator,
      decoration:
          InputDecoration(
        labelText:
            label,
        hintText:
            hint,
        helperText:
            helperText,
        border:
            const OutlineInputBorder(),
      ),
    );
  }

  // ============================================================
  // DATA HELPERS
  // ============================================================

  String _text(
    Object? value,
  ) {
    return value
            ?.toString()
            .trim() ??
        '';
  }

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

  String? _optionalText(
    String value,
  ) {
    final text =
        value.trim();

    return text.isEmpty
        ? null
        : text;
  }

  DateTime? _parseDate(String input) {
    final text = input.trim();
    if (text.isEmpty) return null;

    final iso = DateTime.tryParse(text);
    if (iso != null) return DateTime(iso.year, iso.month, iso.day);

    const months = <String, int>{
      'january': 1, 'february': 2, 'march': 3, 'april': 4,
      'may': 5, 'june': 6, 'july': 7, 'august': 8,
      'september': 9, 'october': 10, 'november': 11, 'december': 12,
      'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'jun': 6,
      'jul': 7, 'aug': 8, 'sep': 9, 'sept': 9, 'oct': 10,
      'nov': 11, 'dec': 12,
    };

    final normalized = text.replaceAll('.', ' ').replaceAll(',', ' ').trim();

    final monthFirst = RegExp(r'^([A-Za-z]+)\s+(\d{1,2})\s+(\d{4})$')
        .firstMatch(normalized);
    if (monthFirst != null) {
      final month = months[monthFirst.group(1)!.toLowerCase()];
      final day = int.tryParse(monthFirst.group(2)!);
      final year = int.tryParse(monthFirst.group(3)!);
      if (month != null && day != null && year != null) {
        return _validDate(year, month, day);
      }
    }

    final dayFirst = RegExp(r'^(\d{1,2})\s+([A-Za-z]+)\s+(\d{4})$')
        .firstMatch(normalized);
    if (dayFirst != null) {
      final day = int.tryParse(dayFirst.group(1)!);
      final month = months[dayFirst.group(2)!.toLowerCase()];
      final year = int.tryParse(dayFirst.group(3)!);
      if (month != null && day != null && year != null) {
        return _validDate(year, month, day);
      }
    }

    final numeric = RegExp(r'^(\d{1,4})[\/-](\d{1,2})[\/-](\d{1,4})$')
        .firstMatch(text);
    if (numeric != null) {
      final a = int.tryParse(numeric.group(1)!);
      final b = int.tryParse(numeric.group(2)!);
      final c = int.tryParse(numeric.group(3)!);
      if (a != null && b != null && c != null) {
        if (a >= 1000) return _validDate(a, b, c);
        if (a > 12) return _validDate(c, b, a);
        return _validDate(c, a, b);
      }
    }
    return null;
  }

  DateTime? _validDate(int year, int month, int day) {
    if (year < 1 || month < 1 || month > 12 || day < 1) return null;
    final date = DateTime(year, month, day);
    if (date.year != year || date.month != month || date.day != day) return null;
    return date;
  }

  int _calculateAge(DateTime birthDate) {
    final today = DateTime.now();
    var age = today.year - birthDate.year;
    final birthdayPassed = today.month > birthDate.month ||
        (today.month == birthDate.month && today.day >= birthDate.day);
    if (!birthdayPassed) age--;
    return age < 0 ? 0 : age;
  }


  int? _asInt(
    Object? value,
  ) {
    if (value is int) {
      return value;
    }

    return int.tryParse(
      value?.toString() ?? '',
    );
  }

  String _displayGrade(
    Object? grade,
  ) {
    final value =
        _text(grade);

    if (value.isEmpty) {
      return '';
    }

    if (value.toUpperCase() ==
        'SNED') {
      return 'SNED';
    }

    if (value
        .toLowerCase()
        .startsWith('grade ')) {
      return value;
    }

    return 'Grade $value';
  }

  String _formatGradeSection(
    String grade,
    String section,
  ) {
    if (grade.isEmpty) {
      return section;
    }

    if (section.isEmpty) {
      return grade;
    }

    return '$grade • $section';
  }

  String _compactAddress(
    Map<String, Object?> learner,
  ) {
    final parts =
        <String>[];

    final fields = [
      learner['HouseNo'],
      learner['Street'],
      learner['Purok'],
      learner['Barangay'],
      learner[
          'TownMunicipality'],
      learner['Province'],
      learner['Region'],
    ];

    for (final field
        in fields) {
      final value =
          _text(field);

      if (value.isNotEmpty) {
        parts.add(value);
      }
    }

    return parts.join(
      ', ',
    );
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

// ================================================================
// TABLE HEADER
// ================================================================

class _TableHeader
    extends StatelessWidget {
  const _TableHeader(
    this.text,
  );

  final String text;

  @override
  Widget build(
    BuildContext context,
  ) {
    return Text(
      text,
      maxLines: 2,
      overflow:
          TextOverflow.ellipsis,
      style:
          const TextStyle(
        fontWeight:
            FontWeight.bold,
        fontSize: 11,
      ),
    );
  }
}

// ================================================================
// INCIDENT EDITOR
// ================================================================

class _IncidentEditorDialog
    extends StatefulWidget {
  const _IncidentEditorDialog({
    this.existing,
  });

  final Map<String, Object?>?
      existing;

  @override
  State<_IncidentEditorDialog>
      createState() =>
          _IncidentEditorDialogState();
}

class _IncidentEditorDialogState
    extends State<
        _IncidentEditorDialog> {
  final GlobalKey<FormState>
      _formKey =
      GlobalKey<FormState>();

  late final TextEditingController
      _dateController;

  late final TextEditingController
      _timeController;

  late final TextEditingController
      _observerController;

  late final TextEditingController
      _observationDetailsController;

  late final TextEditingController
      _actionTakenController;

  late final TextEditingController
      _detailsController;

  final Set<String>
      _behaviors =
      <String>{};

  final Set<String>
      _interventions =
      <String>{};

  final Set<String>
      _remarks =
      <String>{};

  bool get _editing =>
      widget.existing != null;

  @override
  void initState() {
    super.initState();

    final existing =
        widget.existing;

    _dateController =
        TextEditingController(
      text: existing?['IncidentDate']
              ?.toString()
              .trim()
              .isNotEmpty ==
          true
          ? existing!['IncidentDate']!.toString()
          : _formatDate(DateTime.now()),
    );

    _timeController =
        TextEditingController(
      text:
          existing?[
                      'IncidentTime']
                  ?.toString() ??
              '',
    );

    _observerController =
        TextEditingController(
      text:
          existing?[
                      'Observer']
                  ?.toString() ??
              '',
    );

    _observationDetailsController =
        TextEditingController(
      text:
          existing?[
                      'ObservationDetails']
                  ?.toString() ??
              '',
    );

    _actionTakenController =
        TextEditingController(
      text:
          existing?[
                      'ActionTaken']
                  ?.toString() ??
              '',
    );

    _detailsController =
        TextEditingController(
      text:
          existing?[
                      'Details']
                  ?.toString() ??
              '',
    );

    _behaviors.addAll(
      _splitChecklist(
        existing?[
            'BehaviorProblem'],
      ),
    );

    _interventions.addAll(
      _splitChecklist(
        existing?[
            'Intervention'],
      ),
    );

    _remarks.addAll(
      _splitChecklist(
        existing?[
            'Remarks'],
      ),
    );
  }

  @override
  void dispose() {
    _dateController.dispose();
    _timeController.dispose();
    _observerController.dispose();
    _observationDetailsController
        .dispose();
    _actionTakenController.dispose();
    _detailsController.dispose();

    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return AlertDialog(
      title: Text(
        _editing
            ? 'Edit Incident'
            : 'Add Incident',
      ),
      content:
          SizedBox(
        width: 800,
        child:
            Form(
          key:
              _formKey,
          child:
              SingleChildScrollView(
            child:
                Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller:
                      _dateController,
                  decoration:
                      InputDecoration(
                    labelText:
                        'Incident Date *',
                    hintText:
                        'August 22, 2026',
                    border:
                        const OutlineInputBorder(),
                    suffixIcon:
                        IconButton(
                      tooltip:
                          'Select date',
                      icon:
                          const Icon(
                        Icons
                            .calendar_month_rounded,
                      ),
                      onPressed:
                          _selectDate,
                    ),
                  ),
                  validator:
                      (value) {
                    if (value ==
                            null ||
                        value
                            .trim()
                            .isEmpty) {
                      return 'Incident date is required.';
                    }

                    if (_parseDate(
                          value,
                        ) ==
                        null) {
                      return 'Enter a valid date.';
                    }

                    return null;
                  },
                ),

                const SizedBox(
                  height: 10,
                ),

                TextFormField(
                  controller:
                      _timeController,
                  decoration:
                      const InputDecoration(
                    labelText:
                        'Incident Time',
                    hintText:
                        '10:30 AM',
                    border:
                        OutlineInputBorder(),
                  ),
                ),

                const SizedBox(
                  height: 10,
                ),

                TextFormField(
                  controller:
                      _observerController,
                  decoration:
                      const InputDecoration(
                    labelText:
                        'Observer',
                    border:
                        OutlineInputBorder(),
                  ),
                ),

                const SizedBox(
                  height: 14,
                ),

                const Text(
                  'Behavior / Observation *',
                  style:
                      TextStyle(
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),

                const SizedBox(
                  height: 6,
                ),

                _buildChecklist(
                  options:
                      const [
                    'Bullying',
                    'Misbehavior',
                    'Mental Health',
                    'Personal',
                    'Social',
                    'Academic',
                    'Career',
                    'Others...',
                  ],
                  selected:
                      _behaviors,
                ),

                const SizedBox(
                  height: 10,
                ),

                TextFormField(
                  controller:
                      _observationDetailsController,
                  maxLines: 4,
                  decoration:
                      const InputDecoration(
                    labelText:
                        'Observation Details',
                    border:
                        OutlineInputBorder(),
                  ),
                ),

                const SizedBox(
                  height: 14,
                ),

                const Text(
                  'Intervention',
                  style:
                      TextStyle(
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),

                const SizedBox(
                  height: 6,
                ),

                _buildChecklist(
                  options:
                      const [
                    'Counseling',
                    'Referral',
                    'Consultation',
                    'Placement',
                    'Others...',
                  ],
                  selected:
                      _interventions,
                ),

                const SizedBox(
                  height: 10,
                ),

                TextFormField(
                  controller:
                      _actionTakenController,
                  maxLines: 4,
                  decoration:
                      const InputDecoration(
                    labelText:
                        'Action Taken',
                    border:
                        OutlineInputBorder(),
                  ),
                ),

                const SizedBox(
                  height: 14,
                ),

                const Text(
                  'Remarks',
                  style:
                      TextStyle(
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),

                const SizedBox(
                  height: 6,
                ),

                _buildChecklist(
                  options:
                      const [
                    'Follow-up',
                    'Monitor',
                    'Termination',
                    'Referral',
                    'Others...',
                  ],
                  selected:
                      _remarks,
                ),

                const SizedBox(
                  height: 10,
                ),

                TextFormField(
                  controller:
                      _detailsController,
                  maxLines: 5,
                  decoration:
                      const InputDecoration(
                    labelText:
                        'Note / Details',
                    border:
                        OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed:
              () {
            Navigator.of(
              context,
            ).pop();
          },
          child:
              const Text(
            'Cancel',
          ),
        ),
        FilledButton(
          onPressed:
              _save,
          child:
              Text(
            _editing
                ? 'Save Changes'
                : 'Save',
          ),
        ),
      ],
    );
  }

  // ============================================================
  // CHECKLIST
  // ============================================================

  Widget _buildChecklist({
    required List<String>
        options,
    required Set<String>
        selected,
  }) {
    return Wrap(
      spacing: 6,
      runSpacing: 5,
      children:
          options.map(
        (option) {
          return FilterChip(
            label:
                Text(option),
            selected:
                selected.contains(
              option,
            ),
            onSelected:
                (value) {
              setState(() {
                if (value) {
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
          );
        },
      ).toList(),
    );
  }

  // ============================================================
  // DATE
  // ============================================================

  Future<void> _selectDate()
      async {
    final current =
        _parseDate(
      _dateController.text,
    );

    final selected =
        await showDatePicker(
      context: context,
      initialDate:
          current ??
              DateTime.now(),
      firstDate:
          DateTime(1900),
      lastDate:
          DateTime(2100),
    );

    if (!mounted ||
        selected == null) {
      return;
    }

    _dateController.text =
        _formatDate(
      selected,
    );
  }

  // ============================================================
  // SAVE
  // ============================================================

  void _save() {
    if (!(_formKey
            .currentState
            ?.validate() ??
        false)) {
      return;
    }

    if (_behaviors.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        const SnackBar(
          content: Text(
            'Select at least one behavior/observation.',
          ),
        ),
      );

      return;
    }

    Navigator.of(
      context,
    ).pop(
      <String, Object?>{
        'incidentDate':
            _dateController
                .text
                .trim(),

        'incidentTime':
            _nullIfEmpty(
          _timeController.text,
        ),

        'observer':
            _nullIfEmpty(
          _observerController.text,
        ),

        'behaviorProblem':
            _behaviors.join(
          ', ',
        ),

        'observationDetails':
            _nullIfEmpty(
          _observationDetailsController
              .text,
        ),

        'intervention':
            _interventions.isEmpty
                ? null
                : _interventions.join(
                    ', ',
                  ),

        'actionTaken':
            _nullIfEmpty(
          _actionTakenController.text,
        ),

        'remarks':
            _remarks.isEmpty
                ? null
                : _remarks.join(
                    ', ',
                  ),

        'details':
            _nullIfEmpty(
          _detailsController.text,
        ),
      },
    );
  }

  // ============================================================
  // HELPERS
  // ============================================================

  List<String> _splitChecklist(
    Object? value,
  ) {
    final text =
        value?.toString().trim() ??
            '';

    if (text.isEmpty) {
      return [];
    }

    return text
        .split(',')
        .map(
          (item) =>
              item.trim(),
        )
        .where(
          (item) =>
              item.isNotEmpty,
        )
        .toList();
  }

  String? _nullIfEmpty(
    String value,
  ) {
    final text =
        value.trim();

    return text.isEmpty
        ? null
        : text;
  }

  DateTime? _parseDate(String input) {
    final text = input.trim();
    if (text.isEmpty) return null;

    final iso = DateTime.tryParse(text);
    if (iso != null) {
      return DateTime(iso.year, iso.month, iso.day);
    }

    const months = <String, int>{
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
      'jan': 1,
      'feb': 2,
      'mar': 3,
      'apr': 4,
      'jun': 6,
      'jul': 7,
      'aug': 8,
      'sep': 9,
      'sept': 9,
      'oct': 10,
      'nov': 11,
      'dec': 12,
    };

    final normalized =
        text.replaceAll('.', ' ').replaceAll(',', ' ').trim();

    final monthFirst = RegExp(
      r'^([A-Za-z]+)\s+(\d{1,2})\s+(\d{4})$',
    ).firstMatch(normalized);
    if (monthFirst != null) {
      final month =
          months[monthFirst.group(1)!.toLowerCase()];
      final day = int.tryParse(monthFirst.group(2)!);
      final year = int.tryParse(monthFirst.group(3)!);
      if (month != null && day != null && year != null) {
        return _validDate(year, month, day);
      }
    }

    final dayFirst = RegExp(
      r'^(\d{1,2})\s+([A-Za-z]+)\s+(\d{4})$',
    ).firstMatch(normalized);
    if (dayFirst != null) {
      final day = int.tryParse(dayFirst.group(1)!);
      final month =
          months[dayFirst.group(2)!.toLowerCase()];
      final year = int.tryParse(dayFirst.group(3)!);
      if (month != null && day != null && year != null) {
        return _validDate(year, month, day);
      }
    }

    final numeric = RegExp(
      r'^(\d{1,4})[\/-](\d{1,2})[\/-](\d{1,4})$',
    ).firstMatch(text);
    if (numeric != null) {
      final a = int.tryParse(numeric.group(1)!);
      final b = int.tryParse(numeric.group(2)!);
      final c = int.tryParse(numeric.group(3)!);
      if (a != null && b != null && c != null) {
        if (a >= 1000) return _validDate(a, b, c);
        if (a > 12) return _validDate(c, b, a);
        return _validDate(c, a, b);
      }
    }

    return null;
  }

  DateTime? _validDate(
    int year,
    int month,
    int day,
  ) {
    if (year < 1 ||
        month < 1 ||
        month > 12 ||
        day < 1) {
      return null;
    }

    final date = DateTime(year, month, day);
    if (date.year != year ||
        date.month != month ||
        date.day != day) {
      return null;
    }

    return date;
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
}