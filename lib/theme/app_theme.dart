import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_component_themes.dart';

abstract final class AppTheme {
  static final ThemeData lightTheme = _buildTheme(
    brightness: Brightness.light,
    scaffoldBackgroundColor: AppColors.lightScaffold,
    appBarForegroundColor: AppColors.lightForeground,
  );

  static final ThemeData darkTheme = _buildTheme(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.darkSurface,
    appBarForegroundColor: AppColors.darkForeground,
  );

  static ThemeData _buildTheme({
    required Brightness brightness,
    required Color scaffoldBackgroundColor,
    required Color appBarForegroundColor,
  }) {
    return ThemeData(
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: brightness,
        surface: brightness == Brightness.dark ? AppColors.darkSurface : null,
      ),
      scaffoldBackgroundColor: scaffoldBackgroundColor,
      appBarTheme: AppComponentThemes.appBar(
        backgroundColor: scaffoldBackgroundColor,
        foregroundColor: appBarForegroundColor,
      ),
      cardTheme: AppComponentThemes.card,
      textTheme: AppComponentThemes.text,
      elevatedButtonTheme: AppComponentThemes.elevatedButton,
    );
  }
}
