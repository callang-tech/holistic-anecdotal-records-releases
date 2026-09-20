import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class LocationsDatabase {
  LocationsDatabase._();

  static final LocationsDatabase instance =
      LocationsDatabase._();

  Database? _database;

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }

    _database = await _openDatabase();

    return _database!;
  }

  Future<Database> _openDatabase() async {
    final databasePath =
        await databaseFactoryFfi.getDatabasesPath();

    final path = p.join(
      databasePath,
      'locations.db',
    );

    final exists =
        await databaseFactoryFfi.databaseExists(path);

    if (!exists) {
      await _copyBundledDatabase(path);
    }

    return databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        readOnly: true,
      ),
    );
  }

  Future<void> _copyBundledDatabase(
    String destination,
  ) async {
    final data = await rootBundle.load(
      'assets/database/locations.db',
    );

    final bytes = data.buffer.asUint8List();

    final file = File(destination);

    await file.parent.create(
      recursive: true,
    );

    await file.writeAsBytes(
      bytes,
      flush: true,
    );
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}