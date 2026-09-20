import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/google_auth_service.dart';
import '../services/google_sheets_service.dart';
import '../services/sync_service.dart';

/// First-run provisioning flow.
///
/// A new installation starts here before the normal application UI.
/// The user must:
///   1. Sign in with a Google account.
///   2. Choose either:
///        - Create a new Google Spreadsheet
///        - Restore from an existing Google Spreadsheet
///
/// The setup-complete flag is stored locally so subsequent launches
/// go directly to the normal application.
class StartupGate extends StatefulWidget {
  const StartupGate({
    super.key,
    required this.child,
  });

  final Widget child;

  static const String setupCompleteKey =
      'holistic_anecdotal_first_run_setup_complete';

  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  bool? _setupComplete;

  @override
  void initState() {
    super.initState();
    _loadSetupState();
  }

  Future<void> _loadSetupState() async {
    final prefs = await SharedPreferences.getInstance();
    final complete =
        prefs.getBool(StartupGate.setupCompleteKey) ?? false;

    if (!mounted) {
      return;
    }

    setState(() {
      _setupComplete = complete;
    });
  }

  Future<void> _finishSetup() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool(
      StartupGate.setupCompleteKey,
      true,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _setupComplete = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_setupComplete == null) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_setupComplete == false) {
      return FirstRunSetupScreen(
        onSetupComplete: _finishSetup,
      );
    }

    return widget.child;
  }
}

class FirstRunSetupScreen extends StatefulWidget {
  const FirstRunSetupScreen({
    super.key,
    required this.onSetupComplete,
  });

  final Future<void> Function() onSetupComplete;

  @override
  State<FirstRunSetupScreen> createState() =>
      _FirstRunSetupScreenState();
}

class _FirstRunSetupScreenState
    extends State<FirstRunSetupScreen> {
  final GoogleAuthService _auth =
      GoogleAuthService.instance;

  final GoogleSheetsService _sheets =
      GoogleSheetsService.instance;

  final SyncService _sync =
      SyncService.instance;

  bool _busy = false;
  String _status = '';

  Future<bool> _ensureGoogleAccount() async {
    if (_auth.isSignedIn) {
      return true;
    }

    final credentials = await _auth.signIn();

    return credentials != null;
  }

  Future<void> _chooseGoogleAccount() async {
    if (_busy) {
      return;
    }

    setState(() {
      _busy = true;
      _status = 'Opening Google sign-in...';
    });

    try {
      // On first run there normally is no saved Google session.
      // Explicitly signing out first also gives the user a clean
      // opportunity to choose a different account if one is cached.
      if (_auth.isSignedIn) {
        await _auth.signOut();
      }

      final credentials = await _auth.signIn();

      if (credentials == null) {
        throw StateError(
          'Google sign-in was cancelled.',
        );
      }

      _showMessage(
        'Google account connected successfully.',
      );
    } catch (e) {
      _showMessage(
        'Unable to sign in with Google.\n$e',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = '';
        });
      }
    }
  }

  Future<void> _startSetup() async {
    if (_busy) {
      return;
    }

    final choice = await showDialog<_SetupChoice>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Set Up This Installation'),
          content: const SizedBox(
            width: 520,
            child: Text(
              'This appears to be the first run of the '
              'Holistic Anecdotal Records application.\n\n'
              'Choose how this installation should be connected:',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                _SetupChoice.cancel,
              ),
              child: const Text('Cancel'),
            ),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(
                dialogContext,
                _SetupChoice.restore,
              ),
              icon: const Icon(
                Icons.cloud_download_rounded,
              ),
              label: const Text(
                'Restore Existing Sheet',
              ),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(
                dialogContext,
                _SetupChoice.create,
              ),
              icon: const Icon(
                Icons.add_to_drive_rounded,
              ),
              label: const Text(
                'Create New Sheet',
              ),
            ),
          ],
        );
      },
    );

    if (choice == null ||
        choice == _SetupChoice.cancel) {
      return;
    }

    if (choice == _SetupChoice.create) {
      await _createNewInstallation();
    } else {
      await _restoreExistingInstallation();
    }
  }

  Future<void> _createNewInstallation() async {
    setState(() {
      _busy = true;
      _status = 'Connecting Google account...';
    });

    try {
      final authenticated =
          await _ensureGoogleAccount();

      if (!authenticated) {
        throw StateError(
          'Google sign-in was cancelled or could not be completed.',
        );
      }

      final accountConfirmed =
          await _confirmAccountForNewSpreadsheet();

      if (!accountConfirmed) {
        return;
      }

      setState(() {
        _status =
            'Creating a new synchronization spreadsheet...';
      });

      final spreadsheet =
          await _sheets.createAndInitializeSpreadsheet();

      final title =
          spreadsheet.properties?.title ??
              'New Google Spreadsheet';

      final url =
          spreadsheet.spreadsheetUrl ??
              '';

      await _showSuccessDialog(
        title: 'New Installation Ready',
        message:
            'A new synchronization spreadsheet was created.\n\n'
            'Spreadsheet: $title\n\n'
            'The local database is empty and ready for use.',
        url: url,
      );

      await widget.onSetupComplete();
    } catch (e) {
      _showMessage(
        'Initial setup could not be completed.\n$e',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = '';
        });
      }
    }
  }

  Future<bool> _confirmAccountForNewSpreadsheet() async {
    final choice = await showDialog<_AccountChoice>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            'Create Spreadsheet With This Account?',
          ),
          content: const SizedBox(
            width: 520,
            child: Text(
              'The new synchronization spreadsheet will be created '
              'under the currently signed-in Google account.\n\n'
              'You can change the Google account before creating the '
              'spreadsheet.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                _AccountChoice.cancel,
              ),
              child: const Text('Cancel'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                _AccountChoice.change,
              ),
              child: const Text(
                'Change Google Account',
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                _AccountChoice.useCurrent,
              ),
              child: const Text(
                'Use This Account',
              ),
            ),
          ],
        );
      },
    );

    if (choice == null ||
        choice == _AccountChoice.cancel) {
      return false;
    }

    if (choice == _AccountChoice.change) {
      await _chooseGoogleAccount();

      if (!mounted || !_auth.isSignedIn) {
        return false;
      }

      final confirm = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text(
              'Use This Google Account?',
            ),
            content: const Text(
              'The new spreadsheet will be created with the '
              'Google account you just selected.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(
                  dialogContext,
                  false,
                ),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(
                  dialogContext,
                  true,
                ),
                child: const Text(
                  'Use This Account',
                ),
              ),
            ],
          );
        },
      );

      return confirm == true;
    }

    return true;
  }

  Future<void> _restoreExistingInstallation() async {
    setState(() {
      _busy = true;
      _status = 'Connecting Google account...';
    });

    try {
      final authenticated =
          await _ensureGoogleAccount();

      if (!authenticated) {
        throw StateError(
          'Google sign-in was cancelled or could not be completed.',
        );
      }

      final url = await _askForSpreadsheetUrl();

      if (url == null ||
          url.trim().isEmpty) {
        return;
      }

      setState(() {
        _status =
            'Validating the Google spreadsheet...';
      });

      final result = await _sync.restoreFromSpreadsheet(url.trim());

      await _showSuccessDialog(
        title: 'Restore Complete',
        message: result.message,
        url: 'https://docs.google.com/spreadsheets/d/'
            '${result.spreadsheetId}/edit',
      );

      await widget.onSetupComplete();
    } catch (e) {
      _showMessage(
        'The existing spreadsheet could not be restored.\n$e',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = '';
        });
      }
    }
  }

  Future<String?> _askForSpreadsheetUrl() async {
    final controller =
        TextEditingController();

    try {
      return await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text(
              'Restore Existing Google Spreadsheet',
            ),
            content: SizedBox(
              width: 620,
              child: TextField(
                controller: controller,
                autofocus: true,
                keyboardType:
                    TextInputType.url,
                decoration:
                    const InputDecoration(
                  labelText:
                      'Google Sheet URL or Spreadsheet ID',
                  hintText:
                      'https://docs.google.com/spreadsheets/d/...',
                  border:
                      OutlineInputBorder(),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.pop(
                  dialogContext,
                ),
                child:
                    const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final value =
                      controller.text.trim();

                  if (value.isEmpty) {
                    return;
                  }

                  Navigator.pop(
                    dialogContext,
                    value,
                  );
                },
                child:
                    const Text('Continue'),
              ),
            ],
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _showSuccessDialog({
    required String title,
    required String message,
    required String url,
  }) async {
    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(
                Icons.check_circle_outline_rounded,
                color:
                    Theme.of(context)
                        .colorScheme
                        .primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title),
              ),
            ],
          ),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                mainAxisSize:
                    MainAxisSize.min,
                children: [
                  Text(message),
                  if (url.trim().isNotEmpty) ...[
                    const SizedBox(height: 18),
                    const Text(
                      'Google Spreadsheet URL',
                      style: TextStyle(
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 5),
                    SelectableText(url),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext),
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );
  }

  void _showMessage(
    String message, {
    bool isError = false,
  }) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            isError
                ? Theme.of(context)
                    .colorScheme
                    .error
                : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(
              maxWidth: 760,
            ),
            child: Padding(
              padding:
                  const EdgeInsets.all(28),
              child: Card(
                child: Padding(
                  padding:
                      const EdgeInsets.all(30),
                  child: Column(
                    mainAxisSize:
                        MainAxisSize.min,
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.school_rounded,
                            size: 42,
                            color:
                                Theme.of(context)
                                    .colorScheme
                                    .primary,
                          ),
                          const SizedBox(
                            width: 14,
                          ),
                          const Expanded(
                            child: Text(
                              'Holistic Educational '
                              'Anecdotal Record & '
                              'Tracking System',
                              style: TextStyle(
                                fontSize: 25,
                                fontWeight:
                                    FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Welcome. This installation needs to be '
                        'connected to a Google account before the '
                        'application can be used.',
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'You can start with a completely new '
                        'Google Spreadsheet, or restore an existing '
                        'synchronized spreadsheet onto this device.',
                      ),
                      const SizedBox(height: 24),
                      if (_status.isNotEmpty) ...[
                        Row(
                          children: [
                            const SizedBox(
                              width: 20,
                              height: 20,
                              child:
                                  CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            ),
                            const SizedBox(
                              width: 12,
                            ),
                            Expanded(
                              child:
                                  Text(_status),
                            ),
                          ],
                        ),
                        const SizedBox(
                          height: 20,
                        ),
                      ],
                      Row(
                        children: [
                          Expanded(
                            child:
                                OutlinedButton.icon(
                              onPressed:
                                  _busy
                                      ? null
                                      : _chooseGoogleAccount,
                              icon:
                                  const Icon(
                                Icons
                                    .account_circle_outlined,
                              ),
                              label:
                                  const Text(
                                'Choose Google Account',
                              ),
                            ),
                          ),
                          const SizedBox(
                            width: 12,
                          ),
                          Expanded(
                            child:
                                FilledButton.icon(
                              onPressed:
                                  _busy
                                      ? null
                                      : _startSetup,
                              icon:
                                  const Icon(
                                Icons
                                    .arrow_forward_rounded,
                              ),
                              label:
                                  const Text(
                                'Start Setup',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'The local SQLite database is created '
                        'automatically for this installation. '
                        'Restoring an existing spreadsheet replaces '
                        'the local database with the downloaded '
                        'synchronized records.',
                        style: TextStyle(
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
    );
  }
}

enum _SetupChoice {
  create,
  restore,
  cancel,
}

enum _AccountChoice {
  useCurrent,
  change,
  cancel,
}
