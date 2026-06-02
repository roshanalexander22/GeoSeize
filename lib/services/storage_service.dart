import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/capture_event.dart';

class StorageService {
  static const String _eventsKey = 'geoseize_capture_events';

  /// Saves the list of capture events to persistent storage
  Future<void> saveEvents(List<CaptureEvent> events) async {
    final prefs = await SharedPreferences.getInstance();
    
    List<Map<String, dynamic>> serializableEvents = events.map((e) => e.toJson()).toList();
    String jsonString = jsonEncode(serializableEvents);
    
    await prefs.setString(_eventsKey, jsonString);
  }

  /// Loads the list of capture events from persistent storage
  Future<List<CaptureEvent>> loadEvents() async {
    final prefs = await SharedPreferences.getInstance();
    String? jsonString = prefs.getString(_eventsKey);
    
    if (jsonString == null) return [];

    try {
      List<dynamic> decodedList = jsonDecode(jsonString);
      return decodedList.map((dynamic jsonMap) {
        return CaptureEvent.fromJson(jsonMap as Map<String, dynamic>);
      }).toList();
    } catch (e) {
      // If we fail to decode, it might be the old format. 
      // Wipe data gracefully to avoid crashing.
      print("Error loading events (likely old format): \$e");
      await wipeData();
      return [];
    }
  }

  /// Calculates total area from all events
  Future<double> loadTotalArea() async {
    final events = await loadEvents();
    double total = 0.0;
    for (var event in events) {
      total += event.area;
    }
    return total;
  }

  /// Wipe all data to start over
  Future<void> wipeData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_eventsKey);
    // Also remove the old keys just in case
    await prefs.remove('geoseize_territories');
    await prefs.remove('geoseize_total_area');
  }
}
