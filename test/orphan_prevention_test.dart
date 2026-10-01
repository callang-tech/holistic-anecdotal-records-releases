import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:holistic_anecdotal_records/database/app_database.dart';
import 'package:holistic_anecdotal_records/database/database_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late AppDatabase app;
  late DatabaseRepository repository;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('orphan_prevention_');
    app = AppDatabase.forTesting('${directory.path}/test.db');
    await app.initialize();
    // Deliberately exercise application validation without SQLite enforcement.
    await app.database.execute('PRAGMA foreign_keys = OFF');
    repository = DatabaseRepository.forTesting(app);
  });

  tearDown(() async {
    await app.database.close();
    await directory.delete(recursive: true);
  });

  Future<int> parent(int deleted) => app.database.insert('LEARNERS_Table', {
        'FirstName': 'Test',
        'LastName': 'Parent',
        'Sex': 'Male',
        'CreatedAt': '2020-01-01',
        'UpdatedAt': '2020-01-01',
        'DeviceID': 'test',
        'Version': 1,
        'Deleted': deleted,
      });

  Future<Map<String, List<Map<String, Object?>>>> snapshot() async {
    final result = <String, List<Map<String, Object?>>>{};
    final tables = await app.database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name");
    for (final table in tables) {
      final name = table['name'] as String;
      result[name] = await app.database.query(name);
    }
    return result;
  }

  for (final history in [true, false]) {
    final table = history ? 'SCHOOL_HISTORY_Table' : 'INCIDENTS_Table';
    final key = history ? 'SchoolHistoryID' : 'IncidentID';
    Future<int> add(int learnerId) => history
        ? repository.addSchoolHistory(
            learnerId: learnerId,
            schoolYear: '2026',
            grade: '9',
            school: 'School')
        : repository.addIncident(
            learnerId: learnerId,
            incidentDate: '2026-01-01',
            behaviorProblem: 'Test');
    Future<int> update(int id) => history
        ? repository.updateSchoolHistory(
            schoolHistoryId: id,
            schoolYear: '2027',
            grade: '10',
            school: 'Updated school')
        : repository.updateIncident(id, behaviorProblem: 'Updated');
    Future<Map<String, Object?>> row(int id) async =>
        (await app.database.query(table, where: '$key = ?', whereArgs: [id]))
            .single;

    for (final deleted in [0, 1, 2]) {
      test(
          '$table add and edit accept physically present parent Deleted=$deleted',
          () async {
        final learnerId = await parent(deleted);
        final id = await add(learnerId);
        final before = await row(id);
        expect(before['LearnerID'], learnerId);
        expect(before['Version'], 1);
        expect(await update(id), 1);
        final after = await row(id);
        expect(after['Version'], 2);
        expect(after[history ? 'School' : 'BehaviorProblem'],
            history ? 'Updated school' : 'Updated');
        for (final field in ['LearnerID', 'SyncID', 'CreatedAt', 'Deleted']) {
          expect(after[field], before[field]);
        }
        expect(after['UpdatedAt'], isNotNull);
        expect(after['DeviceID'], before['DeviceID']);
      });
    }

    test('$table missing parent add leaves entire database unchanged',
        () async {
      final before = await snapshot();
      await expectLater(
          add(999),
          throwsA(isA<StateError>().having((e) => e.message, 'message',
              contains('Learner 999 does not exist'))));
      expect(await snapshot(), before);
    });

    test('$table existing orphan cannot be edited or partially modified',
        () async {
      // Construct the historical-invalid fixture directly, not via repository.
      final id = await app.database.insert(table, {
        'LearnerID': 999,
        'SyncID': 'orphan',
        'Version': 8,
        'Deleted': 0,
        'CreatedAt': '2020-01-01',
        'UpdatedAt': '2020-01-02',
        'DeviceID': 'original',
        if (history) ...{
          'SchoolYear': '2026',
          'Grade': '9',
          'School': 'Original'
        },
        if (!history) ...{
          'IncidentDate': '2026-01-01',
          'BehaviorProblem': 'Original'
        },
      });
      final before = await snapshot();
      await expectLater(
          update(id),
          throwsA(isA<StateError>().having((e) => e.message, 'message',
              contains('Learner 999 does not exist'))));
      expect(await snapshot(), before);
    });

    test('$table missing child retains previous not-found behavior', () async {
      if (history) {
        expect(await update(999), 0);
      } else {
        await expectLater(update(999), throwsStateError);
      }
    });

    test('$table retains existing soft-deleted child edit behavior', () async {
      final id = await add(await parent(0));
      await app.database
          .update(table, {'Deleted': 1}, where: '$key = ?', whereArgs: [id]);
      final before = await row(id);
      if (history) {
        expect(await update(id), 1);
        expect((await row(id))['Deleted'], 1);
        expect((await row(id))['Version'], 2);
      } else {
        await expectLater(update(id), throwsStateError);
        expect(await row(id), before);
      }
    });
  }
}
