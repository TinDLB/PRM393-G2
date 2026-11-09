import 'package:flutter/material.dart';

abstract final class AppSpacing {
  static const page = EdgeInsets.fromLTRB(16, 12, 16, 28);
  static const section = EdgeInsets.symmetric(vertical: 20);
  static const cardContent = EdgeInsets.all(14);
  static const content = EdgeInsets.all(16);

  static const xSmall = 8.0;
  static const small = 10.0;
  static const medium = 12.0;
  static const large = 14.0;
  static const xLarge = 16.0;
  static const screenColumn = 24.0;
}
