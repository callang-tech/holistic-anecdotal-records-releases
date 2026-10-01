import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class LocationsDatabase {
  LocationsDatabase._() : _supportDirectory = getApplicationSupportDirectory;

  @visibleForTesting
  LocationsDatabase.forTesting({
    required Future<Directory> Function() supportDirectory,
  }) : _supportDirectory = supportDirectory;

  final Future<Directory> Function() _supportDirectory;
  Future<Database>? _opening;

  static final LocationsDatabase instance = LocationsDatabase._();

  Database? _database;

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }

    // Selectors can request different levels concurrently during initialization.
    // Share the copy/open operation so they never read a partially copied file.
    try {
      _database = await (_opening ??= _openDatabase());
    } finally {
      _opening = null;
    }

    return _database!;
  }

  Future<Database> _openDatabase() async {
    // SQLite needs a real file, while Flutter supplies the reference as bytes.
    // Never use the working directory (which may be under Program Files).
    final supportDirectory = await _supportDirectory();
    if (!p.isAbsolute(supportDirectory.path)) {
      throw StateError('Application support directory must be absolute.');
    }

    final path = p.join(
      supportDirectory.path,
      'reference_data',
      'locations.db',
    );

    final exists = await databaseFactoryFfi.databaseExists(path);

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

    final bytes =
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

    final file = File(destination);

    await file.parent.create(
      recursive: true,
    );

    // Publish only a complete copy; an interrupted copy can be retried.
    final pending = File('$destination.pending');
    await pending.writeAsBytes(
      bytes,
      flush: true,
    );
    await pending.rename(destination);
  }

  Future<void> close() async {
    await _opening;
    await _database?.close();
    _database = null;
  }
}
