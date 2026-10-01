import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holistic_anecdotal_records/services/google_auth_service.dart';
import 'package:holistic_anecdotal_records/services/oauth_client_config_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory documents;
  late OAuthClientConfigService config;
  var legacyReads = 0;
  const original =
      '{"installed":{"client_id":"original-id","client_secret":"original-secret"}}';
  const different =
      '{"installed":{"client_id":"different-id","client_secret":"different-secret"}}';

  setUp(() async {
    documents = await Directory.systemTemp.createTemp('oauth_config_test_');
    legacyReads = 0;
    config = OAuthClientConfigService(
      documentsOverride: documents,
      legacyAssetLoader: () async {
        legacyReads++;
        return original;
      },
    );
    SharedPreferences.setMockInitialValues({'token': 'saved-google-token'});
  });

  tearDown(() async => documents.delete(recursive: true));

  Future<File> persistent() => config.externalFile();

  test('valid persistent configuration loads without legacy access', () async {
    final file = await persistent();
    await file.parent.create(recursive: true);
    await file.writeAsString(original);
    final loaded = await config.load();
    expect(loaded.clientId, 'original-id');
    expect(loaded.clientSecret, 'original-secret');
    expect(legacyReads, 0);
  });

  test('different bundled configuration never overwrites persistent copy',
      () async {
    final file = await persistent();
    await file.parent.create(recursive: true);
    await file.writeAsString(original);
    config = OAuthClientConfigService(
      documentsOverride: documents,
      legacyAssetLoader: () async => different,
    );
    expect((await config.load()).clientId, 'original-id');
    expect(await file.readAsString(), original);
  });

  test('valid legacy asset migrates when external file is absent', () async {
    final loaded = await config.load();
    expect(loaded.clientId, 'original-id');
    expect(await (await persistent()).readAsString(), original);
    expect(legacyReads, 1);
  });

  test('migration creates the configuration parent directory', () async {
    final file = await persistent();
    expect(await file.parent.exists(), isFalse);
    await config.load();
    expect(await file.parent.exists(), isTrue);
    expect(
        file.path,
        endsWith('HolisticAnecdotalRecords${Platform.pathSeparator}'
            'config${Platform.pathSeparator}google_oauth_client.json'));
  });

  test('migration is idempotent and reads legacy only once', () async {
    await config.load();
    await config.load();
    expect(legacyReads, 1);
    expect(await (await persistent()).readAsString(), original);
  });

  test('invalid persistent file fails without consulting legacy', () async {
    final file = await persistent();
    await file.parent.create(recursive: true);
    await file.writeAsString('{bad');
    await expectLater(config.load(), throwsStateError);
    expect(legacyReads, 0);
    expect(await file.readAsString(), '{bad');
  });

  test('missing external and missing legacy fail with setup message', () async {
    config = OAuthClientConfigService(
      documentsOverride: documents,
      legacyAssetLoader: () async => throw StateError('asset missing'),
    );
    await expectLater(
        config.load(),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'message', contains('See README'))));
    expect(await (await persistent()).exists(), isFalse);
  });

  test('malformed legacy asset is never persisted', () async {
    config = OAuthClientConfigService(
      documentsOverride: documents,
      legacyAssetLoader: () async => '{"installed":{"client_id":"only"}}',
    );
    await expectLater(config.load(), throwsStateError);
    expect(await (await persistent()).exists(), isFalse);
  });

  test('empty required fields fail without persisting', () async {
    config = OAuthClientConfigService(
      documentsOverride: documents,
      legacyAssetLoader: () async =>
          '{"installed":{"client_id":" ","client_secret":"secret"}}',
    );
    await expectLater(config.load(), throwsStateError);
    expect(await (await persistent()).exists(), isFalse);
  });

  test('authentication config error retains token and emits no credentials',
      () async {
    final file = await persistent();
    await file.parent.create(recursive: true);
    // An invalid external file blocks initialization before the sign-in
    // package can be initialized or manipulate its saved token.
    await file.writeAsString('{"installed":{"client_id":" ",'
        '"client_secret":"sensitive-secret","note":"sensitive-id"}}');
    final messages = <String>[];
    final previous = debugPrint;
    debugPrint = (message, {wrapWidth}) => messages.add(message ?? '');
    try {
      await expectLater(
          GoogleAuthService.forTesting(config).initialize(),
          throwsA(isA<StateError>()
              .having((e) => e.toString(), 'error',
                  isNot(contains('sensitive-secret')))
              .having((e) => e.toString(), 'error',
                  isNot(contains('sensitive-id')))));
    } finally {
      debugPrint = previous;
    }
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('token'), 'saved-google-token');
    expect(messages.join(), isNot(contains('sensitive-id')));
    expect(messages.join(), isNot(contains('sensitive-secret')));
  });
}
