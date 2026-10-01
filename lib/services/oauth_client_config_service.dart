import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class OAuthClientConfig {
  const OAuthClientConfig(this.clientId, this.clientSecret);

  final String clientId;
  final String clientSecret;
}

/// The external file is authoritative. The optional bundled asset is read
/// only once, to migrate installations that predate external configuration.
class OAuthClientConfigService {
  OAuthClientConfigService({
    Directory? documentsOverride,
    Future<String> Function()? legacyAssetLoader,
  })  : _documentsOverride = documentsOverride,
        _legacyAssetLoader = legacyAssetLoader ??
            (() => rootBundle
                .loadString('assets/google/google_oauth_client.json'));

  final Directory? _documentsOverride;
  final Future<String> Function() _legacyAssetLoader;

  static const setupMessage =
      'Google OAuth configuration is missing or invalid. Place '
      'google_oauth_client.json in Documents\\HolisticAnecdotalRecords\\config. '
      'See README for setup.';

  Future<File> externalFile() async {
    final documents =
        _documentsOverride ?? await getApplicationDocumentsDirectory();
    return File(p.join(documents.path, 'HolisticAnecdotalRecords', 'config',
        'google_oauth_client.json'));
  }

  Future<OAuthClientConfig> load() async {
    late final File destination;
    try {
      destination = await externalFile();
    } catch (_) {
      throw StateError(setupMessage);
    }
    // An existing but invalid external file is never replaced from an asset.
    if (await destination.exists()) {
      try {
        return _parse(await destination.readAsString());
      } catch (_) {
        throw StateError(setupMessage);
      }
    }

    late final String legacy;
    late final OAuthClientConfig config;
    try {
      legacy = await _legacyAssetLoader();
      config = _parse(legacy);
    } catch (_) {
      throw StateError(setupMessage);
    }

    // Keep the temporary file beside its destination, not in a general temp
    // or updater directory. A same-directory rename avoids a partial config.
    final pending = File('${destination.path}.pending');
    try {
      await destination.parent.create(recursive: true);
      if (await destination.exists()) {
        return _parse(await destination.readAsString());
      }
      await pending.writeAsString(legacy, flush: true);
      await pending.rename(destination.path);
      return config;
    } catch (_) {
      throw StateError(setupMessage);
    } finally {
      if (await pending.exists()) await pending.delete();
    }
  }

  OAuthClientConfig _parse(String text) {
    try {
      final config = jsonDecode(text);
      if (config is! Map<String, dynamic>) throw const FormatException();
      final installed = config['installed'];
      if (installed is! Map<String, dynamic>) throw const FormatException();
      final id = installed['client_id'];
      final secret = installed['client_secret'];
      if (id is! String ||
          secret is! String ||
          id.trim().isEmpty ||
          secret.trim().isEmpty) {
        throw const FormatException();
      }
      return OAuthClientConfig(id.trim(), secret.trim());
    } catch (_) {
      throw StateError(setupMessage);
    }
  }
}
