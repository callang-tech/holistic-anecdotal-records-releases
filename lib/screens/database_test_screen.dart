import 'package:flutter/material.dart';

import '../database/database_repository.dart';

class DatabaseTestScreen extends StatefulWidget {
  const DatabaseTestScreen({super.key});

  @override
  State<DatabaseTestScreen> createState() => _DatabaseTestScreenState();
}

class _DatabaseTestScreenState extends State<DatabaseTestScreen> {
  String _result = 'Press the button to test SQLite.';

  bool _running = false;

  Future<void> _runTest() async {
    setState(() {
      _running = true;
      _result = 'Running database test...';
    });

    final result = await DatabaseRepository.instance.runDatabaseTest();

    if (!mounted) return;

    setState(() {
      _running = false;
      _result = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final successful = _result.contains('DATABASE TEST SUCCESSFUL');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Database Test'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  successful ? Icons.check_circle : Icons.storage,
                  size: 72,
                ),
                const SizedBox(height: 24),
                SelectableText(
                  _result,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _running ? null : _runTest,
                  icon: _running
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.play_arrow),
                  label: Text(
                    _running ? 'Testing...' : 'Run Database Test',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}