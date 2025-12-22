import 'package:flutter/material.dart';

class AppConfig {
  static const apiBaseUrl =
      'https://thermosetting-paralexic-paulene.ngrok-free.dev';
}

class AppColors {
  static const primary = Color(0xFF009688); // Teal
  static const secondary = Color(0xFF26A69A);
  static const background = Color(0xFFF5F5F5);
  static const surface = Colors.white;
  static const error = Color(0xFFD32F2F);
  static const textPrimary = Color(0xFF212121);
  static const textSecondary = Color(0xFF757575);
}

class AppTextStyle {
  static const headline = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
  );
  static const sectionTitle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );
  static const body = TextStyle(fontSize: 16, color: AppColors.textPrimary);
  static const label = TextStyle(fontSize: 14, color: AppColors.textSecondary);
}
