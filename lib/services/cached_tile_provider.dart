import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

class CachedTileProvider extends TileProvider {
  static Directory? _cacheDir;

  static Future<void> init() async {
    if (_cacheDir == null) {
      try {
        final docDir = await getApplicationDocumentsDirectory();
        final sep = Platform.pathSeparator;
        _cacheDir = Directory('${docDir.path}${sep}map_tiles_cache');
        if (!await _cacheDir!.exists()) {
          await _cacheDir!.create(recursive: true);
        }
      } catch (e) {
        // Safe fallback - app won't crash, it will download on-the-fly
        print('Error initializing tile cache directory: $e');
      }
    }
  }



  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    final url = getTileUrl(coordinates, options);
    
    if (_cacheDir == null) {
      return NetworkImage(url);
    }

    // Generate a unique safe filename for this tile
    final urlHash = url.hashCode.toString();
    final fileName = '${coordinates.x}_${coordinates.y}_${coordinates.z}_$urlHash.png';
    final sep = Platform.pathSeparator;
    final filePath = '${_cacheDir!.path}$sep$fileName';
    final file = File(filePath);

    if (file.existsSync()) {
      return FileImage(file);
    } else {
      // Fetch async in background and write to file, return NetworkImage for immediate display
      _downloadTile(url, file);
      return NetworkImage(url);
    }
  }

  Future<void> _downloadTile(String url, File file) async {
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent': 'GeoSeizeApp/1.0 (com.example.geoseize; roshan.alexander@example.com)'
        },
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        await file.writeAsBytes(response.bodyBytes);
      }
    } catch (e) {
      // Gracefully swallow network/timeout errors
      print('Failed to cache tile: $e');
    }
  }
}
