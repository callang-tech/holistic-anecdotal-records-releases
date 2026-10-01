import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holistic_anecdotal_records/database/locations_database.dart';
import 'package:holistic_anecdotal_records/database/locations_repository.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory temp;
  late Directory support;
  late LocationsDatabase locations;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('locations_path_test_');
    support = Directory(p.join(temp.path, 'user_support'));
    locations = LocationsDatabase.forTesting(
      supportDirectory: () async => support,
    );
  });

  tearDown(() async {
    await locations.close();
    await temp.delete(recursive: true);
  });

  test('copies the bundled reference to support storage and opens read-only',
      () async {
    final db = await locations.database;
    expect(db.path, p.join(support.path, 'reference_data', 'locations.db'));
    final asset = await rootBundle.load('assets/database/locations.db');
    expect(await File(db.path).readAsBytes(),
        asset.buffer.asUint8List(asset.offsetInBytes, asset.lengthInBytes));
    await expectLater(db.execute('CREATE TABLE forbidden_write (id INTEGER)'),
        throwsA(isA<DatabaseException>()));
    expect(await File('${db.path}.pending').exists(), isFalse);
  });

  test('concurrent callers share one copy and existing copy is reused',
      () async {
    final opened = await Future.wait([locations.database, locations.database]);
    expect(identical(opened[0], opened[1]), isTrue);
    final file = File(opened[0].path);
    await locations.close();
    final marker = DateTime(2001, 1, 1);
    await file.setLastModified(marker);
    final before = await file.lastModified();
    await locations.database;
    expect(await file.lastModified(), before);
  });

  test('support lookup failure does not fall back to a working-directory copy',
      () async {
    final unavailable = LocationsDatabase.forTesting(
      supportDirectory: () async => throw StateError('Support unavailable'),
    );
    await expectLater(unavailable.database, throwsStateError);
    final relative = LocationsDatabase.forTesting(
      supportDirectory: () async => Directory('relative_support'),
    );
    await expectLater(relative.database, throwsStateError);
    expect(await temp.list().toList(), isEmpty);
  });

  test('real PSGC hierarchy and lookup queries are preserved', () async {
    final repository = LocationsRepository.forTesting(locations);
    final regions = await repository.getRegions();
    expect(regions, isNotEmpty);
    final region = regions
        .firstWhere((row) => row['name'] == 'Region II (Cagayan Valley)');
    final provinces = await repository.getProvinces(region['id'] as int);
    final isabela = provinces.firstWhere((row) => row['name'] == 'Isabela');
    final cities =
        await repository.getCitiesMunicipalities(isabela['id'] as int);
    expect(cities, isNotEmpty);
    final barangays = await repository.getBarangays(cities.first['id'] as int);
    expect(barangays, isNotEmpty);
    final barangay = barangays.first;
    expect(await repository.getLocationById(barangay['id'] as int), barangay);
    expect(await repository.getLocationById(-1), isNull);
    final independent = <Map<String, Object?>>[];
    for (final row in regions) {
      independent.addAll(await repository
          .getIndependentCitiesMunicipalities(row['id'] as int));
    }
    expect(independent, isNotEmpty);
  });
}
