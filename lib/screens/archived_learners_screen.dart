import 'package:flutter/material.dart';

import '../database/database_repository.dart';
import 'view_screen.dart';

class ArchivedLearnersScreen extends StatefulWidget {
  const ArchivedLearnersScreen({
    super.key,
  });

  @override
  State<ArchivedLearnersScreen> createState() =>
      _ArchivedLearnersScreenState();
}

class _ArchivedLearnersScreenState
    extends State<ArchivedLearnersScreen> {
  final DatabaseRepository _repository =
      DatabaseRepository.instance;

  List<Map<String, Object?>> _learners = [];

  bool _loading = true;

  @override
  void initState() {
    super.initState();

    _loadArchivedLearners();
  }

  // ============================================================
  // LOAD ARCHIVED LEARNERS
  // ============================================================

  Future<void> _loadArchivedLearners() async {
    if (mounted) {
      setState(() {
        _loading = true;
      });
    }

    try {
      final learners =
          await _repository.getArchivedLearners();

      if (!mounted) {
        return;
      }

      setState(() {
        _learners = learners;
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
        'Unable to load archived learners.\n$e',
        isError: true,
      );
    }
  }

  // ============================================================
  // VIEW LEARNER
  // ============================================================

  Future<void> _viewLearner(
    int learnerId,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const ViewScreen(),
        settings: RouteSettings(
          arguments: learnerId,
        ),
      ),
    );
  }

  // ============================================================
  // RESTORE LEARNER
  // ============================================================

  Future<void> _restoreLearner(
    Map<String, Object?> learner,
  ) async {
    final learnerId =
        _asInt(learner['LearnerID']);

    if (learnerId == null) {
      _showMessage(
        'Unable to determine the learner record ID.',
        isError: true,
      );
      return;
    }

    final name =
        _displayName(learner);

    final confirmed =
        await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            'Restore Learner?',
          ),
          content: Text(
            'Restore $name to the active learner list?\n\n'
            'The learner record and its associated history will be '
            'retained.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(
                  dialogContext,
                ).pop(false);
              },
              child: const Text(
                'Cancel',
              ),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(
                  dialogContext,
                ).pop(true);
              },
              icon: const Icon(
                Icons.restore_rounded,
              ),
              label: const Text(
                'Restore',
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
      final affected =
          await _repository.restoreLearner(
        learnerId: learnerId,
      );

      if (!mounted) {
        return;
      }

      if (affected == 0) {
        _showMessage(
          'The learner record could not be restored.',
          isError: true,
        );
        return;
      }

      await _loadArchivedLearners();

      if (!mounted) {
        return;
      }

      _showMessage(
        '$name has been restored successfully.',
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      _showMessage(
        'Unable to restore learner.\n$e',
        isError: true,
      );
    }
  }

  // ============================================================
  // PERMANENT DELETE
  // ============================================================

  Future<void> _permanentlyDeleteLearner(
    Map<String, Object?> learner,
  ) async {
    final learnerId =
        _asInt(
      learner['LearnerID'],
    );

    if (learnerId == null) {
      _showMessage(
        'Unable to determine the learner record ID.',
        isError: true,
      );
      return;
    }

    final name =
        _displayName(learner);

    final confirmed =
        await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            'Permanently Delete Learner?',
          ),
          content: Text(
            'You are about to permanently delete:\n\n'
            '$name\n\n'
            'This will mark the learner for permanent deletion. '
            'The record will no longer be available as an archived '
            'learner and cannot be restored through this screen.\n\n'
            'The deletion will be synchronized to Google Sheets '
            'before the record is physically removed from storage.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(
                  dialogContext,
                ).pop(false);
              },
              child: const Text(
                'Cancel',
              ),
            ),
            FilledButton.icon(
              style:
                  FilledButton.styleFrom(
                backgroundColor:
                    Theme.of(context)
                        .colorScheme
                        .error,
                foregroundColor:
                    Theme.of(context)
                        .colorScheme
                        .onError,
              ),
              onPressed: () {
                Navigator.of(
                  dialogContext,
                ).pop(true);
              },
              icon: const Icon(
                Icons.delete_forever_rounded,
              ),
              label: const Text(
                'Permanently Delete',
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
      final affected =
          await _repository
              .permanentlyDeleteLearner(
        learnerId: learnerId,
      );

      if (!mounted) {
        return;
      }

      if (affected == 0) {
        _showMessage(
          'The learner record could not be marked for permanent deletion.',
          isError: true,
        );
        return;
      }

      await _loadArchivedLearners();

      if (!mounted) {
        return;
      }

      _showMessage(
        '$name has been marked for permanent deletion.',
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      _showMessage(
        'Unable to permanently delete learner.\n$e',
        isError: true,
      );
    }
  }


  // ============================================================
  // DISPLAY HELPERS
  // ============================================================

  String _displayName(
    Map<String, Object?> learner,
  ) {
    final lastName =
        _text(learner['LastName']);

    final firstName =
        _text(learner['FirstName']);

    final middleName =
        _text(learner['MiddleName']);

    final parts = <String>[
      if (lastName.isNotEmpty) lastName,
      if (firstName.isNotEmpty) firstName,
      if (middleName.isNotEmpty) middleName,
    ];

    return parts.isEmpty
        ? 'Unnamed learner'
        : parts.join(', ');
  }

  String _schoolSummary(
    Map<String, Object?> learner,
  ) {
    final grade =
        _text(learner['GradeLevel']);

    final section =
        _text(learner['SectionID']);

    final municipality =
        _text(learner['TownMunicipality']);

    final details = <String>[
      if (grade.isNotEmpty)
        'Grade $grade',
      if (section.isNotEmpty)
        'Section $section',
      if (municipality.isNotEmpty)
        municipality,
    ];

    return details.isEmpty
        ? 'School information not available'
        : details.join(' • ');
  }

  String _archivedDate(
    Map<String, Object?> learner,
  ) {
    final value =
        _text(learner['UpdatedAt']);

    if (value.isEmpty) {
      return 'Archived date not available';
    }

    final parsed =
        DateTime.tryParse(value);

    if (parsed == null) {
      return value;
    }

    final local =
        parsed.toLocal();

    return 'Archived ${_twoDigits(local.month)}/'
        '${_twoDigits(local.day)}/'
        '${local.year}';
  }

  String _text(
    Object? value,
  ) {
    return value
            ?.toString()
            .trim() ??
        '';
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

  String _twoDigits(
    int value,
  ) {
    return value
        .toString()
        .padLeft(
          2,
          '0',
        );
  }

  // ============================================================
  // MESSAGE
  // ============================================================

  void _showMessage(
    String message, {
    bool isError = false,
  }) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
        .hideCurrentSnackBar();

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(message),
        behavior:
            SnackBarBehavior.floating,
        duration:
            const Duration(
          seconds: 4,
        ),
      ),
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
        title: const Text(
          'Archived Learners',
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed:
                _loading
                    ? null
                    : _loadArchivedLearners,
            icon: const Icon(
              Icons.refresh_rounded,
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child:
                  CircularProgressIndicator(),
            )
          : _buildBody(),
    );
  }

  // ============================================================
  // BODY
  // ============================================================

  Widget _buildBody() {
    if (_learners.isEmpty) {
      return _buildEmptyState();
    }

    return ListView.builder(
      padding:
          const EdgeInsets.fromLTRB(
        16,
        16,
        16,
        24,
      ),
      itemCount:
          _learners.length,
      itemBuilder:
          (context, index) {
        final learner =
            _learners[index];

        final learnerId =
            _asInt(
          learner['LearnerID'],
        );

        return Card(
          margin:
              const EdgeInsets.only(
            bottom: 10,
          ),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 8,
            ),
            leading: CircleAvatar(
              child: Text(
                _text(
                  learner[
                      'FirstName'],
                ).isNotEmpty
                    ? _text(
                        learner[
                            'FirstName'],
                      )[0]
                        .toUpperCase()
                    : '?',
              ),
            ),
            title: Text(
              _displayName(
                learner,
              ),
              style:
                  const TextStyle(
                fontWeight:
                    FontWeight.bold,
              ),
            ),
            subtitle:
                Padding(
              padding:
                  const EdgeInsets.only(
                top: 4,
              ),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    _text(
                          learner[
                              'LearnerReferenceNumber'],
                        ).isEmpty
                        ? 'LRN: Not provided'
                        : 'LRN: ${_text(learner['LearnerReferenceNumber'])}',
                  ),
                  const SizedBox(
                    height: 2,
                  ),
                  Text(
                    _schoolSummary(
                      learner,
                    ),
                    maxLines: 1,
                    overflow:
                        TextOverflow.ellipsis,
                  ),
                  const SizedBox(
                    height: 2,
                  ),
                  Text(
                    _archivedDate(
                      learner,
                    ),
                  ),
                ],
              ),
            ),
            isThreeLine:
                true,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton.icon(
                  onPressed:
                      learnerId == null
                          ? null
                          : () =>
                              _restoreLearner(
                                learner,
                              ),
                  icon: const Icon(
                    Icons.restore_rounded,
                    size: 18,
                  ),
                  label: const Text(
                    'Restore',
                  ),
                ),

                const SizedBox(width: 8),

                OutlinedButton.icon(
                  style:
                      OutlinedButton.styleFrom(
                    foregroundColor:
                        Theme.of(context)
                            .colorScheme
                            .error,
                    side: BorderSide(
                      color:
                          Theme.of(context)
                              .colorScheme
                              .error,
                    ),
                  ),
                  onPressed:
                      learnerId == null
                          ? null
                          : () =>
                              _permanentlyDeleteLearner(
                                learner,
                              ),
                  icon: const Icon(
                    Icons.delete_forever_rounded,
                    size: 18,
                  ),
                  label: const Text(
                    'Permanently Delete',
                  ),
                ),
              ],
            ),
            onTap:
                learnerId == null
                    ? null
                    : () =>
                        _viewLearner(
                          learnerId,
                        ),
          ),
        );
      },
    );
  }

  // ============================================================
  // EMPTY STATE
  // ============================================================

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding:
            const EdgeInsets.all(32),
        child: Column(
          mainAxisSize:
              MainAxisSize.min,
          children: [
            Icon(
              Icons.archive_outlined,
              size: 72,
              color: Theme.of(context)
                  .colorScheme
                  .outline,
            ),
            const SizedBox(
              height: 16,
            ),
            Text(
              'No Archived Learners',
              style:
                  Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(
                    fontWeight:
                        FontWeight.bold,
                  ),
            ),
            const SizedBox(
              height: 8,
            ),
            Text(
              'Learners that are archived '
              'will appear here.',
              textAlign:
                  TextAlign.center,
              style:
                  Theme.of(context)
                      .textTheme
                      .bodyMedium,
            ),
            const SizedBox(
              height: 20,
            ),
            OutlinedButton.icon(
              onPressed:
                  _loadArchivedLearners,
              icon: const Icon(
                Icons.refresh_rounded,
              ),
              label:
                  const Text(
                'Refresh',
              ),
            ),
          ],
        ),
      ),
    );
  }
}