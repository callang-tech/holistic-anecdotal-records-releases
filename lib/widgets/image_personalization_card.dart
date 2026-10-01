import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../services/image_personalization_service.dart';

class ImagePersonalizationCard extends StatefulWidget {
  const ImagePersonalizationCard({
    super.key,
    this.personalization,
    this.reportsOnly = false,
  });

  final ImagePersonalizationService? personalization;
  final bool reportsOnly;

  @override
  State<ImagePersonalizationCard> createState() =>
      _ImagePersonalizationCardState();
}

class _ImagePersonalizationCardState extends State<ImagePersonalizationCard> {
  late final _service =
      widget.personalization ?? ImagePersonalizationService.instance;
  PersonalizedImage? _busy;

  Future<void> _choose(PersonalizedImage kind) async {
    const types = XTypeGroup(
        label: 'PNG and JPEG images', extensions: ['png', 'jpg', 'jpeg']);
    setState(() => _busy = kind);
    try {
      final selected = await openFile(acceptedTypeGroups: [types]);
      if (selected == null || !mounted) return;
      await _service.importFile(kind, selected.path);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not import image: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _restore(PersonalizedImage kind) async {
    if (!await _service.hasManagedCopy(kind) || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Restore default ${kind.label}?'),
        content:
            Text('Remove the saved custom ${kind.label.toLowerCase()} image? '
                'The original image you selected will not be changed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Restore Default')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = kind);
    try {
      await _service.restoreDefault(kind);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not restore default: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (!widget.reportsOnly) ...[
              const Row(children: [
                Icon(Icons.palette_outlined),
                SizedBox(width: 10),
                Text('APPEARANCE / PERSONALIZATION',
                    style:
                        TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 8),
              const Text(
                  'Images are copied to this computer’s Documents folder. '
                  'Theme and color choices remain in Settings.'),
              TextButton.icon(
                onPressed: () => Navigator.pushNamed(context, '/settings'),
                icon: const Icon(Icons.color_lens_outlined),
                label: const Text('Theme and Colors'),
              ),
              _imageControl(PersonalizedImage.background),
            ],
            Text('PDF / Report Customization',
                style: Theme.of(context).textTheme.titleLarge),
            const Text('PNG, JPG or JPEG only. Exact dimensions are required; '
                'images are copied without resizing or cropping.'),
            _imageControl(PersonalizedImage.header),
            _imageControl(PersonalizedImage.footer),
          ]),
        ),
      );

  Widget _imageControl(PersonalizedImage kind) => AnimatedBuilder(
        animation: _service,
        builder: (context, _) => Padding(
          padding: const EdgeInsets.only(top: 12),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(kind.label, style: Theme.of(context).textTheme.titleMedium),
            if (kind.requiredHeight != null)
              Text('Required: 1270 x ${kind.requiredHeight} pixels'),
            const SizedBox(height: 8),
            FutureBuilder(
              future: _service.customBytes(kind),
              builder: (context, snapshot) {
                final custom = snapshot.data;
                return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 110,
                        width: 260,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: Theme.of(context)
                                    .colorScheme
                                    .outlineVariant)),
                        child: custom == null
                            ? Image.asset(kind.defaultAsset,
                                fit: BoxFit.contain)
                            : Image.memory(custom, fit: BoxFit.contain),
                      ),
                      const SizedBox(height: 4),
                      Text(custom == null ? 'Default' : 'Custom',
                          style: Theme.of(context).textTheme.bodySmall),
                      Wrap(spacing: 8, children: [
                        OutlinedButton(
                            onPressed:
                                _busy == null ? () => _choose(kind) : null,
                            child: Text('Change ${kind.controlLabel}')),
                        OutlinedButton(
                            onPressed:
                                _busy == null ? () => _restore(kind) : null,
                            child:
                                Text('Restore Default ${kind.controlLabel}')),
                      ]),
                    ]);
              },
            ),
            const Divider(),
          ]),
        ),
      );
}
