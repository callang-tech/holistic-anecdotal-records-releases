import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/image_personalization_service.dart';

class AppBackground extends StatefulWidget {
  const AppBackground({
    super.key,
    required this.child,
    this.personalization,
  });

  final Widget child;
  final ImagePersonalizationService? personalization;

  @override
  State<AppBackground> createState() => _AppBackgroundState();
}

class _AppBackgroundState extends State<AppBackground> {
  late ImagePersonalizationService _personalization;
  late Future<Uint8List?> _background;

  @override
  void initState() {
    super.initState();
    _personalization =
        widget.personalization ?? ImagePersonalizationService.instance;
    _personalization.addListener(_refresh);
    _background = _personalization.customBytes(PersonalizedImage.background);
  }

  @override
  void didUpdateWidget(AppBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.personalization ?? ImagePersonalizationService.instance;
    if (next != _personalization) {
      _personalization.removeListener(_refresh);
      _personalization = next;
      _personalization.addListener(_refresh);
      _refresh();
    }
  }

  void _refresh() {
    if (mounted) {
      setState(() {
        _background =
            _personalization.customBytes(PersonalizedImage.background);
      });
    }
  }

  @override
  void dispose() {
    _personalization.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Subtle base photo background
        FutureBuilder(
          future: _background,
          builder: (context, snapshot) => snapshot.data == null
              ? Image.asset(PersonalizedImage.background.defaultAsset,
                  fit: BoxFit.cover)
              : Image.memory(snapshot.data!,
                  fit: BoxFit.cover, gaplessPlayback: true),
        ),

        // Warm Warm Oat / Cream Overlay
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xB3FAF7F2), // ~70% opacity    Warm Oat Cream
                Color(0xB3F3ECE2), // ~70% opacity    Soft Beige Tint
                Color(0xB3F7F2E9), // ~70% opacity    Cozy Latte Cream
              ],
            ),
          ),
        ),

        widget.child,
      ],
    );
  }
}
