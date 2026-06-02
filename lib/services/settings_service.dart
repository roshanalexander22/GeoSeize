import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  // Singleton pattern
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  // SharedPreferences keys
  static const String _keyIsDarkTheme = 'isDarkTheme';
  static const String _keyMapStyle = 'mapStyle';
  static const String _keyCaptureColor = 'captureColor';
  static const String _keyReconColor = 'reconColor';
  static const String _keyUseMetric = 'useMetric';

  // Map Style Options
  static const String mapStyleDark = 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png';
  static const String mapStyleLight = 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png';
  static const String mapStyleStreet = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  // ValueNotifiers for reactive UI updates
  final ValueNotifier<bool> isDarkTheme = ValueNotifier<bool>(true);
  final ValueNotifier<String> mapStyle = ValueNotifier<String>(mapStyleDark);
  final ValueNotifier<Color> captureColor = ValueNotifier<Color>(const Color(0xFF6C63FF)); // Theme primary
  final ValueNotifier<Color> reconColor = ValueNotifier<Color>(Colors.cyanAccent);
  final ValueNotifier<bool> useMetric = ValueNotifier<bool>(true);

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    
    isDarkTheme.value = prefs.getBool(_keyIsDarkTheme) ?? true;
    mapStyle.value = prefs.getString(_keyMapStyle) ?? mapStyleDark;
    
    int? captureColorInt = prefs.getInt(_keyCaptureColor);
    if (captureColorInt != null) {
      captureColor.value = Color(captureColorInt);
    }
    
    int? reconColorInt = prefs.getInt(_keyReconColor);
    if (reconColorInt != null) {
      reconColor.value = Color(reconColorInt);
    }
    
    useMetric.value = prefs.getBool(_keyUseMetric) ?? true;
  }

  Future<void> setDarkTheme(bool value) async {
    isDarkTheme.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyIsDarkTheme, value);
  }

  Future<void> setMapStyle(String urlTemplate) async {
    mapStyle.value = urlTemplate;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyMapStyle, urlTemplate);
  }

  Future<void> setCaptureColor(Color color) async {
    captureColor.value = color;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyCaptureColor, color.value);
  }

  Future<void> setReconColor(Color color) async {
    reconColor.value = color;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyReconColor, color.value);
  }

  Future<void> setUseMetric(bool value) async {
    useMetric.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyUseMetric, value);
  }
}
