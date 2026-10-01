import 'dart:convert';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import '../services/dataset_key_service.dart';

class DataSecurityCard extends StatefulWidget {
  const DataSecurityCard({super.key, this.service});
  final DatasetKeyService? service;
  @override
  State<DataSecurityCard> createState() => _DataSecurityCardState();
}

class _DataSecurityCardState extends State<DataSecurityCard> {
  late final _service = widget.service ?? DatasetKeyService.instance;
  bool _busy = false;
  bool? _configured;
  String? _message;
  static const _fileType =
      XTypeGroup(label: 'Recovery file', extensions: ['harkey']);

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final configured = await _service.load() != null;
      if (mounted) setState(() => _configured = configured);
    } catch (_) {
      if (mounted) {
        setState(() {
          _configured = null;
          _message =
              'Secure storage is unavailable. Cloud synchronization is blocked.';
        });
      }
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(() => _message = e is DataSecurityException
            ? e.message
            : 'The operation could not be completed. No insecure fallback was used.');
      }
    } finally {
      await _refresh();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String message) async =>
      await showDialog<bool>(
          context: context,
          builder: (dialog) => AlertDialog(
                title: Text(title),
                content: Text(message),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialog, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(dialog, true),
                      child: const Text('Continue')),
                ],
              )) ??
      false;

  Future<String?> _password(
      {required bool exporting, bool cloud = false}) async {
    final password = TextEditingController();
    final confirmation = TextEditingController();
    String? error;
    final result = await showDialog<String>(
        context: context,
        builder: (dialog) => StatefulBuilder(
            builder: (context, update) => AlertDialog(
                  title: Text(cloud
                      ? 'Cloud Encryption Passphrase'
                      : exporting
                          ? 'Protect Recovery File'
                          : 'Unlock Recovery File'),
                  content: SizedBox(
                      width: 420,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(cloud
                            ? 'Enter the exact same unique passphrase on all devices. Use at least 16 characters. Spaces and letter case matter. Keep a secure copy; the app does not save the passphrase.'
                            : exporting
                                ? 'Choose a strong recovery password of at least 16 characters. Keep it separately from the file.'
                                : 'Enter the password used when this recovery file was exported.'),
                        const SizedBox(height: 12),
                        TextField(
                            controller: password,
                            obscureText: true,
                            enableSuggestions: false,
                            autocorrect: false,
                            decoration: InputDecoration(
                                labelText: cloud
                                    ? 'Cloud passphrase'
                                    : 'Recovery password')),
                        if (exporting)
                          TextField(
                              controller: confirmation,
                              obscureText: true,
                              enableSuggestions: false,
                              autocorrect: false,
                              decoration: InputDecoration(
                                  labelText: cloud
                                      ? 'Confirm cloud passphrase'
                                      : 'Confirm recovery password')),
                        if (error != null) Text(error!),
                      ])),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(dialog),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: () {
                          if (password.text.isEmpty ||
                              (exporting &&
                                  (password.text.runes.length < 16 ||
                                      password.text != confirmation.text))) {
                            update(() => error =
                                'Check the password length and confirmation.');
                            return;
                          }
                          Navigator.pop(dialog, password.text);
                        },
                        child: const Text('Continue')),
                  ],
                )));
    // Controllers must outlive the dialog's reverse transition.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    password.dispose();
    confirmation.dispose();
    return result;
  }

  Future<void> _setup() => _run(() async {
        if (!await _confirm('Set Up Encryption?',
            'Use the same cloud passphrase on every device. Use a fresh Sheet for new encrypted records; plaintext cloud records are rejected. No local or cloud data will be cleared.')) {
          return;
        }
        final replacing = _configured == true;
        if (replacing &&
            !await _confirm('Replace Installed Cloud Key?',
                'A different passphrase cannot unlock records encrypted with the current key. Export its recovery file first. Connect to a fresh Sheet before uploading with a changed key. No records will be cleared.')) {
          return;
        }
        final passphrase = await _password(exporting: true, cloud: true);
        if (passphrase == null || !mounted) return;
        await _service.setUpWithPassphrase(passphrase,
            replaceExisting: replacing);
        if (mounted) {
          setState(() => _message =
              'Cloud passphrase configured. Use the exact same passphrase and Sheet on your other devices. Keep a secure passphrase copy or export a recovery file.');
        }
      });

  Future<void> _export() => _run(() async {
        final password = await _password(exporting: true);
        if (password == null || !mounted) return;
        final package = await _service.exportRecovery(password);
        final destination = await getSaveLocation(
            suggestedName: 'holistic-recovery.harkey',
            acceptedTypeGroups: [_fileType]);
        if (destination == null) return;
        await XFile.fromData(utf8.encode(package),
                mimeType: 'application/octet-stream')
            .saveTo(destination.path);
        if (mounted) {
          setState(() => _message =
              'Protected recovery file exported. Keep the file and its password safe and separate.');
        }
      });

  Future<void> _import() => _run(() async {
        final file = await openFile(acceptedTypeGroups: [_fileType]);
        if (file == null || !mounted) return;
        if (await file.length() > 8192) {
          throw const DataSecurityException(
              'This is not a supported recovery file.');
        }
        final package = await file.readAsString();
        if (!mounted) return;
        final password = await _password(exporting: false);
        if (password == null || !mounted) return;
        final exists = await _service.load() != null;
        if (!mounted) return;
        if (exists &&
            !await _confirm('Replace Installed Recovery Key?',
                'Export your current recovery file first. Replacing this key can prevent this device from reading its current encrypted cloud dataset. Only continue with the recovery file for the dataset you intend to use.')) {
          return;
        }
        await _service.importRecovery(package, password,
            replaceExisting: exists);
        if (mounted) {
          setState(() => _message =
              'Recovery key imported. This device can now read the matching encrypted dataset.');
        }
      });

  @override
  Widget build(BuildContext context) => Card(
          child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Data Security',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Text(
                'Encryption: ${_configured == null ? 'Unavailable / Checking' : _configured! ? 'Configured' : 'Not Configured'}'),
            const SizedBox(height: 8),
            const Text(
                'Use the exact same cloud passphrase on all devices. Keep a secure copy or an encrypted recovery file. Without the passphrase, installed key, or recovery file, cloud data cannot be recovered.'),
            const SizedBox(height: 12),
            Wrap(spacing: 12, runSpacing: 8, children: [
              FilledButton(
                  onPressed: _busy || _configured != false ? null : _setup,
                  child: const Text('Set Up Encryption')),
              if (_configured == true)
                OutlinedButton(
                    onPressed: _busy ? null : _setup,
                    child: const Text('Configure Cloud Passphrase')),
              OutlinedButton(
                  onPressed: _busy || _configured != true ? null : _export,
                  child: const Text('Export Recovery Key')),
              OutlinedButton(
                  onPressed: _busy || _configured == null ? null : _import,
                  child: const Text('Import Recovery Key')),
            ]),
            if (_busy)
              const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator()),
            if (_message != null)
              Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_message!)),
          ],
        ),
      ));
}
