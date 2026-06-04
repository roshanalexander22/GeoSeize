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
  static const String _keyProfileImagePath = 'profileImagePath';
  static const String _keyMarkerType = 'markerType';

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
  final ValueNotifier<String?> profileImagePath = ValueNotifier<String?>(null);
  final ValueNotifier<String> markerType = ValueNotifier<String>('default');

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
    profileImagePath.value = prefs.getString(_keyProfileImagePath);
    markerType.value = prefs.getString(_keyMarkerType) ?? 'default';
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

  Future<void> setProfileImagePath(String? path) async {
    profileImagePath.value = path;
    final prefs = await SharedPreferences.getInstance();
    if (path == null) {
      await prefs.remove(_keyProfileImagePath);
    } else {
      await prefs.setString(_keyProfileImagePath, path);
    }
  }

  Future<void> setMarkerType(String type) async {
    markerType.value = type;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyMarkerType, type);
  }
}
