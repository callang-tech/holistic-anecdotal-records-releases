import 'locations_database.dart';

class LocationsRepository {
  LocationsRepository._() : _database = LocationsDatabase.instance;

  LocationsRepository.forTesting(LocationsDatabase database)
      : _database = database;

  static final LocationsRepository instance = LocationsRepository._();

  final LocationsDatabase _database;

  Future<List<Map<String, Object?>>> getRegions() async {
    final db = await _database.database;

    return db.query(
      'locations',
      where: '''
        geographic_level = ?
        AND is_active = 1
      ''',
      whereArgs: ['Reg'],
      orderBy: 'name COLLATE NOCASE',
    );
  }

  Future<List<Map<String, Object?>>> getProvinces(
    int regionId,
  ) async {
    final db = await _database.database;

    return db.query(
      'locations',
      where: '''
        geographic_level = ?
        AND parent_id = ?
        AND is_active = 1
      ''',
      whereArgs: [
        'Prov',
        regionId,
      ],
      orderBy: 'name COLLATE NOCASE',
    );
  }

  /// Returns cities/municipalities directly under a region.
  ///
  /// This is important for NCR and other independent cities
  /// that do not belong to a province.
  Future<List<Map<String, Object?>>> getIndependentCitiesMunicipalities(
    int regionId,
  ) async {
    final db = await _database.database;

    return db.query(
      'locations',
      where: '''
        geographic_level IN (?, ?)
        AND parent_id = ?
        AND is_active = 1
      ''',
      whereArgs: [
        'City',
        'Mun',
        regionId,
      ],
      orderBy: 'name COLLATE NOCASE',
    );
  }

  /// Returns cities/municipalities belonging to a province.
  Future<List<Map<String, Object?>>> getCitiesMunicipalities(
    int provinceId,
  ) async {
    final db = await _database.database;

    return db.query(
      'locations',
      where: '''
        geographic_level IN (?, ?)
        AND parent_id = ?
        AND is_active = 1
      ''',
      whereArgs: [
        'City',
        'Mun',
        provinceId,
      ],
      orderBy: 'name COLLATE NOCASE',
    );
  }

  Future<List<Map<String, Object?>>> getBarangays(
    int cityMunicipalityId,
  ) async {
    final db = await _database.database;

    return db.query(
      'locations',
      where: '''
        geographic_level = ?
        AND parent_id = ?
        AND is_active = 1
      ''',
      whereArgs: [
        'Bgy',
        cityMunicipalityId,
      ],
      orderBy: 'name COLLATE NOCASE',
    );
  }

  Future<Map<String, Object?>?> getLocationById(
    int id,
  ) async {
    final db = await _database.database;

    final rows = await db.query(
      'locations',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return rows.first;
  }
}
