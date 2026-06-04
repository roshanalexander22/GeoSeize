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

  /// Closes and merges a newly drawn path with existing territories
  static List<List<LatLng>> closeAndMergeTerritory(
    List<LatLng> newPath,
    List<List<LatLng>> existingTerritories,
  ) {
    if (newPath.length < 2) return existingTerritories;

    // Convert newPath to PathD
    final pathD = <PointD>[];
    for (var p in newPath) {
      pathD.add(PointD(p.longitude, p.latitude));
    }

    // Inflate the path to give it a physical width (approx 15 meters radius)
    // 1 degree lat/lng is ~111,000 meters. 15 meters is ~0.000135 degrees.
    final inflatedPaths = Clipper.inflatePathsD(
      paths: [pathD],
      delta: 0.000135,
      joinType: JoinType.round,
      endType: EndType.round,
      precision: 7,
    );

    // Convert existing territories to PathsD
    final existingPaths = <PathD>[];
    for (var territory in existingTerritories) {
      final tPath = <PointD>[];
      for (var p in territory) {
        tPath.add(PointD(p.longitude, p.latitude));
      }
      existingPaths.add(tPath);
    }

    // Union the inflated path with existing territories
    final clipper = ClipperD(roundingDecimalPrecision: 7);
    clipper.addPaths(inflatedPaths, PathType.subject);
    if (existingPaths.isNotEmpty) {
      clipper.addPaths(existingPaths, PathType.clip);
    }
    final tree = clipper.executeTree(ClipType.union, FillRule.nonZero)?.tree ?? PolyTreeD(scale: 1);

    // Extract outer boundaries (ignore holes to capture enclosed areas)
    final mergedPaths = <PathD>[];
    void extractOuters(PolyPathD node) {
      if (!node.isHole && node.polygon != null && node.polygon!.isNotEmpty) {
        mergedPaths.add(node.polygon!);
      }
      for (var child in node.children) {
        extractOuters(child);
      }
    }

    for (var child in tree.children) {
      extractOuters(child);
    }

    // Convert back to List<List<LatLng>>
    final result = <List<LatLng>>[];
    for (var p in mergedPaths) {
      final poly = <LatLng>[];
      for (var pt in p) {
        poly.add(LatLng(pt.y, pt.x));
      }
      if (poly.isNotEmpty) {
        result.add(poly);
      }
    }

    return result;
  }
}
