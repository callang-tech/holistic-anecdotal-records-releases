import 'package:flutter/material.dart';

import '../database/app_database.dart';
import '../services/google_auth_service.dart';
import '../services/google_sheets_service.dart';
import '../services/password_service.dart';
import '../services/school_settings_service.dart';
import '../services/sync_service.dart';
import '../widgets/app_shell.dart';
import '../widgets/image_personalization_card.dart';
import '../widgets/sync_status_bar.dart';
import '../widgets/data_security_card.dart';

class AdminToolsScreen extends StatefulWidget {
  const AdminToolsScreen({super.key});

  @override
  State<AdminToolsScreen> createState() => _AdminToolsScreenState();
}

class _AdminToolsScreenState extends State<AdminToolsScreen> {
  final AppDatabase _appDatabase = AppDatabase.instance;
  final SyncService _syncService = SyncService.instance;
  final GoogleAuthService _authService = GoogleAuthService.instance;
  final GoogleSheetsService _sheetsService = GoogleSheetsService.instance;

  bool _busy = false;
  String? _busyMessage;

  Future<void> _ensureGoogleAuthentication() async {
    if (_authService.isSignedIn) return;

    final credentials = await _authService.signIn();
    if (credentials == null) {
      throw StateError(
        'Google authentication was cancelled or could not be completed.',
      );
    }
  }

  Future<void> _runOperation(
    String message,
    Future<void> Function() operation, {
    String? successMessage,
  }) async {
    if (_busy) return;

    setState(() {
      _busy = true;
      _busyMessage = message;
    });

    try {
      await operation();

      if (!mounted) return;

      if (successMessage != null) {
        await _showMessage(
          title: 'Completed',
          message: successMessage,
        );
      }
    } catch (e) {
      if (!mounted) return;

      await _showMessage(
        title: 'Unable to Complete Operation',
        message: _friendlyError(e),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyMessage = null;
        });
      }
    }
  }

  Future<void> _startFreshDatabase() async {
    final confirmed = await _confirm(
      title: 'Start Fresh Database?',
      message: 'This permanently removes the current local database from this '
          'device. Learners, teachers, sections, school history, and '
          'anecdotal records stored locally will be removed.\n\n'
          'The configured Google Sheet will NOT be deleted or changed.',
      confirmText: 'Start Fresh',
    );

    if (!confirmed) return;

    await _runOperation(
      'Starting fresh database...',
      () async {
        await _appDatabase.resetDatabase();
        await _syncService.clearSyncState();
      },
      successMessage:
          'The local database was reset successfully. The configured '
          'Google Sheet was left unchanged.',
    );
  }

  Future<void> _createNewSpreadsheet() async {
    final confirmed = await _confirm(
      title: 'Create New Spreadsheet?',
      message: 'A new Google Spreadsheet will be created for synchronization. '
          'The current local database will remain unchanged.\n\n'
          'The new spreadsheet becomes the configured synchronization '
          'spreadsheet.',
      confirmText: 'Create Spreadsheet',
    );

    if (!confirmed) return;

    await _runOperation(
      'Creating new Google Spreadsheet...',
      () async {
        await _ensureGoogleAuthentication();
        await _sheetsService.createAndInitializeSpreadsheet();
      },
      successMessage:
          'A new synchronization spreadsheet was created successfully.',
    );
  }

  Future<void> _restoreExistingSpreadsheet() async {
    final controller = TextEditingController();

    try {
      final url = await showDialog<String>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text(
              'Restore from Google Spreadsheet',
            ),
            content: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Enter the Google Spreadsheet URL or Spreadsheet ID. '
                    'The existing local database will be replaced only after '
                    'the spreadsheet is successfully validated and downloaded.',
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Google Spreadsheet URL or ID',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final value = controller.text.trim();
                  if (value.isEmpty) return;
                  Navigator.pop(dialogContext, value);
                },
                child: const Text('Restore'),
              ),
            ],
          );
        },
      );

      if (url == null || url.trim().isEmpty) return;

      final confirmed = await _confirm(
        title: 'Replace Local Database?',
        message: 'The records in the selected Google Spreadsheet will replace '
            'the current local database on this device.\n\n'
            'Continue only if this is the synchronization spreadsheet you '
            'want to restore.',
        confirmText: 'Restore',
      );

      if (!confirmed) return;

      await _runOperation(
        'Restoring database from Google Spreadsheet...',
        () async {
          await _ensureGoogleAuthentication();

          final result = await _syncService.restoreFromSpreadsheet(url);
          if (!mounted) return;
          await _showMessage(
            title: 'Restore Complete',
            message: result.message,
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _changePassword() async {
    final currentController = TextEditingController();
    final newController = TextEditingController();
    final confirmController = TextEditingController();

    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Change Password'),
            content: SizedBox(
              width: 430,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: currentController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Current Password',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: newController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'New Password',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: confirmController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Confirm New Password',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  final currentPassword = currentController.text;
                  final newPassword = newController.text;
                  final confirmation = confirmController.text;

                  final valid = await PasswordService().verify(
                    currentPassword,
                  );

                  if (!dialogContext.mounted) return;

                  if (!valid) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Current password is incorrect.',
                        ),
                      ),
                    );
                    return;
                  }

                  if (newPassword.isEmpty) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'New password cannot be empty.',
                        ),
                      ),
                    );
                    return;
                  }

                  if (newPassword != confirmation) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'New passwords do not match.',
                        ),
                      ),
                    );
                    return;
                  }

                  await PasswordService().setPassword(
                    newPassword,
                  );

                  if (!dialogContext.mounted) return;
                  Navigator.pop(dialogContext);

                  if (!mounted) return;
                  await _showMessage(
                    title: 'Password Changed',
                    message:
                        'The application password was changed successfully.',
                  );
                },
                child: const Text('Change Password'),
              ),
            ],
          );
        },
      );
    } finally {
      currentController.dispose();
      newController.dispose();
      confirmController.dispose();
    }
  }

  Future<void> _changeSchoolName() async {
    final settings = SchoolSettingsService.instance;
    final currentName = await settings.getSchoolName();

    if (!mounted) return;

    final controller = TextEditingController(
      text: currentName,
    );

    try {
      final newName = await showDialog<String>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Change School Name'),
            content: SizedBox(
              width: 500,
              child: TextField(
                controller: controller,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'School Name',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (value) {
                  final name = value.trim();
                  if (name.isNotEmpty) {
                    Navigator.pop(dialogContext, name);
                  }
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final name = controller.text.trim();
                  if (name.isEmpty) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'School name cannot be empty.',
                        ),
                      ),
                    );
                    return;
                  }

                  Navigator.pop(dialogContext, name);
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      );

      if (newName == null || newName.trim().isEmpty) {
        return;
      }

      await settings.setSchoolName(newName);

      if (!mounted) return;

      await _showMessage(
        title: 'School Name Changed',
        message: 'The default school name is now "${newName.trim()}". '
            'New learner school-history entries will use this name. '
            'Existing learner records are unchanged.',
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _openSynchronization() async {
    await Navigator.pushNamed(
      context,
      '/sync',
    );
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmText,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 500,
            child: Text(message),
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
              child: Text(confirmText),
            ),
          ],
        );
      },
    );

    return result ?? false;
  }

  Future<void> _showMessage({
    required String title,
    required String message,
  }) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 500,
            child: Text(message),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  String _friendlyError(Object error) {
    var text = error.toString().trim();

    const prefixes = <String>[
      'Bad state: ',
      'StateError: ',
      'Exception: ',
    ];

    for (final prefix in prefixes) {
      if (text.startsWith(prefix)) {
        text = text.substring(prefix.length).trim();
      }
    }

    return text;
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Admin',
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                20,
                20,
                20,
                24,
              ),
              children: [
                _buildAdminCard(),
                const SizedBox(height: 16),
                const DataSecurityCard(),
                const SizedBox(height: 16),
                const ImagePersonalizationCard(),
              ],
            ),
          ),
          const SyncStatusBar(),
        ],
      ),
    );
  }

  Widget _buildAdminCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.admin_panel_settings_rounded),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'DATABASE & SYNCHRONIZATION',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Administrative database provisioning, Google Spreadsheet '
              'configuration, restoration, and synchronization.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 18),
            _action(
              icon: Icons.delete_sweep_rounded,
              label: 'Start Fresh Database',
              description:
                  'Remove all local records and create an empty database.',
              onPressed: _busy ? null : _startFreshDatabase,
              destructive: true,
            ),
            const SizedBox(height: 10),
            _action(
              icon: Icons.add_to_drive_rounded,
              label: 'Create New Spreadsheet',
              description: 'Create a new empty synchronization spreadsheet.',
              onPressed: _busy ? null : _createNewSpreadsheet,
            ),
            const SizedBox(height: 10),
            _action(
              icon: Icons.download_rounded,
              label: 'Restore from Google Spreadsheet',
              description:
                  'Replace the local database using an existing synchronized spreadsheet.',
              onPressed: _busy ? null : _restoreExistingSpreadsheet,
            ),
            const SizedBox(height: 10),
            _action(
              icon: Icons.sync_rounded,
              label: 'Open Synchronization',
              description:
                  'Push, pull, compare, and resolve synchronization conflicts.',
              onPressed: _busy ? null : _openSynchronization,
            ),
            const SizedBox(height: 10),
            _action(
              icon: Icons.school_rounded,
              label: 'Change School Name',
              description:
                  'Change the default school name used for new learner records.',
              onPressed: _busy ? null : _changeSchoolName,
            ),
            const SizedBox(height: 10),
            _action(
              icon: Icons.lock_reset_rounded,
              label: 'Change Password',
              description:
                  'Change the password used to access this application.',
              onPressed: _busy ? null : _changePassword,
            ),
            if (_busy) ...[
              const SizedBox(height: 18),
              const Divider(),
              const SizedBox(height: 12),
              Row(
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _busyMessage ?? 'Processing...',
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _action({
    required IconData icon,
    required String label,
    required String description,
    required VoidCallback? onPressed,
    bool destructive = false,
  }) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
        alignment: Alignment.centerLeft,
      ),
      child: Row(
        children: [
          Icon(icon, size: 21),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: destructive
                        ? Theme.of(context).colorScheme.error
                        : null,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(
            Icons.chevron_right_rounded,
            size: 21,
          ),
        ],
      ),
    );
  }
}
