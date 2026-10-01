import 'package:flutter/material.dart';

import '../services/google_auth_service.dart';
import '../services/sync_service.dart';
import '../screens/sync_screen.dart';
import 'conflict_review_navigation.dart';

class SyncStatusBar extends StatefulWidget {
  const SyncStatusBar({
    super.key,
  });

  @override
  State<SyncStatusBar> createState() => _SyncStatusBarState();
}

class _SyncStatusBarState extends State<SyncStatusBar> {
  final SyncService _syncService = SyncService.instance;

  final GoogleAuthService _googleAuth = GoogleAuthService.instance;

  final _conflictNavigation = ConflictReviewNavigation();

  Future<void> _openConflictReview(int count) => _conflictNavigation.show(
        conflictCount: count,
        mounted: () => mounted,
        open: () async {
          await Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => const SyncScreen(focusConflicts: true),
          ));
        },
        refresh: _load,
      );

  int _pending = 0;

  int _conflicts = 0;

  bool _syncing = false;

  @override
  void initState() {
    super.initState();

    _load();
  }

  // ============================================================
  // LOAD LOCAL SYNC STATUS
  // ============================================================

  Future<void> _load() async {
    try {
      final pending = await _syncService.getTotalPendingCount();

      final conflicts = await _syncService.getLastKnownConflictCount();

      if (!mounted) {
        return;
      }

      setState(() {
        _pending = pending;
        _conflicts = conflicts;
      });
    } catch (_) {
      // Keep the status bar usable even if
      // the sync status cannot be loaded.
    }
  }

  // ============================================================
  // ENSURE GOOGLE AUTHENTICATION
  // ============================================================

  Future<bool> _ensureGoogleAuthentication() async {
    try {
      await _googleAuth.initialize();
    } catch (e) {
      if (!mounted) {
        return false;
      }

      _showMessage(
        'Unable to initialize Google authentication.\n$e',
        isError: true,
      );

      return false;
    }

    // ----------------------------------------------------------
    // FIRST: TRY SILENT SIGN-IN
    // ----------------------------------------------------------

    try {
      final credentials = await _googleAuth.silentSignIn();

      if (credentials != null) {
        return true;
      }
    } catch (_) {
      // Silent sign-in failed.
      //
      // This is not treated as a fatal error because
      // we will immediately open the normal sign-in
      // window below.
    }

    // ----------------------------------------------------------
    // NO EXISTING SESSION
    // OPEN GOOGLE SIGN-IN WINDOW
    // ----------------------------------------------------------

    if (!mounted) {
      return false;
    }

    _showMessage(
      'Google sign-in is required. '
      'Please complete the sign-in window.',
    );

    try {
      final credentials = await _googleAuth.signIn();

      if (credentials == null) {
        if (mounted) {
          _showMessage(
            'Google sign-in was cancelled.',
            isError: true,
          );
        }

        return false;
      }

      return true;
    } catch (e) {
      if (!mounted) {
        return false;
      }

      _showMessage(
        'Google sign-in failed.\n$e',
        isError: true,
      );

      return false;
    }
  }

  // ============================================================
  // SYNC NOW
  // ============================================================

  Future<void> _syncNow() async {
    if (_syncing) {
      return;
    }

    setState(() {
      _syncing = true;
    });

    try {
      // --------------------------------------------------------
      // STEP 0 — ENSURE GOOGLE AUTHENTICATION
      // --------------------------------------------------------

      final authenticated = await _ensureGoogleAuthentication();

      if (!authenticated) {
        await _load();
        return;
      }

      // --------------------------------------------------------
      // STEP 1 — UPLOAD LOCAL CHANGES
      // --------------------------------------------------------

      final uploadResult = await _syncService.syncPendingToGoogleSheets();

      if (!uploadResult.success) {
        await _load();

        if (!mounted) {
          return;
        }

        _showMessage(
          uploadResult.message,
          isError: true,
        );

        await _openConflictReview(uploadResult.conflictCount);
        return;
      }

      // --------------------------------------------------------
      // STEP 2 — APPLY SAFE REMOTE CHANGES
      // --------------------------------------------------------

      final applyResult = await _syncService.applyRemoteChangesToLocal();

      if (!mounted) {
        return;
      }

      // --------------------------------------------------------
      // STEP 3 — SAVE CONFLICT COUNT FOR THIS SESSION
      // --------------------------------------------------------

      setState(() {
        _conflicts = applyResult.conflicts;
      });

      await _load();

      if (!mounted) {
        return;
      }

      if (applyResult.conflicts > 0) {
        _showMessage(
          'Synchronization found '
          '${applyResult.conflicts} conflict(s). '
          'Opening conflict review.',
          isError: true,
        );

        await _openConflictReview(applyResult.conflicts);
        return;
      }

      // --------------------------------------------------------
      // STEP 4 — REFRESH PENDING COUNT
      // --------------------------------------------------------

      await _load();

      if (!mounted) {
        return;
      }

      // --------------------------------------------------------
      // STEP 5 — SHOW RESULT
      // --------------------------------------------------------

      _showMessage(
        'Synchronization completed.\n\n'
        '${uploadResult.message}\n\n'
        '${applyResult.message}',
        isError: !applyResult.success,
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

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
  // MESSAGE
  // ============================================================

  void _showMessage(
    String message, {
    bool isError = false,
  }) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(
          seconds: 5,
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
    String statusText;
    String detailText;
    IconData statusIcon;

    if (_syncing) {
      statusText = 'Synchronizing...';

      detailText = 'Uploading local changes and checking '
          'Google Sheets.';

      statusIcon = Icons.sync_rounded;
    } else if (_conflicts > 0) {
      statusText = 'Conflict requires attention';

      detailText = _conflicts == 1
          ? '1 record needs manual review.'
          : '$_conflicts records need manual review.';

      statusIcon = Icons.warning_amber_rounded;
    } else if (_pending > 0) {
      statusText = 'Changes pending';

      detailText = _pending == 1
          ? '1 local change is waiting to be synchronized.'
          : '$_pending local changes are waiting to be synchronized.';

      statusIcon = Icons.cloud_upload_outlined;
    } else {
      statusText = 'Up to date';

      detailText = 'No pending local changes.';

      statusIcon = Icons.cloud_done_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            statusIcon,
            size: 22,
          ),
          const SizedBox(
            width: 10,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  statusText,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(
                  height: 2,
                ),
                Text(
                  detailText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(
            width: 12,
          ),
          FilledButton.tonalIcon(
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
              _syncing ? 'Syncing...' : 'Sync to cloud',
            ),
          ),
        ],
      ),
    );
  }
}
