import 'package:flutter/material.dart';

class AppBackground extends StatelessWidget {
  const AppBackground({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Subtle base photo background
        Image.asset(
          'assets/images/home_background.jpg',
          fit: BoxFit.cover,
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

        child,
      ],
    );
  }
}