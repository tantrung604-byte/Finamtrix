import 'package:flutter/material.dart';

class AppTheme {
  // Brand & Accent Colors
  static const Color brandCyan = Color(0xFF00E5FF);
  static const Color brandPurple = Color(0xFF7C4DFF);
  static const Color brandGreen = Color(0xFF00E676);
  static const Color brandGold = Color(0xFFFFD600);
  static const Color brandOrange = Color(0xFFFF9100);
  static const Color brandRed = Color(0xFFFF5252);
  
  static const Color bgPrimary = Color(0xFF050918);
  static const Color bgSecondary = Color(0xFF0D1226);

  // Compat for old code
  static const Color colorSafe = brandGreen;
  static const Color colorWarm = brandGold;
  static const Color colorHot = brandOrange;
  static const Color colorDanger = brandRed;
  static const Color colorGold = brandGold;
  static const Color colorBds = brandCyan;
  static const Color colorStock = brandPurple;

  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFB0B3B8);
  static const Color textTertiary = Color(0xFF65676B);

  // Gradients
  static const LinearGradient brandGradient = LinearGradient(
    colors: [brandCyan, brandPurple],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient premiumGradient = LinearGradient(
    colors: [brandPurple, Color(0xFFB388FF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient safeGradient = LinearGradient(
    colors: [brandGreen, Color(0xFF00C853)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient warmGradient = LinearGradient(
    colors: [brandGold, Color(0xFFFFA000)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient hotGradient = LinearGradient(
    colors: [brandOrange, Color(0xFFF4511E)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient dangerGradient = LinearGradient(
    colors: [brandRed, Color(0xFFD32F2F)],
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
      useMaterial3: true,
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
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: bgPrimary,
        indicatorColor: brandCyan.withValues(alpha: 0.15),
        elevation: 0,
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(color: selected ? brandCyan : textTertiary, size: 24);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.bold : FontWeight.w500,
            color: selected ? brandCyan : textTertiary,
          );
        }),
      ),
    );
  }
}
