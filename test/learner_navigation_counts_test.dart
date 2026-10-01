import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holistic_anecdotal_records/database/locations_database.dart';
import 'package:holistic_anecdotal_records/models/school_year.dart';
import 'package:holistic_anecdotal_records/screens/add_learner_screen.dart';
import 'package:holistic_anecdotal_records/screens/search_screen.dart';
import 'package:holistic_anecdotal_records/widgets/school_history_fields.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'school_history_regression_test.dart'
    show MemorySchoolRepository, choose, dropdown;

class LearnerRepository extends MemorySchoolRepository {
  bool fail = false;
  int saves = 0, searches = 0;
  int total = 13;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #addLearnerWithSchoolHistory) {
      saves++;
      return fail
          ? Future<int>.error(StateError('Test save failure'))
          : Future<int>.value(42);
    }
    if (invocation.memberName == #getSchoolYearsForSearch ||
        invocation.memberName == #getSectionsForSearch) {
      return Future<List<Map<String, Object?>>>.value([]);
    }
    if (invocation.memberName == #countActiveLearners) {
      return Future<int>.value(total);
    }
    if (invocation.memberName == #searchIncidentRecords) {
      searches++;
      final query = invocation.namedArguments[#lastName]?.toString() ?? '';
      final count = query.isEmpty
          ? total
          : query == 'Match'
              ? 3
              : 0;
      return Future<List<Map<String, Object?>>>.value(List.generate(
          count,
          (i) => {
                'LearnerID': i + 1,
                'LastName': 'Match',
                'FirstName': 'Learner $i'
              }));
    }
    return super.noSuchMethod(invocation);
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  setUpAll(() async {
    sqfliteFfiInit();
    temp = await Directory.systemTemp.createTemp('navigation_regression_');
    // All path-provider calls are redirected before any widget is constructed.
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => temp.path);
    final locations = await LocationsDatabase.instance.database;
    expect(locations.path, startsWith(temp.path));
  });
  tearDownAll(() async {
    await LocationsDatabase.instance.close();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'), null);
    await temp.delete(recursive: true);
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Finder field(String label) => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == label);

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
    }
    await tester.pumpAndSettle(const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
  }

  for (final caller in ['Home', 'Search/Learner List', 'Other caller']) {
    testWidgets('$caller receives saved learner ID without duplicate routes',
        (tester) async {
      final repo = LearnerRepository();
      int? result;
      await tester.binding.setSurfaceSize(const Size(1500, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Builder(
        builder: (context) => TextButton(
            child: Text(caller),
            onPressed: () async {
              result = await Navigator.push<int>(
                  context,
                  MaterialPageRoute(
                      builder: (_) => AddLearnerScreen(
                          repository: repo,
                          schoolNameLoader: () async => 'Test School')));
            }),
      ))));
      await tester.tap(find.text(caller));
      await settle(tester);
      await tester.enterText(field('Last Name *'), 'Test');
      await tester.enterText(field('First Name *'), 'Learner');
      await choose(tester, 'Sex *', 'Male');
      expect(find.byType(SchoolHistoryFields), findsOneWidget);
      expect(
          tester
              .widget<SchoolHistoryFields>(find.byType(SchoolHistoryFields))
              .year
              .text,
          SchoolYear.current());
      final save = find.widgetWithText(FilledButton, 'Save Learner');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await settle(tester);
      expect(result, 42);
      expect(repo.saves, 1);
      expect(find.text(caller), findsOneWidget);
      expect(find.byType(AddLearnerScreen), findsNothing);
      expect(tester.state<NavigatorState>(find.byType(Navigator)).canPop(),
          isFalse);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('Back returns to the actual caller without saving',
      (tester) async {
    final repo = LearnerRepository();
    int? result;
    await tester.binding.setSurfaceSize(const Size(1500, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
      builder: (context) => TextButton(
          child: const Text('Original caller'),
          onPressed: () async {
            result = await Navigator.push<int>(
                context,
                MaterialPageRoute(
                    builder: (_) => AddLearnerScreen(
                        repository: repo,
                        schoolNameLoader: () async => 'Test School')));
          }),
    ))));
    await tester.tap(find.text('Original caller'));
    await settle(tester);
    await tester.pageBack();
    await settle(tester);
    expect(find.text('Original caller'), findsOneWidget);
    expect(result, isNull);
    expect(repo.saves, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('invalid/failed save stays on form; Cancel returns no success',
      (tester) async {
    final repo = LearnerRepository()..fail = true;
    int? result;
    await tester.binding.setSurfaceSize(const Size(1500, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
      builder: (context) => TextButton(
          child: const Text('Caller'),
          onPressed: () async {
            result = await Navigator.push<int>(
                context,
                MaterialPageRoute(
                    builder: (_) => AddLearnerScreen(
                        repository: repo,
                        schoolNameLoader: () async => 'Test School')));
          }),
    ))));
    await tester.tap(find.text('Caller'));
    await settle(tester);
    final save = find.widgetWithText(FilledButton, 'Save Learner');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await settle(tester);
    expect(repo.saves, 0);
    expect(find.byType(AddLearnerScreen), findsOneWidget);
    await tester.ensureVisible(field('Last Name *'));
    await tester.enterText(field('Last Name *'), 'Test');
    await tester.enterText(field('First Name *'), 'Learner');
    await choose(tester, 'Sex *', 'Male');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await settle(tester);
    expect(repo.saves, 1);
    expect(find.byType(AddLearnerScreen), findsOneWidget);
    expect(result, isNull);
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(find.text('Caller'), findsOneWidget);
    expect(result, isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'Search counts follow applied criteria, not keystrokes or page size; Reset clears',
      (tester) async {
    final repo = LearnerRepository();
    await tester.binding.setSurfaceSize(const Size(1500, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: SearchScreen(repository: repo),
      routes: {
        '/view': (context) => Scaffold(
            body: TextButton(
                onPressed: () {
                  repo.total = 14;
                  Navigator.pop(context, true);
                },
                child: const Text('Return after data change')))
      },
    ));
    await settle(tester);
    expect(find.text('Total Learners: 13'), findsOneWidget);
    expect(find.textContaining('Matching Learners:'), findsNothing);
    final searches = repo.searches;
    await tester.enterText(field('Family Name'), 'Match');
    await tester.pump();
    expect(repo.searches, searches);
    final search = find.widgetWithText(FilledButton, 'Search');
    await tester.ensureVisible(search);
    await tester.tap(search);
    await settle(tester);
    expect(find.text('Matching Learners: 3'), findsOneWidget);
    await tester.ensureVisible(field('Family Name'));
    await tester.enterText(field('Family Name'), 'None');
    await tester.ensureVisible(search);
    await tester.tap(search);
    await settle(tester);
    expect(find.text('Matching Learners: 0'), findsOneWidget);
    await choose(tester, 'Current Grade Level', 'Grade 7');
    expect(
        tester
            .state<FormFieldState<String>>(dropdown('Current Grade Level'))
            .value,
        '7');
    await tester.ensureVisible(find.text('Reset'));
    await tester.tap(find.text('Reset'));
    await settle(tester);
    expect(
        tester
            .state<FormFieldState<String>>(dropdown('Current Grade Level'))
            .value,
        isNull);
    expect(tester.widget<TextField>(field('Family Name')).controller!.text,
        isEmpty);
    expect(find.textContaining('Matching Learners:'), findsNothing);
    expect(find.text('Total Learners: 13'), findsOneWidget);
    expect(find.text('Page 1 of 2'), findsOneWidget);
    await tester.ensureVisible(find.textContaining('Match, Learner 0'));
    await tester.tap(find.textContaining('Match, Learner 0'));
    // The row supports double-tap; advance the fake clock past that window
    // before expecting its single-tap selection action.
    await tester.pump(const Duration(milliseconds: 350));
    await settle(tester);
    await tester.ensureVisible(find.byTooltip('View Record'));
    await tester.tap(find.byTooltip('View Record'));
    await tester.pump(const Duration(milliseconds: 350));
    await settle(tester);
    await tester.tap(find.text('Return after data change'));
    await settle(tester);
    expect(find.text('Total Learners: 14'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
