import 'dart:math' as math;
import 'package:latlong2/latlong.dart';

class GeoCalculator {
  static const double _earthRadius = 6378137.0; // WGS-84 equatorial radius in meters

  /// Calculates the area of a polygon representing a geographic territory using
  /// the Shoelace formula applied to an equirectangular projection.
  /// 
  /// Returns area in Square Meters (m²).
  static double calculateArea(List<LatLng> polygon) {
    if (polygon.length < 3) return 0.0;

    // Approximate area by projecting coordinates to meters locally.
    // For small polygons (like a park or neighborhood walking loop), this is highly accurate.
    
    // Find the average latitude to scale longitudes correctly (cos(lat))
    double sumLat = 0;
    for (var point in polygon) {
      sumLat += point.latitude;
    }
    double meanLat = sumLat / polygon.length;
    double cosMeanLat = math.cos(meanLat * math.pi / 180.0);

    // Convert all points to Cartesian meters relative to an arbitrary origin (0,0)
    List<math.Point<double>> pointsInMeters = polygon.map((point) {
      double x = point.longitude * (math.pi / 180.0) * _earthRadius * cosMeanLat;
      double y = point.latitude * (math.pi / 180.0) * _earthRadius;
      return math.Point<double>(x, y);
    }).toList();

    // Ensure the polygon is closed for the shoelace formula
    if (pointsInMeters.first != pointsInMeters.last) {
      pointsInMeters.add(pointsInMeters.first);
    }

    // Shoelace formula block
    double area = 0.0;
    for (int i = 0; i < pointsInMeters.length - 1; i++) {
      var p1 = pointsInMeters[i];
      var p2 = pointsInMeters[i + 1];
      area += (p1.x * p2.y) - (p2.x * p1.y);
    }

    return (area.abs() / 2.0);
  }

  /// Calculates the centroid of a given polygon.
  static LatLng getCentroid(List<LatLng> polygon) {
    if (polygon.isEmpty) return const LatLng(0, 0);
    double latSum = 0;
    double lngSum = 0;
    for (var point in polygon) {
      latSum += point.latitude;
      lngSum += point.longitude;
    }
    return LatLng(latSum / polygon.length, lngSum / polygon.length);
  }
}
