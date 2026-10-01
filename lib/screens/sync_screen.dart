import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in_all_platforms/google_sign_in_all_platforms.dart';

import '../models/sync_result.dart';
import '../models/sync_comparison.dart';
import '../services/google_auth_service.dart';
import '../services/google_sheets_service.dart';
import '../services/sync_service.dart';

class SyncScreen extends StatefulWidget {
  const SyncScreen({
    super.key,
    this.focusConflicts = false,
  });

  final bool focusConflicts;

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  final SyncService _syncService = SyncService.instance;

  final GoogleAuthService _googleAuth = GoogleAuthService.instance;

  final GoogleSheetsService _sheetsService = GoogleSheetsService.instance;

  final _conflictReviewKey = GlobalKey();

  Future<void> _revealConflictReview(int count) async {
    if (!mounted || count <= 0) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final target = _conflictReviewKey.currentContext;
    if (target != null && target.mounted) {
      await Scrollable.ensureVisible(target,
          duration: const Duration(milliseconds: 250), alignment: 0);
    }
  }

  Future<void> _reviewDetectedConflicts(int count) async {
    if (!mounted || count <= 0) return;
    await _loadComparison();
    await _revealConflictReview(count);
  }

  SyncResult? _result;

  GoogleSignInCredentials? _credentials;

  bool _loading = true;

  bool _syncing = false;

  bool _authLoading = true;

  bool _settingUpSpreadsheet = false;

  bool _downloading = false;

  bool _comparing = false;

  String? _legacySpreadsheetId;
  bool _reconnecting = false;

  String? _error;

  bool _applyingRemote = false;

  // ============================================================
  // 6.7 — LIVE COMPARISON / CONFLICT UI
  // ============================================================

  SyncComparisonResult? _comparisonResult;

  bool _comparisonLoading = false;

  @override
  void initState() {
    super.initState();

    _initializeScreen();
  }

  // ============================================================
  // INITIALIZATION
  // ============================================================

  Future<void> _initializeScreen() async {
    await Future.wait([
      _loadStatus(),
      _initializeGoogleAuth(),
      _sheetsService.initialize(),
    ]);

    if (!mounted) {
      return;
    }

    if (_credentials != null &&
        _sheetsService.spreadsheetId != null &&
        _sheetsService.spreadsheetId!.trim().isNotEmpty) {
      await _loadComparison();
    }
  }

  // ============================================================
  // LOCAL SYNC STATUS
  // ============================================================

  Future<void> _loadStatus() async {
    try {
      final legacyId = await _syncService.legacyUnownedSpreadsheetId();
      final result = await _syncService.inspectPendingChanges();

      if (!mounted) {
        return;
      }

      setState(() {
        _legacySpreadsheetId = legacyId;
        _result = result;
        _error = result.success ? null : result.message;
        _loading = false;
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
  // 6.7 — LOAD LOCAL / REMOTE COMPARISON
  // ============================================================

  Future<void> _loadComparison() async {
    if (_comparisonLoading || _legacySpreadsheetId != null) {
      return;
    }

    if (_credentials == null) {
      return;
    }

    final spreadsheetId = _sheetsService.spreadsheetId;

    if (spreadsheetId == null || spreadsheetId.trim().isEmpty) {
      return;
    }

    if (mounted) {
      setState(() {
        _comparisonLoading = true;
      });
    }

    try {
      final result = await _syncService.compareRemoteWithLocal();

      if (!mounted) {
        return;
      }

      setState(() {
        _comparisonResult = result;
      });
      if (widget.focusConflicts) {
        await _revealConflictReview(result.conflictCount);
      }
    } catch (e) {
      if (!mounted) {
        return;
      }

      _showMessage(
        'Unable to compare local and remote records.\n$e',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _comparisonLoading = false;
        });
      }
    }
  }

  // ============================================================
  // GOOGLE AUTHENTICATION
  // ============================================================

  Future<void> _reconnectCurrentSpreadsheet() async {
    final candidate = _legacySpreadsheetId;
    if (candidate == null || _reconnecting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(
            'Reconnect Current Spreadsheet — Preserve Local Records'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                    'https://docs.google.com/spreadsheets/d/$candidate/edit'),
                const SizedBox(height: 16),
                const Text(
                  'Learner, teacher, section, school-history and incident records '
                  'will NOT be deleted. Google Sheet records will NOT be modified '
                  'by this reconnect.\n\n'
                  'Old synchronization tracking and baselines will be discarded '
                  'because their spreadsheet ownership cannot be proven.\n\n'
                  'The current spreadsheet will be validated, then local and '
                  'remote records will be compared before any synchronization '
                  'changes are applied. No records will be uploaded or imported. '
                  'Neither dataset will be chosen as authoritative. '
                  'Only identical records may receive fresh synchronization baselines.',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Reconnect and Compare Only')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _reconnecting = true);
    try {
      final result = await _syncService.reconnectCurrentSpreadsheet(
          expectedSpreadsheetId: candidate);
      await _loadStatus();
      if (!mounted) return;
      setState(() => _comparisonResult = result.comparison);
      final comparison = result.comparison;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Spreadsheet Reconnected'),
          content: Text(comparison == null
              ? 'Local and Google Sheet records were not changed. Ownership was '
                  'established, but comparison could not finish. Use Compare Local / '
                  'Remote to retry before synchronizing.\n\n${result.comparisonError}'
              : 'No local or Google Sheet records were changed.\n\n'
                  'Identical: ${comparison.sameCount}\n'
                  'Conflicts: ${comparison.conflictCount}\n'
                  'Local only: ${comparison.localOnlyCount}\n'
                  'Remote only: ${comparison.newRemoteCount}\n\n'
                  'Review the existing conflict list below. Records on only one '
                  'side have not been uploaded, imported or interpreted as deletions. '
                  'Sync Now and Apply Remote remain separate actions.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Close')),
          ],
        ),
      );
    } catch (e) {
      await _loadStatus();
      if (!mounted) return;
      _showMessage(
          'Reconnect could not finish. Local and Google Sheet records '
          'were not changed.\n$e',
          isError: true);
    } finally {
      if (mounted) setState(() => _reconnecting = false);
    }
  }

  Future<void> _initializeGoogleAuth() async {
    try {
      await _googleAuth.initialize();

      final credentials = await _googleAuth.silentSignIn();

      if (!mounted) {
        return;
      }

      setState(() {
        _credentials = credentials;
        _authLoading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _authLoading = false;
        _credentials = null;
      });
    }
  }

  // ============================================================
  // SIGN IN
  // ============================================================

  Future<void> _signInGoogle() async {
    if (_authLoading) {
      return;
    }

    setState(() {
      _authLoading = true;
    });

    try {
      final credentials = await _googleAuth.signIn();

      if (!mounted) {
        return;
      }

      setState(() {
        _credentials = credentials;
      });

      if (credentials == null) {
        _showMessage(
          'Google sign-in was cancelled.',
        );
      } else {
        _showMessage(
          'Google account connected successfully.',
        );
      }
    } catch (e) {
      if (!mounted) {
        return;
      }

      _showMessage(
        'Google sign-in failed.\n$e',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _authLoading = false;
        });
      }
    }
  }

  // ============================================================
  // SIGN OUT
  // ============================================================

  Future<void> _signOutGoogle() async {
    if (_authLoading) {
      return;
    }

    setState(() {
      _authLoading = true;
    });

    try {
      await _googleAuth.signOut();

      if (!mounted) {
        return;
      }

      setState(() {
        _credentials = null;
      });

      _showMessage(
        'Google account disconnected.',
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      _showMessage(
        'Unable to disconnect Google account.\n$e',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _authLoading = false;
        });
      }
    }
  }

  // ============================================================
  // CREATE GOOGLE SPREADSHEET
  // ============================================================

  Future<String?> _chooseAccountForNewSpreadsheet() async {
    if (_credentials == null) {
      return 'current';
    }

    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            'Create New Spreadsheet',
          ),
          content: const Text(
            'Choose which Google account should own the new synchronization spreadsheet.\n\n'
            'You can keep the currently connected account or switch to a different Google account first.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                null,
              ),
              child: const Text(
                'Cancel',
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(
                dialogContext,
                'change',
              ),
              icon: const Icon(
                Icons.switch_account_outlined,
              ),
              label: const Text(
                'Change Google Account',
              ),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(
                dialogContext,
                'current',
              ),
              icon: const Icon(
                Icons.check_circle_outline,
              ),
              label: const Text(
                'Use Current Account',
              ),
            ),
          ],
        );
      },
    );
  }

  Future<bool> _switchGoogleAccountForNewSpreadsheet() async {
    try {
      setState(() {
        _authLoading = true;
      });

      await _googleAuth.signOut();

      if (!mounted) {
        return false;
      }

      setState(() {
        _credentials = null;
      });

      final credentials = await _googleAuth.signIn();

      if (!mounted) {
        return false;
      }

      if (credentials == null) {
        _showMessage(
          'Google account change was cancelled. No new spreadsheet was created.',
        );
        return false;
      }

      setState(() {
        _credentials = credentials;
      });

      return true;
    } catch (e) {
      if (mounted) {
        _showMessage(
          'Unable to change Google account.\n$e',
          isError: true,
        );
      }
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _authLoading = false;
        });
      }
    }
  }

  Future<void> _createSyncSpreadsheet() async {
    if (_settingUpSpreadsheet || _authLoading) {
      return;
    }

    if (_credentials == null) {
      _showMessage(
        'Please sign in with Google first.',
        isError: true,
      );
      return;
    }

    final accountChoice = await _chooseAccountForNewSpreadsheet();

    if (!mounted || accountChoice == null) {
      return;
    }

    if (accountChoice == 'change') {
      final switched = await _switchGoogleAccountForNewSpreadsheet();

      if (!switched || !mounted) {
        return;
      }
    }

    if (_credentials == null) {
      _showMessage(
        'Please sign in with Google before creating the spreadsheet.',
        isError: true,
      );
      return;
    }

    setState(() {
      _settingUpSpreadsheet = true;
    });

    try {
      final spreadsheet = await _sheetsService.createAndInitializeSpreadsheet();

      if (!mounted) {
        return;
      }

      final title = spreadsheet.properties?.title ?? 'Untitled';

      final id = spreadsheet.spreadsheetId ?? '';

      final url = spreadsheet.spreadsheetUrl;

      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text(
              'Google Spreadsheet Ready',
            ),
            content: SizedBox(
              width: 620,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'The synchronization spreadsheet has been created successfully.',
                    ),
                    const SizedBox(
                      height: 16,
                    ),
                    Text(
                      'Title',
                      style: Theme.of(
                        context,
                      ).textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(
                      height: 3,
                    ),
                    SelectableText(
                      title,
                    ),
                    const SizedBox(
                      height: 14,
                    ),
                    Text(
                      'Spreadsheet ID',
                      style: Theme.of(
                        context,
                      ).textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(
                      height: 3,
                    ),
                    SelectableText(
                      id,
                    ),
                    if (url != null && url.trim().isNotEmpty) ...[
                      const SizedBox(
                        height: 14,
                      ),
                      Text(
                        'Spreadsheet URL',
                        style: Theme.of(
                          context,
                        ).textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(
                        height: 3,
                      ),
                      SelectableText(
                        url,
                      ),
                    ],
                    const SizedBox(
                      height: 18,
                    ),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(
                        12,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(
                          10,
                        ),
                      ),
                      child: const Text(
                        'The following worksheets were prepared:\n'
                        '• LEARNERS\n'
                        '• TEACHERS\n'
                        '• SECTIONS\n'
                        '• SCHOOL_HISTORY\n'
                        '• INCIDENTS\n\n'
                        'Your local SQLite records have not been uploaded yet.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
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
    } catch (e) {
      if (!mounted) {
        return;
      }

      _showMessage(
        'Unable to create Google Spreadsheet.\n$e',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _settingUpSpreadsheet = false;
        });
      }
    }
  }

  // ============================================================
  // LOCAL SYNC CHECK
  // ============================================================

  // ============================================================
  // 6.7 — SYNC NOW
  //
  // 1. Upload local pending changes.
  // 2. Compare local and Google Sheets.
  // 3. Apply NEW REMOTE and REMOTE NEWER.
  // 4. Leave LOCAL NEWER and CONFLICT untouched.
  // 5. Refresh the conflict UI.
  // ============================================================

  Future<void> _syncNow() async {
    if (_syncing) {
      return;
    }

    if (_credentials == null) {
      _showMessage(
        'Please sign in with Google first.',
        isError: true,
      );
      return;
    }

    final spreadsheetId = _sheetsService.spreadsheetId;

    if (spreadsheetId == null || spreadsheetId.trim().isEmpty) {
      _showMessage(
        'No Google synchronization spreadsheet has been configured.',
        isError: true,
      );
      return;
    }

    setState(() {
      _syncing = true;
      _error = null;
    });

    try {
      // ------------------------------------------------------------
      // STEP 1 — Upload pending local changes
      // ------------------------------------------------------------
      final uploadResult = await _syncService.syncPendingToGoogleSheets();

      if (!uploadResult.success && !uploadResult.requiresRemoteApply) {
        if (!mounted) {
          return;
        }

        setState(() {
          _result = uploadResult;
          _error = uploadResult.message;
        });

        _showMessage(
          uploadResult.message,
          isError: true,
        );

        await _reviewDetectedConflicts(uploadResult.conflictCount);
        return;
      }

      // ------------------------------------------------------------
      // STEP 2 — Apply safe remote changes
      //
      // applyRemoteChangesToLocal() performs its own comparison
      // and only applies NEW_REMOTE / REMOTE_NEWER records.
      // ------------------------------------------------------------
      final applyResult = await _syncService.applyRemoteChangesToLocal();

      // ------------------------------------------------------------
      // STEP 3 — Compare again after synchronization
      // ------------------------------------------------------------

      // ------------------------------------------------------------
      // STEP 3 — Compare again after synchronization
      // ------------------------------------------------------------
      final finalComparison = await _syncService.compareRemoteWithLocal();

      // ------------------------------------------------------------
      // STEP 4 — Refresh pending-change information
      // ------------------------------------------------------------
      final status = await _syncService.inspectPendingChanges();

      if (!mounted) {
        return;
      }

      setState(() {
        _result = status;
        _comparisonResult = finalComparison;
        _error = null;
      });

      _showMessage(
        'Synchronization completed.\n\n'
        '${uploadResult.message}\n\n'
        '${applyResult.message}\n\n'
        'Current unresolved conflicts: '
        '${finalComparison.conflictCount}',
      );
      await _revealConflictReview(finalComparison.conflictCount);
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = e.toString();
      });

      _showMessage(
        'Synchronization failed.\n$e',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _syncing = false;
        });
      }
    }
  }

  // ============================================================
  // LOCAL SYNC TEST
  // ============================================================

  Future<void> _runLocalSyncTest() async {
    if (_syncing) {
      return;
    }

    setState(() {
      _syncing = true;
    });

    try {
      final output = await _syncService.runLocalSyncTest();

      if (!mounted) {
        return;
      }

      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text(
              'Local Sync Test',
            ),
            content: SizedBox(
              width: 700,
              child: SingleChildScrollView(
                child: SelectableText(
                  output,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                  ),
                ),
              ),
            ),
            actions: [
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

      if (!mounted) {
        return;
      }

      await _loadStatus();
    } catch (e) {
      if (!mounted) {
        return;
      }

      _showMessage(
        'Local sync test failed.\n$e',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _syncing = false;
        });
      }
    }
  }

  // ============================================================
  // GOOGLE SHEETS READ / DOWNLOAD TEST
  //
  // This test ONLY reads the five Google Sheets worksheets.
  // It does NOT modify SQLite.
  // ============================================================

  Future<void> _runGoogleSheetsDownloadTest() async {
    if (_downloading) {
      return;
    }

    if (_credentials == null) {
      _showMessage(
        'Please sign in with Google first.',
        isError: true,
      );
      return;
    }

    if (_sheetsService.spreadsheetId == null ||
        _sheetsService.spreadsheetId!.trim().isEmpty) {
      _showMessage(
        'No Google synchronization spreadsheet has been configured.',
        isError: true,
      );
      return;
    }

    setState(() {
      _downloading = true;
    });

    try {
      final data = await _sheetsService.downloadAllTables();

      if (!mounted) {
        return;
      }

      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text(
              'Google Sheets Read / Download Test',
            ),
            content: SizedBox(
              width: 650,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Successfully read the five synchronization worksheets.',
                    ),
                    const SizedBox(
                      height: 18,
                    ),
                    _downloadTestCountRow(
                      'LEARNERS',
                      data.learners.length,
                      Icons.people_alt_rounded,
                    ),
                    _downloadTestCountRow(
                      'TEACHERS',
                      data.teachers.length,
                      Icons.badge_rounded,
                    ),
                    _downloadTestCountRow(
                      'SECTIONS',
                      data.sections.length,
                      Icons.class_rounded,
                    ),
                    _downloadTestCountRow(
                      'SCHOOL_HISTORY',
                      data.schoolHistory.length,
                      Icons.school_rounded,
                    ),
                    _downloadTestCountRow(
                      'INCIDENTS',
                      data.incidents.length,
                      Icons.event_note_rounded,
                    ),
                    const Divider(
                      height: 24,
                    ),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'TOTAL REMOTE RECORDS',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Text(
                          '${data.total}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(
                      height: 18,
                    ),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(
                        12,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(
                          10,
                        ),
                      ),
                      child: const Text(
                        'This test only reads data from Google Sheets. '
                        'No SQLite records were added, updated, or deleted.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              FilledButton(
                onPressed: () {
                  Navigator.pop(
                    dialogContext,
                  );
                },
                child: const Text('Close'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      _showMessage(
        'Google Sheets download test failed.\n$e',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _downloading = false;
        });
      }
    }
  }

  // ============================================================
  // SQLITE / GOOGLE SHEETS COMPARISON TEST
  //
  // READ ONLY.
  //
  // This method does NOT modify SQLite or Google Sheets.
  // It only compares the two sources using SyncID,
  // Version, and UpdatedAt.
  // ============================================================

  Future<void> _runComparisonTest() async {
    if (_comparing) {
      return;
    }

    if (_credentials == null) {
      _showMessage(
        'Please sign in with Google first.',
        isError: true,
      );
      return;
    }

    final spreadsheetId = _sheetsService.spreadsheetId;

    if (spreadsheetId == null || spreadsheetId.trim().isEmpty) {
      _showMessage(
        'No Google synchronization spreadsheet has been configured.',
        isError: true,
      );
      return;
    }

    setState(() {
      _comparing = true;
    });

    try {
      final result = await _syncService.compareRemoteWithLocal();

      if (!mounted) {
        return;
      }

      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text(
              'SQLite / Google Sheets Comparison',
            ),
            content: SizedBox(
              width: 700,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Comparison completed. No records were modified.',
                    ),
                    const SizedBox(
                      height: 18,
                    ),
                    _comparisonRow(
                      'New Remote',
                      result.newRemoteCount,
                      Icons.cloud_download_outlined,
                    ),
                    _comparisonRow(
                      'Local Only',
                      result.localOnlyCount,
                      Icons.storage_outlined,
                    ),
                    _comparisonRow(
                      'Remote Newer',
                      result.remoteNewerCount,
                      Icons.cloud_sync_outlined,
                    ),
                    _comparisonRow(
                      'Local Newer',
                      result.localNewerCount,
                      Icons.computer_outlined,
                    ),
                    _comparisonRow(
                      'Same',
                      result.sameCount,
                      Icons.check_circle_outline,
                    ),
                    _comparisonRow(
                      'Conflict',
                      result.conflictCount,
                      Icons.warning_amber_outlined,
                    ),
                    const Divider(
                      height: 24,
                    ),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'TOTAL COMPARED',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Text(
                          '${result.total}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(
                      height: 14,
                    ),
                    Text(
                      'This is a read-only comparison test. '
                      'SQLite has not been changed.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
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
    } catch (e) {
      if (!mounted) {
        return;
      }

      _showMessage(
        'Comparison failed.\n$e',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _comparing = false;
        });
      }
    }
  }

  Future<void> _applyRemoteChanges() async {
    if (_applyingRemote) {
      return;
    }

    if (_credentials == null) {
      _showMessage(
        'Please sign in with Google first.',
        isError: true,
      );
      return;
    }

    final spreadsheetId = _sheetsService.spreadsheetId;

    if (spreadsheetId == null || spreadsheetId.trim().isEmpty) {
      _showMessage(
        'No Google synchronization spreadsheet has been configured.',
        isError: true,
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            'Apply Remote Changes?',
          ),
          content: const Text(
            'Changes classified as NEW REMOTE or REMOTE NEWER '
            'will be applied to the local database.\n\n'
            'LOCAL NEWER and CONFLICT records will not be overwritten.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  false,
                );
              },
              child: const Text(
                'Cancel',
              ),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  true,
                );
              },
              child: const Text(
                'Apply',
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    setState(() {
      _applyingRemote = true;
    });

    try {
      final result = await _syncService.applyRemoteChangesToLocal();

      if (!mounted) {
        return;
      }

      if (result.conflicts > 0) {
        await _loadStatus();
        await _reviewDetectedConflicts(result.conflicts);
        return;
      }

      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text(
              result.success ? 'Remote Sync Complete' : 'Remote Sync Failed',
            ),
            content: Text(
              result.message,
            ),
            actions: [
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
    } catch (e) {
      if (!mounted) {
        return;
      }

      _showMessage(
        'Unable to apply remote changes.\n$e',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _applyingRemote = false;
        });
      }
    }
  }

  // ============================================================
  // 6.7 — KEEP LOCAL
  // ============================================================

  Future<void> _keepLocal(
    SyncComparison item,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            'Keep Local Record?',
          ),
          content: const Text(
            'The local version will be uploaded to Google Sheets '
            'and will replace the conflicting remote version.',
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
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  true,
                );
              },
              child: const Text('Keep Local'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    setState(() {
      _syncing = true;
    });

    try {
      final result = await _syncService.resolveConflictKeepLocal(
        tableName: item.tableName,
        syncId: item.syncId,
      );

      if (!mounted) {
        return;
      }

      _showMessage(
        result.message,
        isError: !result.success,
      );

      await _refreshAfterConflict();
    } catch (e) {
      if (!mounted) {
        return;
      }

      _showMessage(
        'Unable to keep local record.\n$e',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _syncing = false;
        });
      }
    }
  }

  // ============================================================
  // 6.7 — USE REMOTE
  // ============================================================

  Future<void> _useRemote(
    SyncComparison item,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            'Use Remote Record?',
          ),
          content: const Text(
            'The local version will be replaced by '
            'the version currently stored in Google Sheets.',
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
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  true,
                );
              },
              child: const Text('Use Remote'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    setState(() {
      _syncing = true;
    });

    try {
      final result = await _syncService.resolveConflictUseRemote(
        tableName: item.tableName,
        syncId: item.syncId,
      );

      if (!mounted) {
        return;
      }

      _showMessage(
        result.message,
        isError: !result.success,
      );

      await _refreshAfterConflict();
    } catch (e) {
      if (!mounted) {
        return;
      }

      _showMessage(
        'Unable to use remote record.\n$e',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _syncing = false;
        });
      }
    }
  }

  // ============================================================
  // REFRESH AFTER CONFLICT RESOLUTION
  // ============================================================

  Future<void> _refreshAfterConflict() async {
    final status = await _syncService.inspectPendingChanges();

    final comparison = await _syncService.compareRemoteWithLocal();

    if (!mounted) {
      return;
    }

    setState(() {
      _result = status;
      _comparisonResult = comparison;
      _error = null;
    });
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
          'Synchronization',
        ),
      ),
      body: SafeArea(
        child: _loading || _reconnecting
            ? const Center(
                child: CircularProgressIndicator(),
              )
            : RefreshIndicator(
                onRefresh: _loadStatus,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(
                    20,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: 900,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildGoogleAccountCard(),
                          const SizedBox(
                            height: 16,
                          ),
                          _buildSpreadsheetCard(),
                          const SizedBox(
                            height: 16,
                          ),
                          _buildStatusCard(),
                          const SizedBox(
                            height: 16,
                          ),
                          _buildPendingCard(),
                          const SizedBox(
                            height: 16,
                          ),
                          Container(
                              key: _conflictReviewKey,
                              child: _buildConflictCard()),
                          const SizedBox(
                            height: 16,
                          ),
                          _buildActionsCard(),
                          const SizedBox(
                            height: 16,
                          ),
                          _buildInformationCard(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _comparisonRow(
    String label,
    int count,
    IconData icon,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 5,
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 19,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(
            width: 10,
          ),
          Expanded(
            child: Text(
              label,
            ),
          ),
          Text(
            '$count',
            style: const TextStyle(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // GOOGLE ACCOUNT CARD
  // ============================================================

  Widget _buildGoogleAccountCard() {
    final connected = _credentials != null;

    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(
          20,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: connected
                    ? colorScheme.primaryContainer
                    : colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(
                  14,
                ),
              ),
              child: Icon(
                connected
                    ? Icons.account_circle_rounded
                    : Icons.account_circle_outlined,
                size: 27,
                color: connected
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(
              width: 14,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    connected
                        ? 'Google Account Connected'
                        : 'Google Account Not Connected',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(
                    height: 4,
                  ),
                  Text(
                    connected
                        ? 'Google authentication is ready for Sheets access.'
                        : 'Sign in before creating or using the synchronization spreadsheet.',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(
              width: 12,
            ),
            _authLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                : connected
                    ? OutlinedButton.icon(
                        onPressed: _signOutGoogle,
                        icon: const Icon(
                          Icons.logout_rounded,
                        ),
                        label: const Text(
                          'Disconnect',
                        ),
                      )
                    : FilledButton.icon(
                        onPressed: _signInGoogle,
                        icon: const Icon(
                          Icons.login_rounded,
                        ),
                        label: const Text(
                          'Sign in with Google',
                        ),
                      ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // COPY SPREADSHEET URL
  // ============================================================

  Future<void> _copySpreadsheetUrl() async {
    final spreadsheetId = _sheetsService.spreadsheetId;

    if (spreadsheetId == null || spreadsheetId.trim().isEmpty) {
      _showMessage(
        'No Google synchronization spreadsheet has been configured.',
        isError: true,
      );
      return;
    }

    try {
      final url = 'https://docs.google.com/spreadsheets/d/'
          '${spreadsheetId.trim()}/edit';

      await Clipboard.setData(
        ClipboardData(text: url),
      );

      if (!mounted) {
        return;
      }

      _showMessage(
        'Google Sheet URL copied to clipboard.',
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      _showMessage(
        'Unable to copy the Google Sheet URL.\n$e',
        isError: true,
      );
    }
  }

  // ============================================================
  // SPREADSHEET CARD
  // ============================================================

  Widget _buildSpreadsheetCard() {
    final spreadsheetId = _sheetsService.spreadsheetId;

    final configured = spreadsheetId != null && spreadsheetId.trim().isNotEmpty;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(
          20,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              configured
                  ? Icons.table_chart_rounded
                  : Icons.add_to_drive_rounded,
              color: Theme.of(context).colorScheme.primary,
              size: 28,
            ),
            const SizedBox(
              width: 12,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    configured
                        ? 'Synchronization Spreadsheet'
                        : 'Google Spreadsheet',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(
                    height: 5,
                  ),
                  Text(
                    configured
                        ? 'A synchronization spreadsheet has been configured for this session.'
                        : 'No synchronization spreadsheet has been configured yet.',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (configured) ...[
                    if (_legacySpreadsheetId != null) ...[
                      const SizedBox(height: 12),
                      const Text(
                          'Legacy synchronization tracking has no proven '
                          'spreadsheet owner. Reconnect to preserve both datasets '
                          'and compare them. Sign in with Google first.'),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _credentials == null ||
                                _syncing ||
                                _applyingRemote ||
                                _comparing ||
                                _downloading ||
                                _comparisonLoading ||
                                _settingUpSpreadsheet
                            ? null
                            : _reconnectCurrentSpreadsheet,
                        icon: const Icon(Icons.link),
                        label: const Text(
                            'Reconnect Current Spreadsheet — Preserve Local Records'),
                      ),
                    ],
                    const SizedBox(
                      height: 10,
                    ),
                    Text(
                      'Spreadsheet ID',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(
                      height: 3,
                    ),
                    SelectableText(
                      spreadsheetId,
                      maxLines: 2,
                    ),
                    const SizedBox(
                      height: 10,
                    ),
                    Text(
                      'Spreadsheet URL',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(
                      height: 3,
                    ),
                    SelectableText(
                      'https://docs.google.com/spreadsheets/d/'
                      '$spreadsheetId/edit',
                      maxLines: 2,
                    ),
                    const SizedBox(
                      height: 8,
                    ),
                    OutlinedButton.icon(
                      onPressed: _copySpreadsheetUrl,
                      icon: const Icon(
                        Icons.copy_rounded,
                      ),
                      label: const Text(
                        'Copy Spreadsheet URL',
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(
              width: 12,
            ),
            if (!configured)
              OutlinedButton.icon(
                onPressed: _credentials == null || _settingUpSpreadsheet
                    ? null
                    : _createSyncSpreadsheet,
                icon: _settingUpSpreadsheet
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(
                        Icons.add_to_drive_rounded,
                      ),
                label: Text(
                  _settingUpSpreadsheet ? 'Creating...' : 'Create Spreadsheet',
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // STATUS CARD
  // ============================================================

  Widget _buildStatusCard() {
    final result = _result;

    final colorScheme = Theme.of(context).colorScheme;

    IconData icon;

    Color color;

    String title;

    String subtitle;

    if (_syncing) {
      icon = Icons.sync_rounded;
      color = colorScheme.primary;
      title = 'Checking...';
      subtitle = 'Inspecting local synchronization changes.';
    } else if (_error != null) {
      icon = Icons.error_outline_rounded;
      color = colorScheme.error;
      title = 'Synchronization Error';
      subtitle = _error!;
    } else if (result?.success == true) {
      icon = Icons.cloud_done_rounded;
      color = colorScheme.primary;
      title = 'Ready';
      subtitle = result?.message ?? 'Synchronization status is available.';
    } else {
      icon = Icons.cloud_off_rounded;
      color = colorScheme.onSurfaceVariant;
      title = 'Not Ready';
      subtitle = 'Synchronization status is unavailable.';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(
          20,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withValues(
                  alpha: 0.12,
                ),
                borderRadius: BorderRadius.circular(
                  14,
                ),
              ),
              child: Icon(
                icon,
                color: color,
                size: 26,
              ),
            ),
            const SizedBox(
              width: 14,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(
                    height: 4,
                  ),
                  Text(
                    subtitle,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // PENDING CHANGES CARD
  // ============================================================

  Widget _buildPendingCard() {
    final result = _result;

    if (result == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            'Synchronization information is unavailable.',
          ),
        ),
      );
    }

    final colorScheme = Theme.of(context).colorScheme;

    final noPending = result.totalPending == 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(
          20,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.pending_actions_rounded,
                  color: colorScheme.primary,
                ),
                const SizedBox(
                  width: 8,
                ),
                Text(
                  'Pending Changes',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: noPending
                        ? colorScheme.primaryContainer
                        : colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(
                      20,
                    ),
                  ),
                  child: Text(
                    '${result.totalPending}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: noPending
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(
              height: 16,
            ),
            _buildCountRow(
              icon: Icons.people_alt_rounded,
              label: 'Learners',
              count: result.learners,
            ),
            _buildCountRow(
              icon: Icons.badge_rounded,
              label: 'Teachers',
              count: result.teachers,
            ),
            _buildCountRow(
              icon: Icons.class_rounded,
              label: 'Sections',
              count: result.sections,
            ),
            _buildCountRow(
              icon: Icons.school_rounded,
              label: 'School History',
              count: result.schoolHistory,
            ),
            _buildCountRow(
              icon: Icons.event_note_rounded,
              label: 'Incidents',
              count: result.incidents,
            ),
            const Divider(
              height: 22,
            ),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Total Pending Changes',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  '${result.totalPending}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // COUNT ROW
  // ============================================================

  Widget _buildCountRow({
    required IconData icon,
    required String label,
    required int count,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 5,
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 19,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(
            width: 10,
          ),
          Expanded(
            child: Text(
              label,
            ),
          ),
          Text(
            '$count',
            style: const TextStyle(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // ACTIONS CARD
  // ============================================================

  // ============================================================
  // 6.7 — CONFLICT CARD
  // ============================================================

  Widget _buildConflictCard() {
    final comparison = _comparisonResult;

    if (_comparisonLoading) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                ),
              ),
              const SizedBox(
                width: 12,
              ),
              Text(
                'Checking Google Sheets for changes...',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      );
    }

    if (comparison == null) {
      return const SizedBox.shrink();
    }

    final conflicts = comparison.comparisons
        .where(
          (item) => item.status == SyncComparisonStatus.conflict,
        )
        .toList();

    if (conflicts.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.green.withValues(
                    alpha: 0.12,
                  ),
                  borderRadius: BorderRadius.circular(
                    12,
                  ),
                ),
                child: Icon(
                  Icons.check_circle_outline_rounded,
                  color: Colors.green.shade700,
                ),
              ),
              const SizedBox(
                width: 14,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'No Unresolved Conflicts',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(
                      height: 4,
                    ),
                    const Text(
                      'Local and Google Sheets records do not currently require a manual conflict decision.',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(
                      12,
                    ),
                  ),
                  child: Icon(
                    Icons.warning_amber_rounded,
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
                const SizedBox(
                  width: 14,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Conflicts Requiring Review',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                      ),
                      const SizedBox(
                        height: 4,
                      ),
                      Text(
                        '${conflicts.length} record(s) require a manual decision.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh comparison',
                  onPressed:
                      _syncing || _comparisonLoading ? null : _loadComparison,
                  icon: const Icon(
                    Icons.refresh_rounded,
                  ),
                ),
              ],
            ),
            const SizedBox(
              height: 16,
            ),
            const Text(
              'A conflict occurs when both local SQLite and Google Sheets contain different changes that cannot safely be resolved automatically.',
            ),
            const SizedBox(
              height: 16,
            ),
            ...conflicts.map(
              _buildConflictItem,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConflictItem(
    SyncComparison item,
  ) {
    return Container(
      margin: const EdgeInsets.only(
        bottom: 16,
      ),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.folder_copy_outlined,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(
                width: 8,
              ),
              Expanded(
                child: Text(
                  _friendlyTableName(
                    item.tableName,
                  ),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(
            height: 6,
          ),
          Text(
            'SyncID: ${item.syncId}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(
            height: 14,
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildConflictVersionPanel(
                  title: 'LOCAL',
                  record: item.localRecord,
                ),
              ),
              const SizedBox(
                width: 12,
              ),
              Expanded(
                child: _buildConflictVersionPanel(
                  title: 'GOOGLE SHEETS',
                  record: item.remoteRecord,
                ),
              ),
            ],
          ),
          const SizedBox(
            height: 16,
          ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _syncing
                      ? null
                      : () => _keepLocal(
                            item,
                          ),
                  icon: const Icon(
                    Icons.computer_outlined,
                  ),
                  label: const Text(
                    'Keep Local',
                  ),
                ),
              ),
              const SizedBox(
                width: 10,
              ),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _syncing
                      ? null
                      : () => _useRemote(
                            item,
                          ),
                  icon: const Icon(
                    Icons.cloud_download_outlined,
                  ),
                  label: const Text(
                    'Use Remote',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildConflictVersionPanel({
    required String title,
    required Map<String, Object?>? record,
  }) {
    final data = record ?? {};

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          const SizedBox(
            height: 8,
          ),
          _conflictDetail(
            'Version',
            data['Version'],
          ),
          _conflictDetail(
            'Updated',
            data['UpdatedAt'],
          ),
          _conflictDetail(
            'Device',
            data['DeviceID'],
          ),
          if (data['LastName'] != null || data['FirstName'] != null)
            _conflictDetail(
              'Name',
              _conflictLearnerName(data),
            ),
          if (data['TeacherName'] != null)
            _conflictDetail(
              'Teacher',
              data['TeacherName'],
            ),
          if (data['SectionName'] != null)
            _conflictDetail(
              'Section',
              data['SectionName'],
            ),
          if (data['SchoolYear'] != null)
            _conflictDetail(
              'School Year',
              data['SchoolYear'],
            ),
        ],
      ),
    );
  }

  Widget _conflictDetail(
    String label,
    Object? value,
  ) {
    final text = value?.toString().trim() ?? '';

    if (text.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(
        bottom: 4,
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
            TextSpan(
              text: text,
            ),
          ],
        ),
      ),
    );
  }

  String _conflictLearnerName(
    Map<String, Object?> row,
  ) {
    final last = row['LastName']?.toString().trim() ?? '';

    final first = row['FirstName']?.toString().trim() ?? '';

    final middle = row['MiddleName']?.toString().trim() ?? '';

    return [
      last,
      first,
      middle,
    ]
        .where(
          (value) => value.isNotEmpty,
        )
        .join(', ');
  }

  String _friendlyTableName(
    String tableName,
  ) {
    switch (tableName) {
      case SyncService.learnersTable:
        return 'Learner Record';

      case SyncService.teachersTable:
        return 'Teacher Record';

      case SyncService.sectionsTable:
        return 'Section Record';

      case SyncService.schoolHistoryTable:
        return 'School History';

      case SyncService.incidentsTable:
        return 'Incident Record';

      default:
        return tableName;
    }
  }

  Widget _buildActionsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(
          20,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Synchronization',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(
              height: 6,
            ),
            Text(
              'Sync Now uploads pending local changes, checks Google Sheets, '
              'and applies safe remote changes. Conflicts remain for manual review.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(
              height: 16,
            ),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: _syncing ? null : _syncNow,
                  icon: _syncing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(
                          Icons.sync_rounded,
                        ),
                  label: Text(
                    _syncing ? 'Checking...' : 'Sync Now',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _syncing ? null : _runLocalSyncTest,
                  icon: const Icon(
                    Icons.bug_report_outlined,
                  ),
                  label: const Text(
                    'Local Sync Test',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _downloading ||
                          _credentials == null ||
                          _sheetsService.spreadsheetId == null
                      ? null
                      : _runGoogleSheetsDownloadTest,
                  icon: _downloading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(
                          Icons.cloud_download_outlined,
                        ),
                  label: Text(
                    _downloading ? 'Reading...' : 'Read / Download Test',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _comparing ||
                          _credentials == null ||
                          _sheetsService.spreadsheetId == null
                      ? null
                      : _runComparisonTest,
                  icon: _comparing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(
                          Icons.compare_arrows_rounded,
                        ),
                  label: Text(
                    _comparing ? 'Comparing...' : 'Compare Local / Remote',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _applyingRemote ||
                          _credentials == null ||
                          _sheetsService.spreadsheetId == null
                      ? null
                      : _applyRemoteChanges,
                  icon: _applyingRemote
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(
                          Icons.cloud_download_rounded,
                        ),
                  label: Text(
                    _applyingRemote ? 'Applying...' : 'Apply Remote Changes',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _credentials == null || _settingUpSpreadsheet
                      ? null
                      : _createSyncSpreadsheet,
                  icon: _settingUpSpreadsheet
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(
                          Icons.add_to_drive_rounded,
                        ),
                  label: Text(
                    _settingUpSpreadsheet
                        ? 'Creating Spreadsheet...'
                        : 'Create Google Spreadsheet',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // INFORMATION CARD
  // ============================================================

  Widget _buildInformationCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(
          20,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(
                  width: 8,
                ),
                Text(
                  'About Synchronization',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(
              height: 10,
            ),
            const Text(
              'The SQLite database remains the primary local storage. '
              'CreatedAt, UpdatedAt, DeviceID, Version, and Deleted '
              'are used as synchronization metadata. Records will '
              'not be marked synchronized until an actual Google '
              'Sheets synchronization is successfully completed.',
            ),
            const SizedBox(
              height: 12,
            ),
            Text(
              'Device: ${_syncService.deviceId}',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(
              height: 5,
            ),
            Text(
              'Google authentication: '
              '${_credentials == null ? 'Not connected' : 'Connected'}',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _downloadTestCountRow(
    String label,
    int count,
    IconData icon,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 5,
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 19,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(
            width: 10,
          ),
          Expanded(
            child: Text(
              label,
            ),
          ),
          Text(
            '$count',
            style: const TextStyle(
              fontWeight: FontWeight.w600,
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
    String message, {
    bool isError = false,
  }) {
    if (!mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(
      context,
    );

    messenger.hideCurrentSnackBar();

    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }
}
