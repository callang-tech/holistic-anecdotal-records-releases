import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemePreset {
  natureOffice,
  coffeeWood,
  calmBlue,
  forest,
  softBloom,
  warmSunrise,
  gentleLavender,
  cleanProfessional,
  jolly,
  darkNature,
}

extension AppThemePresetExtension on AppThemePreset {
  String get displayName {
    switch (this) {
      case AppThemePreset.natureOffice:
        return 'Nature Office';
      case AppThemePreset.coffeeWood:
        return 'Coffee & Wood';
      case AppThemePreset.calmBlue:
        return 'Calm Blue';
      case AppThemePreset.forest:
        return 'Forest';
      case AppThemePreset.softBloom:
        return 'Soft Bloom';
      case AppThemePreset.warmSunrise:
        return 'Warm Sunrise';
      case AppThemePreset.gentleLavender:
        return 'Gentle Lavender';
      case AppThemePreset.cleanProfessional:
        return 'Clean Professional';
      case AppThemePreset.jolly:
        return 'Jolly';
      case AppThemePreset.darkNature:
        return 'Dark Nature';
    }
  }
}

class AppTheme {
  static ThemeData themeFor(AppThemePreset preset) {
    switch (preset) {
      case AppThemePreset.natureOffice:
        return _natureOffice();

      case AppThemePreset.coffeeWood:
        return _lightTheme(
          primary: const Color(0xFF6D4C41),
          secondary: const Color(0xFFBCAAA4),
          background: const Color(0xFFF8F3EE),
          border: const Color(0xFFE0D2C7),
          text: const Color(0xFF3E3029),
          mutedText: const Color(0xFF75665E),
        );

      case AppThemePreset.calmBlue:
        return _lightTheme(
          primary: const Color(0xFF356A8A),
          secondary: const Color(0xFF6FA3BF),
          background: const Color(0xFFF3F8FB),
          border: const Color(0xFFD4E3EA),
          text: const Color(0xFF263B46),
          mutedText: const Color(0xFF61727B),
        );

      case AppThemePreset.forest:
        return _lightTheme(
          primary: const Color(0xFF315B3E),
          secondary: const Color(0xFF6F9B62),
          background: const Color(0xFFF3F7F1),
          border: const Color(0xFFD5E0D0),
          text: const Color(0xFF29382D),
          mutedText: const Color(0xFF68756B),
        );

      case AppThemePreset.softBloom:
        return _lightTheme(
          primary: const Color(0xFF9A6478),
          secondary: const Color(0xFFC58CA2),
          background: const Color(0xFFFBF5F7),
          border: const Color(0xFFE9D8DF),
          text: const Color(0xFF49343D),
          mutedText: const Color(0xFF77666D),
        );

      case AppThemePreset.warmSunrise:
        return _lightTheme(
          primary: const Color(0xFFB56B35),
          secondary: const Color(0xFFD59A55),
          background: const Color(0xFFFFF8EF),
          border: const Color(0xFFEEDCC5),
          text: const Color(0xFF4B3628),
          mutedText: const Color(0xFF786A5E),
        );

      case AppThemePreset.gentleLavender:
        return _lightTheme(
          primary: const Color(0xFF75639A),
          secondary: const Color(0xFFA998C7),
          background: const Color(0xFFF8F6FC),
          border: const Color(0xFFE2DCEF),
          text: const Color(0xFF40384D),
          mutedText: const Color(0xFF716A7A),
        );

      case AppThemePreset.cleanProfessional:
        return _lightTheme(
          primary: const Color(0xFF37474F),
          secondary: const Color(0xFF607D8B),
          background: const Color(0xFFF5F7F8),
          border: const Color(0xFFD9E0E3),
          text: const Color(0xFF263238),
          mutedText: const Color(0xFF68767C),
        );

      case AppThemePreset.jolly:
        return _lightTheme(
          primary: const Color(0xFF00897B),
          secondary: const Color(0xFFFFB300),
          background: const Color(0xFFFFFBF0),
          border: const Color(0xFFE8DFC4),
          text: const Color(0xFF37474F),
          mutedText: const Color(0xFF68757A),
        );

      case AppThemePreset.darkNature:
        return _darkNature();
    }
  }

  // This is the CURRENT app appearance.
  // It is intentionally preserved as the default Phase 9A theme.
  static ThemeData _natureOffice() {
    const espresso = Color(0xFF2D241E);
    const forestGreen = Color(0xFF1E3932);
    const sageGreen = Color(0xFF00704A);
    const warmCream = Color(0xFFFBF8F3);
    const warmBorder = Color(0xFFE8DFC8);
    const textMuted = Color(0xFF6B5E52);

    final colorScheme = ColorScheme.fromSeed(
      seedColor: forestGreen,
      primary: forestGreen,
      secondary: sageGreen,
      surface: Colors.white,
      brightness: Brightness.light,
    );

    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      scaffoldBackgroundColor: warmCream,

      appBarTheme: const AppBarTheme(
        backgroundColor: forestGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFFAF7F2),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        hintStyle: const TextStyle(color: textMuted),
        labelStyle: const TextStyle(color: textMuted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: warmBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: warmBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(
            color: forestGreen,
            width: 2,
          ),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: forestGreen,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 16,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),

      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(
            color: warmBorder,
            width: 1,
          ),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),

      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return forestGreen;
          }
          return null;
        }),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
      ),

      textTheme: const TextTheme(
        bodyLarge: TextStyle(
          color: espresso,
          fontSize: 16,
        ),
        bodyMedium: TextStyle(
          color: textMuted,
          fontSize: 14,
        ),
        titleLarge: TextStyle(
          color: espresso,
          fontWeight: FontWeight.w700,
          fontSize: 20,
        ),
        titleMedium: TextStyle(
          color: textMuted,
          fontWeight: FontWeight.w500,
          fontSize: 16,
        ),
      ),
    );
  }

  static ThemeData _lightTheme({
    required Color primary,
    required Color secondary,
    required Color background,
    required Color border,
    required Color text,
    required Color mutedText,
  }) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primary,
      primary: primary,
      secondary: secondary,
      surface: Colors.white,
      brightness: Brightness.light,
    );

    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      scaffoldBackgroundColor: background,

      appBarTheme: AppBarTheme(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        hintStyle: TextStyle(color: mutedText),
        labelStyle: TextStyle(color: mutedText),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: primary,
            width: 2,
          ),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 16,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: border),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),

      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return primary;
          }
          return null;
        }),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
      ),

      textTheme: TextTheme(
        bodyLarge: TextStyle(
          color: text,
          fontSize: 16,
        ),
        bodyMedium: TextStyle(
          color: mutedText,
          fontSize: 14,
        ),
        titleLarge: TextStyle(
          color: text,
          fontWeight: FontWeight.w700,
          fontSize: 20,
        ),
        titleMedium: TextStyle(
          color: mutedText,
          fontWeight: FontWeight.w500,
          fontSize: 16,
        ),
      ),
    );
  }

  static ThemeData _darkNature() {
    const primary = Color(0xFF6FAF8B);
    const secondary = Color(0xFFB5C98A);
    const background = Color(0xFF17231D);
    const surface = Color(0xFF223129);
    const text = Color(0xFFE8F0EA);
    const mutedText = Color(0xFFB8C6BC);

    final colorScheme = ColorScheme.fromSeed(
      seedColor: primary,
      primary: primary,
      secondary: secondary,
      surface: surface,
      brightness: Brightness.dark,
    );

    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      scaffoldBackgroundColor: background,

      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF102019),
        foregroundColor: Colors.white,
        elevation: 0,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        hintStyle: const TextStyle(color: mutedText),
        labelStyle: const TextStyle(color: mutedText),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: Colors.white24,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: Colors.white24,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: primary,
            width: 2,
          ),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: const Color(0xFF102019),
          elevation: 0,
          padding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 16,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
      ),

      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(
            color: Colors.white12,
          ),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),

      textTheme: const TextTheme(
        bodyLarge: TextStyle(
          color: text,
          fontSize: 16,
        ),
        bodyMedium: TextStyle(
          color: mutedText,
          fontSize: 14,
        ),
        titleLarge: TextStyle(
          color: text,
          fontWeight: FontWeight.w700,
          fontSize: 20,
        ),
        titleMedium: TextStyle(
          color: mutedText,
          fontWeight: FontWeight.w500,
          fontSize: 16,
        ),
      ),
    );
  }
}

class AppThemeController extends ChangeNotifier {
  static const _themeKey = 'app_theme_preset';

  AppThemePreset _preset = AppThemePreset.natureOffice;

  AppThemePreset get preset => _preset;

  ThemeData get theme => AppTheme.themeFor(_preset);

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();

    final savedIndex = prefs.getInt(_themeKey);

    if (savedIndex != null &&
        savedIndex >= 0 &&
        savedIndex < AppThemePreset.values.length) {
      _preset = AppThemePreset.values[savedIndex];
    }

    notifyListeners();
  }

  Future<void> setPreset(AppThemePreset preset) async {
    if (_preset == preset) {
      return;
    }

    _preset = preset;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeKey, preset.index);
  }
}