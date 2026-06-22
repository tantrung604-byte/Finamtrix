import 'package:flutter/material.dart';

class AppTheme {
  // Brand & Accent Colors
  static const Color bgPrimary = Color(0xFF070B1E);
  static const Color bgSecondary = Color(0xFF0D122F);
  
  static const Color brandCyan = Color(0xFF00D4FF);
  static const Color brandPurple = Color(0xFF7C4DFF);
  
  static const Color colorSafe = Color(0xFF00E676);
  static const Color colorWarm = Color(0xFFFFCA28);
  static const Color colorHot = Color(0xFFFF9100);
  static const Color colorDanger = Color(0xFFFF5252);
  static const Color colorGold = Color(0xFFFFD54F);
  static const Color colorBds = Color(0xFF26C6DA);
  static const Color colorStock = Color(0xFF7C4DFF);
  
  static const Color textPrimary = Color(0xFFF0F2FF);
  static const Color textSecondary = Color(0x99F0F2FF);
  static const Color textTertiary = Color(0x66F0F2FF);

  // Gradients
  static const LinearGradient brandGradient = LinearGradient(
    colors: [Color(0xFF00C9FF), Color(0xFF0052D4)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient premiumGradient = LinearGradient(
    colors: [Color(0xFF7C4DFF), Color(0xFF00D4FF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient safeGradient = LinearGradient(
    colors: [Color(0xFF00E676), Color(0xFF00C853)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient warmGradient = LinearGradient(
    colors: [Color(0xFFFFCA28), Color(0xFFFFA000)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient hotGradient = LinearGradient(
    colors: [Color(0xFFFF9100), Color(0xFFF4511E)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient dangerGradient = LinearGradient(
    colors: [Color(0xFFFF5252), Color(0xFFD32F2F)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Glassmorphic properties
  static final Color glassBg = Colors.white.withOpacity(0.04);
  static final Color glassBorder = Colors.white.withOpacity(0.08);
  static const double glassBlur = 20.0;

  // Glow Shadows
  static List<BoxShadow> getGlow(Color color) {
    return [
      BoxShadow(
        color: color.withOpacity(0.24),
        blurRadius: 16,
        spreadRadius: -2,
        offset: const Offset(0, 4),
      ),
    ];
  }

  // Theme Data Definition
  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bgPrimary,
      primaryColor: brandCyan,
      colorScheme: const ColorScheme.dark(
        primary: brandCyan,
        secondary: brandPurple,
        surface: bgSecondary,
      ),
      fontFamily: 'Inter',
      textTheme: const TextTheme(
        headlineLarge: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: textPrimary, letterSpacing: -0.5),
        headlineMedium: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textPrimary, letterSpacing: -0.5),
        titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textPrimary),
        titleMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: textPrimary),
        bodyLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.normal, color: textPrimary),
        bodyMedium: TextStyle(fontSize: 13, fontWeight: FontWeight.normal, color: textSecondary),
        labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: textTertiary, letterSpacing: 1.0),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: bgPrimary,
        selectedItemColor: brandCyan,
        unselectedItemColor: textTertiary,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
    );
  }
}
