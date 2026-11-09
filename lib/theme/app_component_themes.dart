import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_radii.dart';
import 'app_spacing.dart';
import 'app_text_styles.dart';

abstract final class AppComponentThemes {
  static const card = CardThemeData(elevation: 3, margin: EdgeInsets.zero);

  static const text = TextTheme(
    titleLarge: AppTextStyles.titleLarge,
    titleMedium: AppTextStyles.titleMedium,
    bodyMedium: AppTextStyles.bodyMedium,
    bodySmall: AppTextStyles.bodySmall,
  );

  static AppBarTheme appBar({
    required Color backgroundColor,
    required Color foregroundColor,
  }) {
    return AppBarTheme(
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      surfaceTintColor: Colors.transparent,
      centerTitle: true,
    );
  }

  static final elevatedButton = ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xLarge + AppSpacing.small,
        vertical: AppSpacing.large,
      ),
      shape: const RoundedRectangleBorder(borderRadius: AppRadii.button),
    ),
  );
}
