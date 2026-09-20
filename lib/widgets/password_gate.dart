import 'package:flutter/material.dart';

import '../services/google_auth_service.dart';
import '../services/password_service.dart';

enum _PasswordGateResult {
  authenticated,
  forgotPassword,
}

class PasswordGate {
  static final PasswordService _passwordService = PasswordService();
  static final GoogleAuthService _googleAuth = GoogleAuthService.instance;

  static Future<bool> request(BuildContext context) async {
    final hasPassword = await _passwordService.hasPassword();

    if (!context.mounted) return false;

    if (!hasPassword) {
      return _showInitialPasswordDialog(context);
    }

    final result = await showDialog<_PasswordGateResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _PasswordDialog(),
    );

    if (!context.mounted) return false;

    if (result == _PasswordGateResult.forgotPassword) {
      await _forgotPassword(context);
      return false;
    }

    return result == _PasswordGateResult.authenticated;
  }

  static Future<bool> _showInitialPasswordDialog(
    BuildContext context,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _InitialPasswordDialog(),
    );
    return result ?? false;
  }

  static Future<void> _rememberGoogleRecoveryAccount() async {
    final existing = await _passwordService.getRecoveryEmail();
    if (existing != null && existing.isNotEmpty) return;
    if (!_googleAuth.isSignedIn) return;

    try {
      final email = await _googleAuth.getAccountEmail();
      if (email != null && email.isNotEmpty) {
        await _passwordService.setRecoveryEmail(email);
      }
    } catch (_) {
      // Recovery binding is best-effort during normal login.
    }
  }

  static Future<void> _forgotPassword(BuildContext context) async {
    final recoveryEmail = await _passwordService.getRecoveryEmail();

    if (!context.mounted) return;

    if (recoveryEmail == null || recoveryEmail.isEmpty) {
      await _showMessage(
        context,
        'No recovery Google account has been registered yet.\n\n'
        'Sign in to the authorized Google account in the app, then log in '
        'normally once so it can be registered for password recovery.',
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset system password'),
        content: Text(
          'A one-time reset code will be sent to:\n\n'
          '$recoveryEmail\n\n'
          'The existing password will not be sent or revealed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final diagnostic = _RecoveryDiagnosticController();
    diagnostic.open(context);

    try {
      diagnostic.step('1/7  Connecting to Google...');
      final credentials = await _googleAuth.signIn();

      if (credentials == null) {
        throw StateError('Google sign-in was cancelled.');
      }

      diagnostic.step('2/7  Google sign-in completed.');

      diagnostic.step('3/7  Checking the signed-in Google account...');
      final accountEmail = await _googleAuth.getAccountEmail();

      if (accountEmail == null || accountEmail.trim().isEmpty) {
        throw StateError(
          'Google sign-in succeeded, but the account email could not be determined.',
        );
      }

      if (accountEmail.toLowerCase() != recoveryEmail.toLowerCase()) {
        throw StateError(
          'The signed-in Google account does not match the registered '
          'recovery account.\n\n'
          'Registered: $recoveryEmail\n'
          'Signed in: $accountEmail',
        );
      }

      diagnostic.step('4/7  Requesting Gmail sending permission...');
      await _googleAuth.ensureGmailSendAccess();

      final verifiedAccountEmail = await _googleAuth.getAccountEmail();

      if (verifiedAccountEmail == null ||
          verifiedAccountEmail.toLowerCase() != recoveryEmail.toLowerCase()) {
        throw StateError(
          'The Google account used for Gmail authorization does not match '
          'the registered recovery account.\n\n'
          'Registered: $recoveryEmail\n'
          'Authorized: ${verifiedAccountEmail ?? 'unknown'}',
        );
      }

      diagnostic.step('5/7  Gmail permission granted.');

      diagnostic.step('6/7  Generating a one-time reset code...');
      final code = await _passwordService.createResetCode();

      diagnostic.step('7/7  Sending the reset email...');
      await _googleAuth.sendPasswordResetCode(
        recipientEmail: recoveryEmail,
        code: code,
      );

      diagnostic.step('EMAIL SENT  Gmail accepted the reset message.');

      await Future<void>.delayed(
        const Duration(milliseconds: 600),
      );

      if (!context.mounted) return;

      diagnostic.close();

      if (!context.mounted) return;

      final verifiedCode = await _showResetCodeDialog(context);

      if (verifiedCode == null || !context.mounted) return;

      await _showNewPasswordDialog(
        context,
        verifiedCode,
      );
    } catch (e, stackTrace) {
      debugPrint('PASSWORD RECOVERY ERROR: $e');
      debugPrintStack(stackTrace: stackTrace);

      diagnostic.error(e);

      await Future<void>.delayed(
        const Duration(milliseconds: 300),
      );

      if (!context.mounted) return;

      diagnostic.close();

      if (!context.mounted) return;

      await _showMessage(
        context,
        'Password reset could not be completed.\n\n'
        '${_cleanError(e)}',
      );
    }
  }

  static String _cleanError(Object error) {
    return error
        .toString()
        .replaceFirst('Bad state: ', '')
        .replaceFirst('StateError: ', '')
        .replaceFirst('Exception: ', '')
        .trim();
  }

  static Future<String?> _showResetCodeDialog(
    BuildContext context,
  ) async {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _ResetCodeDialog(),
    );
  }

  static Future<void> _showNewPasswordDialog(
    BuildContext context,
    String verifiedResetCode,
  ) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _NewPasswordDialog(
        verifiedResetCode: verifiedResetCode,
      ),
    );
  }

  static Future<void> _showMessage(
    BuildContext context,
    String message,
  ) async {
    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        content: SingleChildScrollView(
          child: Text(message),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

class _RecoveryDiagnosticController {
  BuildContext? _context;
  StateSetter? _setState;
  String _message = 'Starting...';
  String? _error;
  bool _closed = false;

  void open(BuildContext context) {
    _context = context;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            _setState = setState;

            return AlertDialog(
              title: const Row(
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text('Password Recovery'),
                  ),
                ],
              ),
              content: SizedBox(
                width: 460,
                child: SingleChildScrollView(
                  child: Text(
                    _error ?? _message,
                    style: TextStyle(
                      color: _error == null
                          ? null
                          : Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    ).then((_) {
      _closed = true;
      _context = null;
      _setState = null;
    });
  }

  void step(String message) {
    _message = message;
    _error = null;
    _refresh();
    debugPrint('PASSWORD RECOVERY: $message');
  }

  void error(Object error) {
    _error = _clean(error);
    _message = 'Recovery stopped.';
    _refresh();
    debugPrint('PASSWORD RECOVERY ERROR: $_error');
  }

  void _refresh() {
    if (_closed) return;

    final setter = _setState;

    if (setter != null) {
      setter(() {});
    }
  }

  void close() {
    if (_closed) return;

    final context = _context;

    if (context != null && context.mounted) {
      Navigator.of(
        context,
        rootNavigator: true,
      ).pop();
    }
  }

  static String _clean(Object error) {
    return error
        .toString()
        .replaceFirst('Bad state: ', '')
        .replaceFirst('StateError: ', '')
        .replaceFirst('Exception: ', '')
        .trim();
  }
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog();

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _controller = TextEditingController();

  bool _obscure = true;
  bool _error = false;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_busy) return;

    setState(() {
      _busy = true;
      _error = false;
    });

    final ok = await PasswordGate._passwordService.verify(
      _controller.text,
    );

    if (!mounted) return;

    if (ok) {
      await PasswordGate._rememberGoogleRecoveryAccount();

      if (!mounted) return;

      Navigator.pop(
        context,
        _PasswordGateResult.authenticated,
      );
    } else {
      setState(() {
        _busy = false;
        _error = true;
      });
    }
  }

  void _forgotPassword() {
    if (_busy) return;

    Navigator.pop(
      context,
      _PasswordGateResult.forgotPassword,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Enter system password'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        obscureText: _obscure,
        enabled: !_busy,
        onSubmitted: (_) => _verify(),
        decoration: InputDecoration(
          labelText: 'Password',
          errorText: _error ? 'Incorrect password.' : null,
          suffixIcon: IconButton(
            onPressed: _busy
                ? null
                : () => setState(
                      () => _obscure = !_obscure,
                    ),
            icon: Icon(
              _obscure
                  ? Icons.visibility
                  : Icons.visibility_off,
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy
              ? null
              : () => Navigator.pop(
                    context,
                    null,
                  ),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _busy ? null : _forgotPassword,
          child: const Text('Forgot Password?'),
        ),
        FilledButton(
          onPressed: _busy ? null : _verify,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                  ),
                )
              : const Text('Continue'),
        ),
      ],
    );
  }
}

class _InitialPasswordDialog extends StatefulWidget {
  const _InitialPasswordDialog();

  @override
  State<_InitialPasswordDialog> createState() =>
      _InitialPasswordDialogState();
}

class _InitialPasswordDialogState
    extends State<_InitialPasswordDialog> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _obscure = true;
  bool _confirmObscure = true;
  bool _busy = false;
  String _error = '';

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;

    final password = _passwordController.text;
    final confirm = _confirmController.text;

    if (password.length < 8) {
      setState(() => _error = 'Use at least 8 characters.');
      return;
    }

    if (password != confirm) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }

    setState(() {
      _busy = true;
      _error = '';
    });

    try {
      await PasswordGate._passwordService.setPassword(password);
      await PasswordGate._rememberGoogleRecoveryAccount();

      if (!mounted) return;

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _busy = false;
        _error = PasswordGate._cleanError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create system password'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'No system password has been configured yet. Create one now.',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _passwordController,
            obscureText: _obscure,
            enabled: !_busy,
            decoration: InputDecoration(
              labelText: 'New password',
              suffixIcon: IconButton(
                onPressed: _busy
                    ? null
                    : () => setState(
                          () => _obscure = !_obscure,
                        ),
                icon: Icon(
                  _obscure
                      ? Icons.visibility
                      : Icons.visibility_off,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirmController,
            obscureText: _confirmObscure,
            enabled: !_busy,
            onSubmitted: (_) => _save(),
            decoration: InputDecoration(
              labelText: 'Confirm password',
              errorText: _error.isEmpty ? null : _error,
              suffixIcon: IconButton(
                onPressed: _busy
                    ? null
                    : () => setState(
                          () => _confirmObscure = !_confirmObscure,
                        ),
                icon: Icon(
                  _confirmObscure
                      ? Icons.visibility
                      : Icons.visibility_off,
                ),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy
              ? null
              : () => Navigator.pop(
                    context,
                    false,
                  ),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                  ),
                )
              : const Text('Create Password'),
        ),
      ],
    );
  }
}

class _ResetCodeDialog extends StatefulWidget {
  const _ResetCodeDialog();

  @override
  State<_ResetCodeDialog> createState() => _ResetCodeDialogState();
}

class _ResetCodeDialogState extends State<_ResetCodeDialog> {
  final _controller = TextEditingController();

  bool _busy = false;
  String _error = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _verifyCode() async {
    if (_busy) return;

    setState(() => _busy = true);

    try {
      final valid = await PasswordGate._passwordService.verifyResetCode(
        _controller.text,
      );

      if (!mounted) return;

      if (valid) {
        Navigator.pop(
          context,
          _controller.text.trim(),
        );
      } else {
        setState(() {
          _busy = false;
          _error = 'Invalid or expired reset code.';
        });
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _busy = false;
        _error = PasswordGate._cleanError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Enter reset code'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        maxLength: 6,
        enabled: !_busy,
        onSubmitted: (_) => _verifyCode(),
        decoration: InputDecoration(
          labelText: '6-digit code',
          errorText: _error.isEmpty ? null : _error,
          counterText: '',
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy
              ? null
              : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _verifyCode,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                  ),
                )
              : const Text('Verify Code'),
        ),
      ],
    );
  }
}

class _NewPasswordDialog extends StatefulWidget {
  final String verifiedResetCode;

  const _NewPasswordDialog({
    required this.verifiedResetCode,
  });

  @override
  State<_NewPasswordDialog> createState() =>
      _NewPasswordDialogState();
}

class _NewPasswordDialogState
    extends State<_NewPasswordDialog> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _obscure = true;
  bool _confirmObscure = true;
  bool _busy = false;
  String _error = '';

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _reset() async {
    if (_busy) return;

    final password = _passwordController.text;
    final confirm = _confirmController.text;

    if (password.length < 8) {
      setState(() => _error = 'Use at least 8 characters.');
      return;
    }

    if (password != confirm) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }

    setState(() {
      _busy = true;
      _error = '';
    });

    try {
      await PasswordGate._passwordService.resetPassword(
        resetCode: widget.verifiedResetCode,
        newPassword: password,
      );

      if (!mounted) return;

      Navigator.pop(context);

      if (!mounted) return;

      await PasswordGate._showMessage(
        context,
        'Your system password has been reset successfully. '
        'The old password is no longer valid.',
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _busy = false;
        _error = PasswordGate._cleanError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create new system password'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _passwordController,
            obscureText: _obscure,
            enabled: !_busy,
            decoration: InputDecoration(
              labelText: 'New password',
              suffixIcon: IconButton(
                onPressed: _busy
                    ? null
                    : () => setState(
                          () => _obscure = !_obscure,
                        ),
                icon: Icon(
                  _obscure
                      ? Icons.visibility
                      : Icons.visibility_off,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirmController,
            obscureText: _confirmObscure,
            enabled: !_busy,
            onSubmitted: (_) => _reset(),
            decoration: InputDecoration(
              labelText: 'Confirm password',
              errorText: _error.isEmpty ? null : _error,
              suffixIcon: IconButton(
                onPressed: _busy
                    ? null
                    : () => setState(
                          () => _confirmObscure = !_confirmObscure,
                        ),
                icon: Icon(
                  _confirmObscure
                      ? Icons.visibility
                      : Icons.visibility_off,
                ),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy
              ? null
              : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _reset,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                  ),
                )
              : const Text('Reset Password'),
        ),
      ],
    );
  }
}
