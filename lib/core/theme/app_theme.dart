import 'package:flutter/material.dart';

abstract final class AppColors {
  static const background = Color(0xFFF5F7FB);
  static const surface = Colors.white;
  static const border = Color(0xFFE2E7F0);
  static const primary = Color(0xFF246BFD);
  static const ink = Color(0xFF101828);
  static const muted = Color(0xFF55627A);
  static const ok = Color(0xFF127A53);
  static const warning = Color(0xFFB24E00);
  static const danger = Color(0xFFB42318);
  static const neutral = Color(0xFF475467);
  static const flight = Color(0xFF6A3FC4);
  static const train = Color(0xFF1F5FE0);
  static const coach = Color(0xFF00785F);
  static const mockBackground = Color(0xFFFFF4D6);
  static const mockBorder = Color(0xFFF0D585);
  static const mockText = Color(0xFF6B4700);
}

ThemeData buildAppTheme() {
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
    scaffoldBackgroundColor: AppColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
    ),
    cardTheme: const CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(20)),
        side: BorderSide(color: AppColors.border),
      ),
    ),
  );
}
