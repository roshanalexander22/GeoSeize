import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/rewards_system.dart';

class SettingsService {
  // Singleton pattern
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  // SharedPreferences keys
  static const String _keyIsDarkTheme        = 'isDarkTheme';
  static const String _keyMapStyle           = 'mapStyle';
  static const String _keyReconColor         = 'reconColor';
  static const String _keyUseMetric          = 'useMetric';
  static const String _keyProfileImagePath   = 'profileImagePath';
  static const String _keyMarkerType         = 'markerType';
  static const String _keySelectedColorIndex = 'selectedColorIndex';
  static const String _keySelectedAvatarIndex = 'selectedAvatarIndex';
  static const String _keyShowMapScale       = 'showMapScale';

  // Map Style Options
  static const String mapStyleDark      = 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png';
  static const String mapStyleLight     = 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png';
  static const String mapStyleStreet    = 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png';
  static const String mapStyleSatellite = 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';


  // ValueNotifiers for reactive UI updates
  final ValueNotifier<bool>   isDarkTheme      = ValueNotifier<bool>(true);
  final ValueNotifier<String> mapStyle         = ValueNotifier<String>(mapStyleDark);
  final ValueNotifier<Color>  reconColor       = ValueNotifier<Color>(Colors.cyanAccent);
  final ValueNotifier<bool>   useMetric        = ValueNotifier<bool>(true);
  final ValueNotifier<String?> profileImagePath = ValueNotifier<String?>(null);
  final ValueNotifier<String> markerType       = ValueNotifier<String>('default');

  /// Index into RewardsSystem.colors — the player's chosen colour.
  final ValueNotifier<int> selectedColorIndex  = ValueNotifier<int>(0);

  /// Index into RewardsSystem.avatars — the player's chosen avatar.
  final ValueNotifier<int> selectedAvatarIndex = ValueNotifier<int>(0);

  /// Whether to show the map scale indicator in the corner.
  final ValueNotifier<bool> showMapScale = ValueNotifier<bool>(true);

  /// The actual Color derived from the selected index.
  Color get selectedColor => RewardsSystem.colors[selectedColorIndex.value].color;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();

    isDarkTheme.value    = prefs.getBool(_keyIsDarkTheme)  ?? true;
    mapStyle.value       = prefs.getString(_keyMapStyle)    ?? mapStyleDark;
    useMetric.value      = prefs.getBool(_keyUseMetric)    ?? true;
    profileImagePath.value = prefs.getString(_keyProfileImagePath);
    showMapScale.value   = prefs.getBool(_keyShowMapScale) ?? true;

    // Restore colour index (default 0 = Cyan)
    selectedColorIndex.value  = prefs.getInt(_keySelectedColorIndex)  ?? 0;

    // Restore avatar index and sync legacy markerType string
    final savedAvatarIdx = prefs.getInt(_keySelectedAvatarIndex);
    if (savedAvatarIdx != null) {
      selectedAvatarIndex.value = savedAvatarIdx;
      markerType.value = RewardsSystem.avatars[savedAvatarIdx].id;
    } else {
      // Migrate legacy markerType string to index
      final legacy = prefs.getString(_keyMarkerType) ?? 'default';
      final idx = RewardsSystem.indexOfAvatar(legacy);
      selectedAvatarIndex.value = idx >= 0 ? idx : 0;
      markerType.value = RewardsSystem.avatars[selectedAvatarIndex.value].id;
    }

    // Migrate legacy reconColor
    final reconColorInt = prefs.getInt(_keyReconColor);
    if (reconColorInt != null) {
      reconColor.value = Color(reconColorInt);
    }
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

  Future<void> setSelectedColorIndex(int index) async {
    selectedColorIndex.value = index;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keySelectedColorIndex, index);
  }

  Future<void> setSelectedAvatarIndex(int index) async {
    selectedAvatarIndex.value = index;
    markerType.value = RewardsSystem.avatars[index].id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keySelectedAvatarIndex, index);
    await prefs.setString(_keyMarkerType, markerType.value);
  }

  Future<void> setShowMapScale(bool value) async {
    showMapScale.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyShowMapScale, value);
  }
}
