import 'package:flutter/material.dart';

abstract final class AppTextStyles {
  static const titleLarge = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.bold,
  );
  static const titleMedium = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.bold,
  );
  static const videoTitle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
  );
  static const appBarTitle = TextStyle(fontWeight: FontWeight.w700);
  static const channelName = TextStyle(fontWeight: FontWeight.w600);
  static const channelInitial = TextStyle(color: Colors.white);
  static const bodyMedium = TextStyle(fontSize: 15);
  static const bodySmall = TextStyle(fontSize: 13, color: Colors.grey);
  static const videoDetails = TextStyle(fontSize: 12);
}
