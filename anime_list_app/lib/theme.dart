import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppTheme {
  static const Color primary = Color(0xFFD095FF);
  static const Color primaryDark = Color(0xFF9D4EDD);
  static const Color primaryFixed = Color(0xFFC782FF);
  static const Color secondary = Color(0xFFFF9100);
  static const Color secondaryLight = Color(0xFFFFAB40);
  static const Color background = Color(0xFF0E0E0E);
  static const Color surface = Color(0xFF1A1A1A);
  static const Color surfaceL2 = Color(0xFF262626);
  static const Color onSurface = Color(0xE6FFFFFF); // 90% Opacity
  static const Color onSurfaceVariant = Color(0xFFADAAAA);
  static const Color outlineVariant = Color(0xFF484847);
  static const Color neonCyan = Color(0xFF00E5FF);
  
  static const LinearGradient neonGradient = LinearGradient(
    colors: [Color(0xFFD095FF), Color(0xFFC782FF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      primaryColor: primary,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: secondary,
        surface: surface,
        onSurface: onSurface,
        onSurfaceVariant: onSurfaceVariant,
        outlineVariant: outlineVariant,
        surfaceContainerLow: surface,
        surfaceContainerHighest: surfaceL2,
        onPrimary: Colors.black,
        tertiary: neonCyan,
      ),
      textTheme: TextTheme(
        displayLarge: GoogleFonts.plusJakartaSans(color: onSurface, fontWeight: FontWeight.bold),
        displayMedium: GoogleFonts.plusJakartaSans(color: onSurface, fontWeight: FontWeight.bold),
        displaySmall: GoogleFonts.plusJakartaSans(color: onSurface, fontWeight: FontWeight.bold),
        headlineMedium: GoogleFonts.plusJakartaSans(color: onSurface, fontWeight: FontWeight.bold),
        titleLarge: GoogleFonts.plusJakartaSans(color: onSurface, fontWeight: FontWeight.bold),
        titleMedium: GoogleFonts.plusJakartaSans(color: onSurface, fontWeight: FontWeight.bold),
        titleSmall: GoogleFonts.plusJakartaSans(color: onSurface, fontWeight: FontWeight.bold),
        bodyLarge: GoogleFonts.manrope(color: onSurface),
        bodyMedium: GoogleFonts.manrope(color: onSurface),
        bodySmall: GoogleFonts.manrope(color: onSurfaceVariant),
        labelLarge: GoogleFonts.plusJakartaSans(color: primary),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
    );
  }

  static ThemeData get lightTheme {
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: const Color(0xFFFBFBFE), // Off-white clean background
      primaryColor: primary,
      colorScheme: const ColorScheme.light(
        primary: primary,
        secondary: secondary,
        surface: Colors.white,
        onSurface: Color(0xFF1A1A1A),
        onSurfaceVariant: Color(0xFF6B6B6B),
        outlineVariant: Color(0xFFE0E0E0),
        onPrimary: Colors.white,
        surfaceContainerHighest: Color(0xFFF0F0F0),
        tertiary: neonCyan,
      ),
      textTheme: TextTheme(
        displayLarge: GoogleFonts.plusJakartaSans(color: const Color(0xFF1A1A1A), fontWeight: FontWeight.bold),
        displayMedium: GoogleFonts.plusJakartaSans(color: const Color(0xFF1A1A1A), fontWeight: FontWeight.bold),
        displaySmall: GoogleFonts.plusJakartaSans(color: const Color(0xFF1A1A1A), fontWeight: FontWeight.bold),
        headlineMedium: GoogleFonts.plusJakartaSans(color: const Color(0xFF1A1A1A), fontWeight: FontWeight.bold),
        titleLarge: GoogleFonts.plusJakartaSans(color: const Color(0xFF1A1A1A), fontWeight: FontWeight.bold),
        titleMedium: GoogleFonts.plusJakartaSans(color: const Color(0xFF1A1A1A), fontWeight: FontWeight.bold),
        titleSmall: GoogleFonts.plusJakartaSans(color: const Color(0xFF1A1A1A), fontWeight: FontWeight.bold),
        bodyLarge: GoogleFonts.manrope(color: const Color(0xFF1A1A1A)),
        bodyMedium: GoogleFonts.manrope(color: const Color(0xFF1A1A1A)),
        bodySmall: GoogleFonts.manrope(color: const Color(0xFF6B6B6B)),
        labelLarge: GoogleFonts.plusJakartaSans(color: primary),
      ),
    );
  }

  static InputDecoration inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: primary),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: outlineVariant.withOpacity(0.3)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: outlineVariant.withOpacity(0.3)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: primary),
      ),
      labelStyle: const TextStyle(color: onSurfaceVariant, fontSize: 14),
    );
  }
}

class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.dark;
  static const String _key = 'theme_mode';

  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final isDark = prefs.getBool(_key);
    if (isDark != null) {
      _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
      notifyListeners();
    }
  }

  Future<void> toggleTheme(bool isOn) async {
    _themeMode = isOn ? ThemeMode.dark : ThemeMode.light;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, isOn);
    notifyListeners();
  }
}

final themeProvider = ThemeProvider();


