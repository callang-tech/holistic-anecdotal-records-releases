import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holistic_anecdotal_records/services/anecdotal_pdf_service.dart';
import 'package:holistic_anecdotal_records/services/image_personalization_service.dart';
import 'package:holistic_anecdotal_records/theme/app_theme.dart';
import 'package:holistic_anecdotal_records/widgets/app_background.dart';
import 'package:holistic_anecdotal_records/widgets/image_personalization_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<Uint8List> sampleImage(Color color,
    {int width = 1270, int height = 317}) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(color, BlendMode.src);
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

class _PreviewImages extends ImagePersonalizationService {
  Uint8List? current;

  @override
  Future<Uint8List?> customBytes(PersonalizedImage kind) async => current;

  void show(Uint8List? bytes) {
    current = bytes;
    notifyListeners();
  }
}

class _RestoreImages extends ImagePersonalizationService {
  final restored = <PersonalizedImage>[];

  @override
  Future<Uint8List?> customBytes(PersonalizedImage kind) async => null;

  @override
  Future<bool> hasManagedCopy(PersonalizedImage kind) async => true;

  @override
  Future<void> restoreDefault(PersonalizedImage kind) async {
    restored.add(kind);
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late ImagePersonalizationService images;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('image_personalization_');
    images = ImagePersonalizationService(
        directoryOverride: Directory('${temp.path}/customization'));
    SharedPreferences.setMockInitialValues({'app_theme_preset': 2});
  });

  tearDown(() async {
    images.dispose();
    await temp.delete(recursive: true);
  });

  test('copies all three images to deterministic persistent files', () async {
    final source = File('${temp.path}/source.jpg');
    await source.writeAsBytes(await sampleImage(Colors.red));
    for (final kind in PersonalizedImage.values) {
      await source.writeAsBytes(
          await sampleImage(Colors.red, height: kind.requiredHeight ?? 2));
      await images.importFile(kind, source.path);
      final file = await images.managedFile(kind);
      expect(file.path,
          endsWith('customization${Platform.pathSeparator}${kind.fileName}'));
      expect(await file.exists(), isTrue);
      expect(await images.customBytes(kind), isNotNull);
    }
    await source.delete();
    for (final kind in PersonalizedImage.values) {
      expect(await images.customBytes(kind), isNotNull);
    }
  });

  test('custom image wins; missing and corrupt files fall back to assets',
      () async {
    final defaultBackground =
        await images.imageBytes(PersonalizedImage.background);
    expect(await images.customBytes(PersonalizedImage.background), isNull);
    await images.importBytes(
        PersonalizedImage.background, await sampleImage(Colors.green));
    final custom = await images.imageBytes(PersonalizedImage.background);
    expect(custom, isNot(equals(defaultBackground)));
    final file = await images.managedFile(PersonalizedImage.background);
    await file.writeAsBytes([1, 2, 3]);
    expect(await images.imageBytes(PersonalizedImage.background),
        equals(defaultBackground));
    expect(await images.hasManagedCopy(PersonalizedImage.background), isTrue);
    await images.restoreDefault(PersonalizedImage.background);
    expect(await images.hasManagedCopy(PersonalizedImage.background), isFalse);
  });

  test('unsupported input is rejected without replacing an existing image',
      () async {
    await images.importBytes(
        PersonalizedImage.background, await sampleImage(Colors.orange));
    final before = await images.customBytes(PersonalizedImage.background);
    await expectLater(
        images.importBytes(PersonalizedImage.background,
            Uint8List.fromList([71, 73, 70, 56, 57, 97])),
        throwsFormatException);
    expect(
        await images.customBytes(PersonalizedImage.background), equals(before));
  });

  test('restore removes only the selected managed copy and retains theme',
      () async {
    for (final kind in PersonalizedImage.values) {
      await images.importBytes(kind,
          await sampleImage(Colors.blue, height: kind.requiredHeight ?? 2));
    }
    await images.restoreDefault(PersonalizedImage.header);
    expect(await images.customBytes(PersonalizedImage.header), isNull);
    expect(await images.customBytes(PersonalizedImage.background), isNotNull);
    expect(await images.customBytes(PersonalizedImage.footer), isNotNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('app_theme_preset'), 2);
    final theme = AppThemeController();
    await theme.initialize();
    expect(theme.preset, AppThemePreset.values[2]);
    theme.dispose();
  });

  test('PDF image loader selects custom header and footer', () async {
    final defaults =
        await AnecdotalPdfService.loadReportImages(personalization: images);
    await images.importBytes(
        PersonalizedImage.header, await sampleImage(Colors.red));
    await images.importBytes(
        PersonalizedImage.footer, await sampleImage(Colors.blue, height: 154));
    final selected =
        await AnecdotalPdfService.loadReportImages(personalization: images);
    expect(selected.header, isNot(equals(defaults.header)));
    expect(selected.footer, isNot(equals(defaults.footer)));
    await (await images.managedFile(PersonalizedImage.header))
        .writeAsBytes([1, 2, 3]);
    final fallback =
        await AnecdotalPdfService.loadReportImages(personalization: images);
    expect(fallback.header, equals(defaults.header));
    expect(fallback.footer, equals(selected.footer));
  });

  for (final kind in [PersonalizedImage.header, PersonalizedImage.footer]) {
    test('${kind.label} rejects wrong dimensions before any write', () async {
      final wrong = await sampleImage(Colors.red, width: 1269, height: 154);
      await expectLater(
          images.importBytes(kind, wrong),
          throwsA(isA<FormatException>().having(
              (e) => e.message,
              'dimensions',
              contains(
                  '1270 x ${kind.requiredHeight} pixels. Selected image is 1269 x 154'))));
      expect(await (await images.customizationDirectory()).exists(), isFalse);
      final valid =
          await sampleImage(Colors.green, height: kind.requiredHeight!);
      await images.importBytes(kind, valid);
      await expectLater(images.importBytes(kind, wrong), throwsFormatException);
      expect(await images.customBytes(kind), orderedEquals(valid));
      final restarted = ImagePersonalizationService(
          directoryOverride: await images.customizationDirectory());
      expect(await restarted.customBytes(kind), orderedEquals(valid));
      restarted.dispose();
    });

    test(
        '${kind.label} invalid persisted dimensions fall back; restore is isolated',
        () async {
      final fallback = await images.imageBytes(kind);
      await images.importBytes(
          kind, await sampleImage(Colors.green, height: kind.requiredHeight!));
      final file = await images.managedFile(kind);
      await file
          .writeAsBytes(await sampleImage(Colors.red, width: 2, height: 2));
      expect(await images.imageBytes(kind), orderedEquals(fallback));
      final other = kind == PersonalizedImage.header
          ? PersonalizedImage.footer
          : PersonalizedImage.header;
      final otherBytes =
          await sampleImage(Colors.blue, height: other.requiredHeight!);
      await images.importBytes(other, otherBytes);
      await images.restoreDefault(kind);
      expect(await file.exists(), isFalse);
      expect(await images.imageBytes(kind), orderedEquals(fallback));
      expect(await images.customBytes(other), orderedEquals(otherBytes));
    });
  }

  testWidgets('Admin appearance card exposes three previews and controls',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
      body: SingleChildScrollView(
        child: ImagePersonalizationCard(personalization: images),
      ),
    )));
    await tester.pumpAndSettle();
    expect(find.text('Home Background'), findsOneWidget);
    expect(find.text('Report Header'), findsOneWidget);
    expect(find.text('Report Footer'), findsOneWidget);
    expect(find.text('PDF / Report Customization'), findsOneWidget);
    expect(find.text('Change Header'), findsOneWidget);
    expect(find.text('Change Footer'), findsOneWidget);
    expect(find.text('Restore Default Header'), findsOneWidget);
    expect(find.text('Restore Default Footer'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('AppBackground switches between default and saved image',
      (tester) async {
    final preview = _PreviewImages();
    addTearDown(preview.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AppBackground(
                personalization: preview, child: const Text('Content')))));
    await tester.pumpAndSettle();
    expect((tester.widget<Image>(find.byType(Image))).image, isA<AssetImage>());
    final bytes = await tester.runAsync(() => sampleImage(Colors.purple));
    preview.show(bytes);
    await tester.pumpAndSettle();
    expect(
        (tester.widget<Image>(find.byType(Image))).image, isA<MemoryImage>());
    preview.show(null);
    await tester.pumpAndSettle();
    expect((tester.widget<Image>(find.byType(Image))).image, isA<AssetImage>());
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final kind in [PersonalizedImage.header, PersonalizedImage.footer]) {
    testWidgets('report-only card confirms restoring ${kind.controlLabel}',
        (tester) async {
      final service = _RestoreImages();
      addTearDown(service.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ImagePersonalizationCard(
              personalization: service,
              reportsOnly: true,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Home Background'), findsNothing);
      expect(find.text('PDF / Report Customization'), findsOneWidget);
      expect(find.byType(Image), findsNWidgets(2));
      final restore = find.text('Restore Default ${kind.controlLabel}');
      await tester.ensureVisible(restore);
      await tester.tap(restore);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(service.restored, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(service.restored, isEmpty);
      await tester.tap(restore);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restore Default'));
      await tester.pumpAndSettle();
      expect(service.restored, [kind]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
