import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:latlong2/latlong.dart';

class StorageService {
  static const String _territoriesKey = 'geoseize_territories';
  static const String _totalAreaKey = 'geoseize_total_area';

  /// Saves the list of territories (polygons) to persistent storage
  Future<void> saveTerritories(List<List<LatLng>> territories) async {
    final prefs = await SharedPreferences.getInstance();
    
    // Convert List<List<LatLng>> to a JSON encodable format
    List<List<Map<String, double>>> serializableTerritories = territories.map((polygon) {
      return polygon.map((point) => {
        'lat': point.latitude,
        'lng': point.longitude,
      }).toList();
    }).toList();

    String jsonString = jsonEncode(serializableTerritories);
    await prefs.setString(_territoriesKey, jsonString);
  }

  /// Loads the list of territories from persistent storage
  Future<List<List<LatLng>>> loadTerritories() async {
    final prefs = await SharedPreferences.getInstance();
    String? jsonString = prefs.getString(_territoriesKey);
    
    if (jsonString == null) return [];

    try {
      List<dynamic> decodedList = jsonDecode(jsonString);
      
      List<List<LatLng>> loadedTerritories = decodedList.map((dynamic polygonList) {
        return (polygonList as List).map((dynamic pointMap) {
          return LatLng(pointMap['lat'] as double, pointMap['lng'] as double);
        }).toList();
      }).toList();

      return loadedTerritories;
    } catch (e) {
      print("Error loading territories: \$e");
      return [];
    }
  }

  /// Saves the accumulated total area scored
  Future<void> saveTotalArea(double totalArea) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_totalAreaKey, totalArea);
  }

  /// Loads the total area scored
  Future<double> loadTotalArea() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_totalAreaKey) ?? 0.0;
  }

  /// Wipe all data to start over
  Future<void> wipeData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_territoriesKey);
    await prefs.remove(_totalAreaKey);
  }
}
