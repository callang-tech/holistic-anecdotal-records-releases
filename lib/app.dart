import 'package:flutter/material.dart';

import 'theme/app_theme.dart';

import 'screens/add_learner_screen.dart';
import 'screens/admin_task_screen.dart';
import 'screens/home_screen.dart';
import 'screens/print_screen.dart';
import 'screens/search_screen.dart';
import 'screens/view_screen.dart';
import 'screens/admin_import_screen.dart';
import 'screens/admin_tools_screen.dart';
import 'screens/sync_screen.dart';
import 'screens/settings_screen.dart';

class HolisticAnecdotalApp extends StatefulWidget {
const HolisticAnecdotalApp({super.key});

@override
State<HolisticAnecdotalApp> createState() =>
_HolisticAnecdotalAppState();
}

class _HolisticAnecdotalAppState
extends State<HolisticAnecdotalApp> {
late final AppThemeController _themeController;

@override
void initState() {
super.initState();


_themeController = AppThemeController();

_initializeTheme();


}

Future<void> _initializeTheme() async {
await _themeController.initialize();


if (mounted) {
  setState(() {});
}


}

@override
void dispose() {
_themeController.dispose();
super.dispose();
}

@override
Widget build(BuildContext context) {
return AnimatedBuilder(
animation: _themeController,
builder: (context, child) {
return MaterialApp(
title:
'Holistic Educational Anecdotal Record & Tracking System',
debugShowCheckedModeBanner: false,


      theme: _themeController.theme,

      initialRoute: '/',

      routes: {
        '/': (_) => const HomeScreen(),

        '/search': (_) => const SearchScreen(),

        '/add-learner': (_) => const AddLearnerScreen(),

        '/admin': (_) => const AdminTaskScreen(),

        '/view': (_) => const ViewScreen(),

        '/print': (_) => const PrintScreen(),

        '/admin-import': (_) => const AdminImportScreen(),

        '/admin-tools': (_) => const AdminToolsScreen(),

        '/sync': (_) => const SyncScreen(),

        '/settings': (_) => SettingsScreen(
              themeController: _themeController,
            ),
      },
    );
  },
);


}
}
