import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in_all_platforms/google_sign_in_all_platforms.dart';
import 'package:http/http.dart' as http;

import 'oauth_client_config_service.dart';

class GoogleAuthService {
  GoogleAuthService._() : _config = OAuthClientConfigService();

  @visibleForTesting
  GoogleAuthService.forTesting(OAuthClientConfigService config)
      : _config = config;

  static final GoogleAuthService instance = GoogleAuthService._();

  // ============================================================
  // GOOGLE OAUTH CONFIGURATION
  // ============================================================

  // Loaded from persistent installation configuration; see README for setup.

  final OAuthClientConfigService _config;

  static const String gmailSendScope =
      'https://www.googleapis.com/auth/gmail.send';

  // google_sign_in_all_platforms initializes its platform parameters only once.
  // Therefore all scopes that this app may need during the running session
  // must be declared on the single GoogleSignIn instance created at startup.
  static const List<String> scopes = <String>[
    'openid',
    'profile',
    'email',
    'https://www.googleapis.com/auth/spreadsheets',
    gmailSendScope,
  ];

  GoogleSignIn? _googleSignIn;
  GoogleSignInCredentials? _latestCredentials;
  bool _initialized = false;

  // ============================================================
  // INITIALIZE
  // ============================================================

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    _googleSignIn = await _createGoogleSignIn();
    _initialized = true;
  }

  Future<GoogleSignIn> _createGoogleSignIn() async {
    final config = await _config.load();
    return GoogleSignIn(
      params: GoogleSignInParams(
        clientId: config.clientId,
        clientSecret: config.clientSecret,
        scopes: scopes,
      ),
    );
  }

  GoogleSignIn get _signIn {
    final signIn = _googleSignIn;

    if (signIn == null) {
      throw StateError(
        'GoogleAuthService has not been initialized.',
      );
    }

    return signIn;
  }

  // ============================================================
  // AUTHENTICATION STATE
  // ============================================================

  Stream<GoogleSignInCredentials?> get authenticationState =>
      _signIn.authenticationState;

  GoogleSignInCredentials? get currentCredentials => _latestCredentials;

  bool get isSignedIn => _latestCredentials != null;

  String? get accessToken => _latestCredentials?.accessToken;

  String? get idToken => _latestCredentials?.idToken;

  String? get refreshToken => _latestCredentials?.refreshToken;

  List<String> get grantedScopes => List<String>.unmodifiable(
        _latestCredentials?.scopes ?? const <String>[],
      );

  DateTime? get expiresAt => _latestCredentials?.expiresIn;

  String get authenticationStatus =>
      _latestCredentials == null ? 'Not connected' : 'Connected';

  // ============================================================
  // SIGN IN
  // ============================================================

  Future<GoogleSignInCredentials?> signIn() async {
    await initialize();

    try {
      final credentials = await _signIn.signIn();

      _latestCredentials = credentials;

      return credentials;
    } catch (e, stackTrace) {
      debugPrint(
        'GOOGLE SIGN-IN ERROR: $e',
      );
      debugPrintStack(
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  // ============================================================
  // SILENT SIGN IN
  // ============================================================

  Future<GoogleSignInCredentials?> silentSignIn() async {
    await initialize();

    try {
      final credentials = await _signIn.silentSignIn();

      _latestCredentials = credentials;

      return credentials;
    } catch (e, stackTrace) {
      debugPrint(
        'GOOGLE SILENT SIGN-IN ERROR: $e',
      );
      debugPrintStack(
        stackTrace: stackTrace,
      );

      _latestCredentials = null;

      return null;
    }
  }

  // ============================================================
  // SIGN OUT
  // ============================================================

  Future<void> signOut() async {
    await initialize();

    await _signIn.signOut();

    _latestCredentials = null;
  }

  // ============================================================
  // AUTHENTICATED HTTP CLIENT
  // ============================================================

  /// Returns the package-managed authenticated HTTP client.
  ///
  /// Google API calls should use this client instead of manually attaching
  /// [accessToken]. The package can then use the current/renewed token rather
  /// than leaving the application dependent on a stale token.
  Future<http.Client?> get authenticatedClient async {
    await initialize();

    return _signIn.authenticatedClient;
  }

  // ============================================================
  // ACCOUNT EMAIL
  // ============================================================

  /// Returns the email address belonging to the currently authenticated
  /// Google account.
  ///
  /// This version intentionally uses [authenticatedClient]. The previous
  /// raw-access-token implementation could return HTTP 401 after the token
  /// became stale.
  Future<String?> getAccountEmail() async {
    final client = await authenticatedClient;

    if (client == null) {
      throw StateError(
        'Google account is not authenticated.',
      );
    }

    final response = await client.get(
      Uri.parse(
        'https://www.googleapis.com/oauth2/v3/userinfo',
      ),
      headers: const <String, String>{
        'Accept': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      var detail = response.body.trim();

      if (detail.length > 500) {
        detail = detail.substring(0, 500);
      }

      throw StateError(
        'Google account information could not be retrieved '
        '(HTTP ${response.statusCode}).'
        '${detail.isEmpty ? '' : '\n\nGoogle response:\n$detail'}',
      );
    }

    final dynamic decoded = jsonDecode(response.body);

    if (decoded is! Map<String, dynamic>) {
      throw StateError(
        'Google account information returned an invalid response.',
      );
    }

    final email = decoded['email']?.toString().trim().toLowerCase();

    if (email == null || email.isEmpty) {
      return null;
    }

    return email;
  }

  // ============================================================
  // GMAIL SEND PERMISSION
  // ============================================================

  /// Ensures that the current Google authorization includes gmail.send.
  ///
  /// Verifies that the current Google authorization includes gmail.send.
  ///
  /// The scope is declared on the application's single GoogleSignIn instance
  /// because google_sign_in_all_platforms does not support reinitializing its
  /// platform parameters with a second scope set during the same process.
  Future<GoogleSignInCredentials?> ensureGmailSendAccess() async {
    await initialize();

    // The single GoogleSignIn instance was initialized with gmail.send.
    // Never create another GoogleSignIn instance here: this package keeps
    // initialization parameters globally and will assert if they are set
    // a second time during the same application process.
    var credentials = _latestCredentials;

    if (credentials == null) {
      credentials = await _signIn.silentSignIn();

      _latestCredentials = credentials;
    }

    if (credentials == null) {
      credentials = await _signIn.signIn();

      _latestCredentials = credentials;
    }

    if (credentials == null) {
      throw StateError(
        'Google sign-in was cancelled.',
      );
    }

    if (!credentials.scopes.contains(
      gmailSendScope,
    )) {
      throw StateError(
        'Gmail sending permission is not available in the current Google '
        'authorization. Disconnect the Google account, reconnect it, and '
        'approve the requested Gmail sending permission.',
      );
    }

    final email = await getAccountEmail();

    if (email == null || email.isEmpty) {
      throw StateError(
        'The authenticated Google account email could not be determined.',
      );
    }

    return credentials;
  }

  // ============================================================
  // PASSWORD RESET EMAIL
  // ============================================================

  /// Sends a one-time password-reset code using the Gmail API.
  ///
  /// The old password, password hash, and new password are never sent.
  Future<void> sendPasswordResetCode({
    required String recipientEmail,
    required String code,
  }) async {
    final client = await authenticatedClient;

    if (client == null) {
      throw StateError(
        'Google authentication is required.',
      );
    }

    final credentials = _latestCredentials;

    if (credentials == null) {
      throw StateError(
        'Google authentication credentials are not available.',
      );
    }

    if (!credentials.scopes.contains(
      gmailSendScope,
    )) {
      throw StateError(
        'Gmail sending permission is not present in the current Google session. '
        'Please authorize Gmail access again.',
      );
    }

    final senderEmail = await getAccountEmail();

    if (senderEmail == null || senderEmail.isEmpty) {
      throw StateError(
        'The Google account email could not be determined.',
      );
    }

    final normalizedRecipient = recipientEmail.trim().toLowerCase();

    if (normalizedRecipient.isEmpty) {
      throw StateError(
        'The password recovery email address is empty.',
      );
    }

    if (normalizedRecipient != senderEmail.toLowerCase()) {
      throw StateError(
        'The recovery email does not match the authenticated Google account.',
      );
    }

    // ------------------------------------------------------------
    // Build RFC 2822 email.
    //
    // Do NOT call users/me/profile here. The app intentionally requests
    // only gmail.send, which is sufficient for users.messages.send but
    // does not grant mailbox/profile-reading scopes.
    // ------------------------------------------------------------

    final message = <String>[
      'From: $senderEmail',
      'To: $normalizedRecipient',
      'Subject: Anecdotal Records password reset code',
      'MIME-Version: 1.0',
      'Content-Type: text/plain; charset=UTF-8',
      '',
      'Your Holistic Anecdotal Records password reset code is:',
      '',
      code,
      '',
      'This code expires in 10 minutes.',
      '',
      'If you did not request a password reset, '
          'you can safely ignore this email.',
      '',
      'The existing system password is never included in this message.',
    ].join('\r\n');

    final rawMessage = base64Url
        .encode(
          utf8.encode(
            message,
          ),
        )
        .replaceAll(
          '=',
          '',
        );

    // ------------------------------------------------------------
    // Send through Gmail API.
    // ------------------------------------------------------------

    final response = await client.post(
      Uri.parse(
        'https://gmail.googleapis.com/gmail/v1/users/me/messages/send',
      ),
      headers: const <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode(
        <String, String>{
          'raw': rawMessage,
        },
      ),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      var detail = response.body.trim();

      if (detail.length > 800) {
        detail = detail.substring(0, 800);
      }

      throw StateError(
        'Google could not send the password-reset email '
        '(HTTP ${response.statusCode}).'
        '${detail.isEmpty ? '' : '\n\nGoogle response:\n$detail'}',
      );
    }

    debugPrint(
      'PASSWORD RESET EMAIL SENT: '
      'Gmail API accepted the message for '
      '$normalizedRecipient.',
    );
  }

  // ============================================================
  // AUTHENTICATION TEST
  // ============================================================

  Future<String> runAuthenticationTest() async {
    try {
      await initialize();

      final credentials = await signIn();

      if (credentials == null) {
        return '''
GOOGLE AUTHENTICATION TEST

Sign-in was cancelled or no credentials were returned.
''';
      }

      final tokenAvailable = credentials.accessToken.trim().isNotEmpty;

      final idTokenAvailable = credentials.idToken?.trim().isNotEmpty ?? false;

      final refreshTokenAvailable =
          credentials.refreshToken?.trim().isNotEmpty ?? false;

      String accountEmail = 'Not available';

      try {
        accountEmail = await getAccountEmail() ?? 'Not available';
      } catch (e) {
        debugPrint(
          'AUTH TEST USERINFO ERROR: $e',
        );
      }

      return '''
GOOGLE AUTHENTICATION TEST SUCCESSFUL

Authentication:
  Connected

Account email:
  $accountEmail

Access token:
  ${tokenAvailable ? 'Available' : 'Not available'}

ID token:
  ${idTokenAvailable ? 'Available' : 'Not available'}

Refresh token:
  ${refreshTokenAvailable ? 'Available' : 'Not available'}

Granted scopes:
  ${credentials.scopes.isEmpty ? 'None reported' : credentials.scopes.join(', ')}

Token expiry:
  ${credentials.expiresIn?.toIso8601String() ?? 'Not available'}
''';
    } catch (e, stackTrace) {
      debugPrint(
        'GOOGLE AUTH TEST ERROR: $e',
      );
      debugPrintStack(
        stackTrace: stackTrace,
      );

      return '''
GOOGLE AUTHENTICATION TEST FAILED

$e
''';
    }
  }
}
