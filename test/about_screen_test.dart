import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holistic_anecdotal_records/screens/about_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('version follows bundled pubspec without a fixed release value',
      () async {
    final pubspec = await rootBundle.loadString('pubspec.yaml');
    final version = RegExp(r'^version:\s*(\S+)', multiLine: true)
        .firstMatch(pubspec)!
        .group(1)!
        .split('+')
        .first;
    expect(await loadApplicationVersion(), version);
  });

  test('all three bundled branding assets resolve and decode', () async {
    for (final name in ['app_logo.png', 'project_leader.jpg', 'school.jpg']) {
      final data = await rootBundle.load('assets/images/about/$name');
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      expect(frame.image.width, greaterThan(0));
      expect(frame.image.height, greaterThan(0));
      frame.image.dispose();
      codec.dispose();
    }
  });

  for (final width in [360.0, 700.0, 1440.0]) {
    testWidgets(
        'About content, attribution, scrolling and back at width $width',
        (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 650));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Builder(builder: (context) {
          return TextButton(
            onPressed: () => Navigator.push(context,
                MaterialPageRoute<void>(builder: (_) => const AboutScreen())),
            child: const Text('Open About'),
          );
        })),
      ));
      await tester.tap(find.text('Open About'));
      await tester.pumpAndSettle();
      for (final content in [
        'Holistic Anecdotal Records',
        'Holistic Educational Anecdotal Record & Tracking System',
        'Organize • Monitor • Support • Empower Learners',
        'Supporting Learners for a Brighter Tomorrow',
        'ABOUT THE SYSTEM',
        'SYSTEM LEADERSHIP',
        'Michelle A. Carpio, RGC',
        'System Lead and Guidance Process Designer',
        'Guidance Counselor, Care Center Office',
        'INSTITUTION',
        'Callang National High School',
        'District 4, San Manuel, Isabela',
        'Region II, Philippines',
        'PRIVACY & INTENDED USE',
        'ACKNOWLEDGEMENTS',
        'Initial Release • 2026',
      ]) {
        expect(find.text(content), findsOneWidget);
      }
      expect(
          find.text(
              'Directed the development of the system and defined the guidance processes, '
              'record requirements, workflow, and functional requirements that form its '
              'foundation. Provides the professional guidance, content expertise, and '
              'overall direction in the continuous improvement of the system for the '
              'benefit of the learners.'),
          findsOneWidget);
      final acknowledgement = find.text(
          'Special acknowledgement to Joven A. Danipog for the technical development and IT support, '
          'including application programming, database implementation, user interface, '
          'synchronization, testing, and technical refinements.');
      expect(acknowledgement, findsOneWidget);
      expect(find.textContaining('Joven'), findsOneWidget);
      expect(find.text('Technical Development'), findsNothing);
      expect(find.text('Developer'), findsNothing);
      expect(find.byType(Image), findsNWidgets(3));
      expect(
          tester
              .widgetList<Image>(find.byType(Image))
              .map((image) => (image.image as AssetImage).assetName),
          unorderedEquals([
            'assets/images/about/app_logo.png',
            'assets/images/about/project_leader.jpg',
            'assets/images/about/school.jpg',
          ]));
      expect(find.textContaining('Change Photo'), findsNothing);
      expect(find.textContaining('Change Logo'), findsNothing);
      expect(find.text('Choose Image'), findsNothing);
      final version = await tester.runAsync(loadApplicationVersion);
      await tester.pumpAndSettle();
      final footer = find.text('Holistic Anecdotal Records • Version $version');
      expect(footer, findsOneWidget);
      expect(tester.getTopLeft(find.text('SYSTEM LEADERSHIP')).dy,
          lessThan(tester.getTopLeft(find.text('ACKNOWLEDGEMENTS')).dy));
      expect(tester.getTopLeft(acknowledgement).dy,
          lessThan(tester.getTopLeft(footer).dy));
      await tester.ensureVisible(footer);
      await tester.pumpAndSettle();
      expect(footer.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Open About'), findsOneWidget);
    });
  }

  testWidgets('footer automatically displays a future bundled version',
      (tester) async {
    // Replace only pubspec in the test asset channel; other assets still load.
    rootBundle.evict('pubspec.yaml');
    tester.binding.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
      final key = utf8.decode(message!.buffer.asUint8List());
      if (key == 'pubspec.yaml') {
        return ByteData.sublistView(
            Uint8List.fromList(utf8.encode('version: 7.8.9+42\n')));
      }
      return tester.binding.defaultBinaryMessenger.delegate
          .send('flutter/assets', message);
    });
    addTearDown(() {
      tester.binding.defaultBinaryMessenger
          .setMockMessageHandler('flutter/assets', null);
      rootBundle.evict('pubspec.yaml');
    });
    await tester.pumpWidget(const MaterialApp(home: AboutScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Holistic Anecdotal Records • Version 7.8.9'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
