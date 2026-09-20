import 'package:flutter/material.dart';

import 'app.dart';
import 'database/app_database.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await AppDatabase.instance.initialize();

  runApp(
    const HolisticAnecdotalApp(),
  );
}
