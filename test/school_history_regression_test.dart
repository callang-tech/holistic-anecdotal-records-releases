import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holistic_anecdotal_records/database/app_database.dart';
import 'package:holistic_anecdotal_records/database/database_repository.dart';
import 'package:holistic_anecdotal_records/models/school_year.dart';
import 'package:holistic_anecdotal_records/widgets/school_history_fields.dart';
import 'package:holistic_anecdotal_records/widgets/school_year_field.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MemorySchoolRepository implements DatabaseRepository {
  final sections = <Map<String, Object?>>[];
  final teachers = <Map<String, Object?>>[];
  @override
  Future<List<Map<String, Object?>>> getSections(
          {String? schoolYear, String? gradeLevel}) async =>
      sections
          .where((s) =>
              (schoolYear == null ||
                  SchoolYear.normalize(s['SchoolYear']) ==
                      SchoolYear.normalize(schoolYear)) &&
              (gradeLevel == null ||
                  normalizedGrade(s['GradeLevel']) ==
                      normalizedGrade(gradeLevel)))
          .toList();
  @override
  Future<List<Map<String, Object?>>> getTeachers() async => teachers;
  @override
  Future<int> addSection(
      {required String schoolYear,
      required String gradeLevel,
      required String sectionName,
      required String adviser}) async {
    final id = sections.length + 1;
    sections.add({
      'SectionID': id,
      'SchoolYear': schoolYear,
      'GradeLevel': gradeLevel,
      'SectionName': sectionName,
      'Adviser': adviser
    });
    return id;
  }

  @override
  Future<int> addTeacher(
      {required String teacherName,
      String? mobileNumber,
      String status = 'Active'}) async {
    final id = teachers.length + 1;
    teachers.add({
      'TeacherID': id,
      'TeacherName': teacherName,
      'MobileNumber': mobileNumber,
      'Status': status
    });
    return id;
  }

  @override
  Future<int> updateSection(int id,
      {String? schoolYear,
      String? gradeLevel,
      String? sectionName,
      String? adviser}) async {
    sections.firstWhere((r) => r['SectionID'] == id)['Adviser'] = adviser;
    return 1;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Finder dropdown(String label) => find.byWidgetPredicate((w) =>
    w is DropdownButtonFormField<String> && w.decoration.labelText == label);

Future<void> choose(WidgetTester tester, String label, String value) async {
  await tester.ensureVisible(dropdown(label));
  await tester.tap(dropdown(label));
  await tester.pumpAndSettle();
  await tester.tap(find.text(value).last);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final date = DateTime(2026, 9, 26);
  test('June 1 boundary and exactly five newest-to-oldest school years', () {
    expect(SchoolYear.current(date: DateTime(2026, 5, 31)), '2025–2026');
    expect(SchoolYear.current(date: DateTime(2026, 6, 1)), '2026–2027');
    expect(SchoolYear.options(date: date),
        ['2026–2027', '2025–2026', '2024–2025', '2023–2024', '2022–2023']);
    expect(
        SchoolYear.options(date: date).first, SchoolYear.current(date: date));
  });
  test('stored historical year and legacy spelling are preserved', () {
    expect(
        SchoolYear.options(date: date, stored: '2010-2011').last, '2010-2011');
    final years = SchoolYear.options(date: date, stored: '2022-2023');
    expect(years.length, 5);
    expect(years.last, '2022-2023');
  });

  group('shared Add/Edit history fields', () {
    late MemorySchoolRepository repo;
    late TextEditingController year, section, adviser;
    String? grade;
    setUp(() {
      repo = MemorySchoolRepository();
      year = TextEditingController(text: '2022-2023');
      section = TextEditingController(text: 'Historical Section');
      adviser = TextEditingController(text: 'Historical Adviser');
      grade = '8';
      repo.sections.addAll([
        {
          'SectionID': 1,
          'SchoolYear': '2022–2023',
          'GradeLevel': '8',
          'SectionName': 'Historical Section',
          'Adviser': 'Changed Maintenance Adviser'
        },
        {
          'SectionID': 2,
          'SchoolYear': '2022–2023',
          'GradeLevel': '8',
          'SectionName': 'Other',
          'Adviser': 'Other Teacher'
        },
        {
          'SectionID': 3,
          'SchoolYear': '2022–2023',
          'GradeLevel': '9',
          'SectionName': 'Wrong Grade',
          'Adviser': ''
        },
        {
          'SectionID': 4,
          'SchoolYear': '2023–2024',
          'GradeLevel': '8',
          'SectionName': 'Next Year',
          'Adviser': ''
        },
      ]);
    });
    tearDown(() {
      year.dispose();
      section.dispose();
      adviser.dispose();
    });
    Future<void> mount(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
        child: StatefulBuilder(
            builder: (context, setState) => SchoolHistoryFields(
                repository: repo,
                year: year,
                section: section,
                adviser: adviser,
                grade: grade,
                onGradeChanged: (v) => setState(() => grade = v))),
      ))));
      await tester.pumpAndSettle();
    }

    testWidgets(
        'edit preserves stored adviser; section change resolves assignment',
        (tester) async {
      await mount(tester);
      expect(adviser.text, 'Historical Adviser');
      final field = tester.widget<DropdownButton<String>>(find.descendant(
          of: dropdown('Section'),
          matching: find.byType(DropdownButton<String>)));
      expect(field.items!.map((i) => i.value),
          ['', 'Historical Section', 'Other']);
      await choose(tester, 'Section', 'Other');
      expect(adviser.text, 'Other Teacher');
      await tester.pumpWidget(const SizedBox());
    });
    testWidgets('year change clears stale section/adviser; no adviser is safe',
        (tester) async {
      await mount(tester);
      await choose(tester, 'School Year *', '2023–2024');
      expect(section.text, isEmpty);
      expect(adviser.text, isEmpty);
      await choose(tester, 'Section', 'Next Year');
      expect(adviser.text, isEmpty);
      await tester.pumpWidget(const SizedBox());
    });
    testWidgets('grade change clears stale values and handles no matches',
        (tester) async {
      await mount(tester);
      await choose(tester, 'Grade Level *', '10');
      expect(section.text, isEmpty);
      expect(adviser.text, isEmpty);
      expect(find.text('No sections for this school year and grade.'),
          findsOneWidget);
      expect(find.text('Add New Section'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
    testWidgets(
        'quick-add cancel preserves parent; section inherits historical context',
        (tester) async {
      await mount(tester);
      await tester.tap(find.text('Add New Section'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Canceled');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repo.sections.length, 4);
      expect(section.text, 'Historical Section');
      expect(adviser.text, 'Historical Adviser');
      await tester.tap(find.text('Add New Section'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'New Historical');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(repo.sections.last['SchoolYear'], '2022-2023');
      expect(repo.sections.last['GradeLevel'], '8');
      expect(section.text, 'New Historical');
      expect(adviser.text, isEmpty);
      expect(find.byType(SchoolHistoryFields), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
    testWidgets(
        'quick-add adviser cancel writes nothing; save selects and assigns teacher',
        (tester) async {
      await mount(tester);
      await tester.tap(find.text('Add New Adviser'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Canceled');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repo.teachers, isEmpty);
      expect(adviser.text, 'Historical Adviser');
      await tester.tap(find.text('Add New Adviser'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'New Teacher');
      await tester.enterText(find.byType(TextField).last, '09123456789');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(repo.teachers.single['MobileNumber'], '09123456789');
      expect(repo.teachers.single['Status'], 'Active');
      expect(adviser.text, 'New Teacher');
      expect(repo.sections.first['Adviser'], 'New Teacher');
      expect(year.text, '2022-2023');
      expect(grade, '8');
      await tester.pumpWidget(const SizedBox());
    });
    testWidgets('older historical value remains in dropdown unchanged',
        (tester) async {
      year.text = '2010-2011';
      await mount(tester);
      expect(year.text, '2010-2011');
      expect(section.text, 'Historical Section');
      expect(find.byType(SchoolYearField), findsOneWidget);
      expect(
          tester
              .widget<DropdownButton<String>>(find.descendant(
                  of: dropdown('School Year *'),
                  matching: find.byType(DropdownButton<String>)))
              .items!
              .map((i) => i.value),
          contains('2010-2011'));
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('maintenance tables and learner counts in temporary SQLite', () {
    late Directory temp;
    late AppDatabase app;
    late DatabaseRepository repo;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      temp = await Directory.systemTemp.createTemp('school_regression_');
      app = AppDatabase.forTesting('${temp.path}/test.db');
      await app.initialize();
      repo = DatabaseRepository.forTesting(app);
    });
    tearDown(() async {
      await app.database.close();
      await temp.delete(recursive: true);
    });
    test(
        'same tables, normalized duplicate prevention and reuse across school years',
        () async {
      final teacher =
          await repo.addTeacher(teacherName: 'Jane Smith', mobileNumber: '123');
      expect(await repo.addTeacher(teacherName: '  jane   SMITH '), teacher);
      final section = await repo.addSection(
          schoolYear: '2022-2023',
          gradeLevel: '8',
          sectionName: 'Blue Room',
          adviser: 'Jane Smith');
      expect(
          await repo.addSection(
              schoolYear: '2022–2023',
              gradeLevel: 'Grade 8',
              sectionName: ' blue   ROOM ',
              adviser: ''),
          section);
      await repo.addSection(
          schoolYear: '2023–2024',
          gradeLevel: '8',
          sectionName: 'Blue Room',
          adviser: 'Jane Smith');
      await repo.addSection(
          schoolYear: '2022–2023',
          gradeLevel: '9',
          sectionName: 'Blue Room',
          adviser: '');
      expect((await repo.getTeachers()).length, 1);
      expect((await repo.getSections()).length, 3);
      final filtered =
          await repo.getSections(schoolYear: '2022–2023', gradeLevel: '8');
      expect(filtered.single['SectionID'], section);
      expect((await app.database.query('TEACHERS_Table')).length, 1);
      expect((await app.database.query('SECTIONS_Table')).length, 3);
      expect(await repo.getSections(schoolYear: '2000–2001', gradeLevel: '8'),
          isEmpty);
    });
    test(
        'total, combined search, no matches, deleted exclusion and caller refresh',
        () async {
      expect(await repo.countActiveLearners(), 0);
      final ids = <int>[];
      for (var i = 0; i < 5; i++) {
        ids.add(await repo.addLearner(
            lastName: i < 3 ? 'Match' : 'Other',
            firstName: 'Learner $i',
            sex: 'Male',
            age: i == 0 ? 12 : 13));
      }
      expect(await repo.countActiveLearners(), 5);
      expect(
          DatabaseRepository.matchingLearnerCount(
              await repo.searchIncidentRecords(lastName: 'Match')),
          3);
      expect(
          DatabaseRepository.matchingLearnerCount(
              await repo.searchIncidentRecords(lastName: 'Match', age: 13)),
          2);
      expect(
          DatabaseRepository.matchingLearnerCount(
              await repo.searchIncidentRecords(lastName: 'Absent')),
          0);
      await repo.deleteLearner(ids.last);
      expect(await repo.countActiveLearners(), 4);
      expect(
          DatabaseRepository.matchingLearnerCount(
              await repo.searchIncidentRecords()),
          4);
      await repo.addLearner(
          lastName: 'Added', firstName: 'After return', sex: 'Female');
      expect(await repo.countActiveLearners(), 5);
    });
    test(
        'combined incident/history filters count distinct learners with en-dash years',
        () async {
      final id = await repo.addLearner(
          lastName: 'Match', firstName: 'One', sex: 'Male');
      await repo.addSchoolHistory(
          learnerId: id,
          schoolYear: '2026–2027',
          grade: '8',
          school: 'Test',
          section: 'Blue',
          adviser: 'Jane');
      for (final day in [1, 2]) {
        await repo.addIncident(
            learnerId: id,
            incidentDate: '2026-09-0$day',
            observer: 'Jane',
            behaviorProblem: 'Late');
      }
      final results = await repo.searchIncidentRecords(
          lastName: 'Match',
          schoolYearLastEnrolled: '2026-2027',
          incidentGradeLevel: '8',
          section: 'Blue',
          observer: 'Jane');
      expect(results.length, 2);
      expect(DatabaseRepository.matchingLearnerCount(results), 1);
      await repo.archiveLearner(learnerId: id);
      expect(await repo.countActiveLearners(), 0);
      expect(await repo.searchIncidentRecords(observer: 'Jane'), isEmpty);
    });
    test(
        'all matches counted before pagination; incident duplicates counted once',
        () async {
      for (var i = 0; i < 13; i++) {
        await repo.addLearner(lastName: 'Match', firstName: '$i', sex: 'Male');
      }
      final results = await repo.searchIncidentRecords(lastName: 'Match');
      expect(results.take(10).length, 10);
      expect(DatabaseRepository.matchingLearnerCount(results), 13);
      expect(DatabaseRepository.matchingLearnerCount([...results, ...results]),
          13);
    });
  });
}
