import 'dart:io';

import 'package:path_provider/path_provider.dart';

class SchoolSettingsService {
  SchoolSettingsService._();

  static final SchoolSettingsService instance =
      SchoolSettingsService._();

  static const String defaultSchoolName =
      'Callang National High School';

  Future<File> _settingsFile() async {
    final documentsDirectory =
        await getApplicationDocumentsDirectory();

    final appDirectory = Directory(
      '${documentsDirectory.path}'
      '${Platform.pathSeparator}'
      'HolisticAnecdotalRecords',
    );

    if (!await appDirectory.exists()) {
      await appDirectory.create(recursive: true);
    }

    return File(
      '${appDirectory.path}'
      '${Platform.pathSeparator}'
      'school_name.txt',
    );
  }

  Future<String> getSchoolName() async {
    try {
      final file = await _settingsFile();

      if (!await file.exists()) {
        return defaultSchoolName;
      }

      final value = (await file.readAsString()).trim();

      return value.isEmpty ? defaultSchoolName : value;
    } catch (_) {
      return defaultSchoolName;
    }
  }

  Future<void> setSchoolName(String schoolName) async {
    final value = schoolName.trim();

    if (value.isEmpty) {
      throw ArgumentError('School name cannot be empty.');
    }

    final file = await _settingsFile();
    await file.writeAsString(value, flush: true);
  }
}
