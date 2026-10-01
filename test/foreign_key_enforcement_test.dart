import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:holistic_anecdotal_records/database/app_database.dart';
import 'package:holistic_anecdotal_records/database/database_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late AppDatabase app;
  late DatabaseRepository repository;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('foreign_key_test_');
    app = AppDatabase.forTesting('${directory.path}/test.db');
    await app.initialize();
    repository = DatabaseRepository.forTesting(app);
  });

  tearDown(() async {
    await app.database.close();
    await directory.delete(recursive: true);
  });

  Future<int> learner() => app.database.insert('LEARNERS_Table', {
        'LastName': 'Parent',
        'FirstName': 'Test',
        'Sex': 'Female',
        'CreatedAt': '2026-01-01',
        'UpdatedAt': '2026-01-01',
        'DeviceID': 'test',
      });

  Future<int> child(String table, int learnerId) => app.database.insert(table, {
        'LearnerID': learnerId,
        if (table == 'SCHOOL_HISTORY_Table') ...{
          'SchoolYear': '2026',
          'Grade': '9',
          'School': 'School',
        } else ...{
          'IncidentDate': '2026-01-01',
          'BehaviorProblem': 'Observation',
        },
        'CreatedAt': '2026-01-01',
        'UpdatedAt': '2026-01-01',
        'DeviceID': 'test',
      });

  test('main database enables foreign keys on initialization and reopen',
      () async {
    expect(
        (await app.database.rawQuery('PRAGMA foreign_keys'))
            .single
            .values
            .single,
        1);
    await app.database.close();
    app = AppDatabase.forTesting('${directory.path}/test.db');
    await app.initialize();
    expect(
        (await app.database.rawQuery('PRAGMA foreign_keys'))
            .single
            .values
            .single,
        1);
  });

  for (final table in ['SCHOOL_HISTORY_Table', 'INCIDENTS_Table']) {
    test('$table rejects a nonexistent parent at SQLite level', () async {
      await expectLater(child(table, 999), throwsA(isA<DatabaseException>()));
      expect(await app.database.query(table), isEmpty);
    });

    test('$table accepts active, archived and retained deleted parents',
        () async {
      for (final deleted in [0, 1, 2]) {
        final id = await learner();
        await app.database.update('LEARNERS_Table', {'Deleted': deleted},
            where: 'LearnerID = ?', whereArgs: [id]);
        expect(await child(table, id), greaterThan(0));
      }
      expect(await app.database.query(table), hasLength(3));
      expect(await app.database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    });
  }

  test('archive, restore and permanent-delete markers preserve children',
      () async {
    final id = await learner();
    await child('SCHOOL_HISTORY_Table', id);
    await child('INCIDENTS_Table', id);
    expect(await repository.archiveLearner(learnerId: id), 1);
    expect(await repository.restoreLearner(learnerId: id), 1);
    expect(await repository.archiveLearner(learnerId: id), 1);
    expect(await repository.permanentlyDeleteLearner(learnerId: id), 1);
    expect((await app.database.query('LEARNERS_Table')).single['Deleted'], 2);
    expect(await app.database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });
}
