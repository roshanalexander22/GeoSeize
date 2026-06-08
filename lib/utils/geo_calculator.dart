import 'dart:math' as math;
import 'package:latlong2/latlong.dart';
import 'package:clipper2/clipper2.dart';

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

  /// Returns the **visual center** of a polygon — the point that is furthest
  /// from all edges (pole of inaccessibility). This is ALWAYS inside the polygon,
  /// even for concave shapes and fused/merged territories.
  ///
  /// Uses a fast grid-sampling approach: subdivide the bounding box into a grid,
  /// keep only cells whose centers are inside the polygon, pick the one whose
  /// minimum distance to any edge is greatest.
  static LatLng getVisualCenter(List<LatLng> polygon) {
    if (polygon.isEmpty) return const LatLng(0, 0);
    if (polygon.length < 3) return polygon.first;

    // Bounding box
    double minLat = polygon.first.latitude;
    double maxLat = polygon.first.latitude;
    double minLng = polygon.first.longitude;
    double maxLng = polygon.first.longitude;
    for (var p in polygon) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    final latRange = maxLat - minLat;
    final lngRange = maxLng - minLng;
    // Grid resolution: 10 steps per side (100 candidates max — very fast)
    const steps = 10;
    final latStep = latRange / steps;
    final lngStep = lngRange / steps;

    LatLng? bestPoint;
    double bestDist = -1;

    for (int i = 0; i <= steps; i++) {
      for (int j = 0; j <= steps; j++) {
        final candidate = LatLng(
          minLat + latStep * i + latStep * 0.5,
          minLng + lngStep * j + lngStep * 0.5,
        );

        // Only consider points inside the polygon
        if (!_pointInPolygon(candidate, polygon)) continue;

        // Find minimum distance to any edge (in degrees — sufficient for ranking)
        double minEdgeDist = double.infinity;
        for (int k = 0; k < polygon.length; k++) {
          final p1 = polygon[k];
          final p2 = polygon[(k + 1) % polygon.length];
          final d = _pointToSegmentDistSq(candidate, p1, p2);
          if (d < minEdgeDist) minEdgeDist = d;
        }

        if (minEdgeDist > bestDist) {
          bestDist = minEdgeDist;
          bestPoint = candidate;
        }
      }
    }

    // Fallback to simple average if grid found nothing (degenerate polygon)
    if (bestPoint == null) {
      double latSum = 0, lngSum = 0;
      for (var p in polygon) { latSum += p.latitude; lngSum += p.longitude; }
      return LatLng(latSum / polygon.length, lngSum / polygon.length);
    }
    return bestPoint;
  }

  /// Returns a font size for the zone label scaled to the zone's area.
  /// Tiny zones get size 8, large zones scale up to size 22.
  static double getZoneLabelFontSize(double areaM2) {
    // Scale: 50 m² → 8pt,  5000 m² → 18pt, 50000 m² → 22pt
    const minSize = 8.0;
    const maxSize = 22.0;
    if (areaM2 <= 0) return minSize;
    // Logarithmic scale so small zones aren't tiny and huge zones aren't massive
    final t = (math.log(areaM2.clamp(50, 50000)) - math.log(50)) /
              (math.log(50000) - math.log(50));
    return minSize + (maxSize - minSize) * t.clamp(0.0, 1.0);
  }

  // Ray-casting point-in-polygon test (lat/lng degrees)
  static bool _pointInPolygon(LatLng point, List<LatLng> polygon) {
    bool inside = false;
    for (int i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final xi = polygon[i].longitude, yi = polygon[i].latitude;
      final xj = polygon[j].longitude, yj = polygon[j].latitude;
      if (((yi > point.latitude) != (yj > point.latitude)) &&
          (point.longitude < (xj - xi) * (point.latitude - yi) / (yj - yi) + xi)) {
        inside = !inside;
      }
    }
    return inside;
  }

  // Squared distance from point P to segment AB (in degrees — for ranking only)
  static double _pointToSegmentDistSq(LatLng p, LatLng a, LatLng b) {
    double ax = a.longitude, ay = a.latitude;
    double bx = b.longitude, by = b.latitude;
    double px = p.longitude, py = p.latitude;
    double dx = bx - ax, dy = by - ay;
    final lenSq = dx * dx + dy * dy;
    double t = lenSq == 0 ? 0 : ((px - ax) * dx + (py - ay) * dy) / lenSq;
    t = t.clamp(0.0, 1.0);
    final nearX = ax + t * dx, nearY = ay + t * dy;
    final diffX = px - nearX, diffY = py - nearY;
    return diffX * diffX + diffY * diffY;
  }

  /// Calculates the centroid of a given polygon (simple average — may fall outside concave shapes).
  /// Prefer [getVisualCenter] for label placement.
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

  /// Checks if a point is inside any of the given polygons
  static bool isPointInPolygons(LatLng point, List<List<LatLng>> polygons) {
    final pt = PointD(point.longitude, point.latitude);
    for (var poly in polygons) {
      final pathD = <PointD>[];
      for (var p in poly) {
        pathD.add(PointD(p.longitude, p.latitude));
      }
      if (pathD.pointInPolygon(pt) != PointInPolygonResult.isOutside) {
        return true;
      }
    }
    return false;
  }

}

