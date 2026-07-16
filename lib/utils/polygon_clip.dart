import 'dart:math' as math;
import 'package:clipper2/clipper2.dart';
import 'package:latlong2/latlong.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PolygonClip — thin wrapper around clipper2 for territory boolean operations.
//
// All LatLng coordinates are scaled to int64 fixed-point so that clipper2's
// integer arithmetic stays fully precise.
//
// Scale factor: 7 decimal places → sub-centimetre precision worldwide.
// ─────────────────────────────────────────────────────────────────────────────
class PolygonClip {
  static const double _scale = 10000000.0;

  // ── Internal coordinate helpers ─────────────────────────────────────────────

  static Path64 _toPath64(List<LatLng> pts) => pts
      .map((p) => Point64(
            (p.longitude * _scale).round(),
            (p.latitude  * _scale).round(),
          ))
      .toList();

  static List<LatLng>? _fromPath64(Path64 path) {
    if (path.length < 3) return null;
    final result = <LatLng>[];
    for (final pt in path) {
      final lat = pt.y / _scale;
      final lng = pt.x / _scale;
      if (lat.isNaN || lat.isInfinite || lng.isNaN || lng.isInfinite) return null;
      if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
      result.add(LatLng(lat, lng));
    }
    return result.length >= 3 ? result : null;
  }

  /// Recursively extract outer (non-hole) rings from a PolyTree64.
  static List<List<LatLng>> _extractOuters(PolyTree64 tree) {
    final result = <List<LatLng>>[];
    void visit(PolyPath64 node) {
      if (!node.isHole && node.polygon != null && node.polygon!.isNotEmpty) {
        final poly = _fromPath64(node.polygon!);
        if (poly != null) result.add(poly);
      }
      for (final child in node.children) visit(child);
    }
    for (final child in tree.children) visit(child);
    return result;
  }

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Boolean UNION of [subjects] with [clips]. Returns merged outer rings.
  /// Safe with empty inputs (returns concatenated list as-is).
  static List<List<LatLng>> union(
      List<List<LatLng>> subjects, List<List<LatLng>> clips) {
    if (subjects.isEmpty && clips.isEmpty) return [];
    try {
      final c = Clipper64();
      for (final s in subjects) {
        if (s.length >= 3) c.addPath(_toPath64(s), PathType.subject);
      }
      for (final cl in clips) {
        if (cl.length >= 3) c.addPath(_toPath64(cl), PathType.clip);
      }
      final res = c.executeTree(ClipType.union, FillRule.nonZero);
      if (res == null) return [...subjects, ...clips];
      return _extractOuters(res.tree);
    } catch (_) {
      return [...subjects, ...clips];
    }
  }

  /// Boolean INTERSECTION of polygon [a] with polygon [b].
  /// Returns the parts that are inside both. Empty list if no overlap.
  static List<List<LatLng>> intersection(List<LatLng> a, List<LatLng> b) {
    if (a.length < 3 || b.length < 3) return [];
    if (!bboxOverlap(a, b)) return [];
    try {
      final c = Clipper64();
      c.addPath(_toPath64(a), PathType.subject);
      c.addPath(_toPath64(b), PathType.clip);
      final res = c.executeTree(ClipType.intersection, FillRule.nonZero);
      if (res == null) return [];
      return _extractOuters(res.tree);
    } catch (_) {
      return [];
    }
  }

  /// Boolean DIFFERENCE: A minus B. Returns parts of [a] not covered by [b].
  static List<List<LatLng>> difference(List<LatLng> a, List<LatLng> b) {
    if (a.length < 3) return [];
    if (b.length < 3) return [a];
    if (!bboxOverlap(a, b)) return [a];
    try {
      final c = Clipper64();
      c.addPath(_toPath64(a), PathType.subject);
      c.addPath(_toPath64(b), PathType.clip);
      final res = c.executeTree(ClipType.difference, FillRule.nonZero);
      if (res == null) return [a];
      final out = _extractOuters(res.tree);
      return out.isEmpty ? [a] : out;
    } catch (_) {
      return [a];
    }
  }

  /// DIFFERENCE of [a] minus the union of all [clips].
  /// Efficiently removes multiple overlapping regions in one clip call.
  static List<List<LatLng>> differenceMulti(
      List<LatLng> a, List<List<LatLng>> clips) {
    if (a.length < 3) return [];
    final validClips = clips.where((c) => c.length >= 3 && bboxOverlap(a, c)).toList();
    if (validClips.isEmpty) return [a];
    try {
      final c = Clipper64();
      c.addPath(_toPath64(a), PathType.subject);
      for (final cl in validClips) c.addPath(_toPath64(cl), PathType.clip);
      final res = c.executeTree(ClipType.difference, FillRule.nonZero);
      if (res == null) return [a];
      final out = _extractOuters(res.tree);
      return out.isEmpty ? [a] : out;
    } catch (_) {
      return [a];
    }
  }

  // ── Validation ──────────────────────────────────────────────────────────────

  /// Returns true if the polygon has any self-intersections (excluding the
  /// endpoint closure and the most-recent [skipRecent] segments).
  /// O(n²) — fine for walking paths < ~500 points.
  static bool hasSelfIntersection(List<LatLng> path, {int skipRecent = 10}) {
    if (path.length < 4) return false;
    final limit = path.length - skipRecent - 1;
    if (limit < 2) return false;
    final p1 = path[path.length - 2];
    final p2 = path.last;
    for (int i = 0; i < limit; i++) {
      if (_segmentsProperlyIntersect(p1, p2, path[i], path[i + 1])) return true;
    }
    return false;
  }

  static bool _segmentsProperlyIntersect(
      LatLng a, LatLng b, LatLng c, LatLng d) {
    final dxAB = b.longitude - a.longitude;
    final dyAB = b.latitude  - a.latitude;
    final dxCD = d.longitude - c.longitude;
    final dyCD = d.latitude  - c.latitude;
    final denom = dxAB * dyCD - dyAB * dxCD;
    if (denom.abs() < 1e-14) return false;
    final dxAC = c.longitude - a.longitude;
    final dyAC = c.latitude  - a.latitude;
    final t = (dxAC * dyCD - dyAC * dxCD) / denom;
    final u = (dxAC * dyAB - dyAC * dxAB) / denom;
    const eps = 0.0001;
    return t > eps && t < 1 - eps && u > eps && u < 1 - eps;
  }

  // ── Geometry helpers ────────────────────────────────────────────────────────

  /// Fast AABB overlap check. Use before expensive clip operations.
  static bool bboxOverlap(List<LatLng> a, List<LatLng> b) {
    if (a.isEmpty || b.isEmpty) return false;
    double aMinLat = a.first.latitude, aMaxLat = a.first.latitude;
    double aMinLng = a.first.longitude, aMaxLng = a.first.longitude;
    for (final p in a) {
      if (p.latitude  < aMinLat) aMinLat = p.latitude;
      if (p.latitude  > aMaxLat) aMaxLat = p.latitude;
      if (p.longitude < aMinLng) aMinLng = p.longitude;
      if (p.longitude > aMaxLng) aMaxLng = p.longitude;
    }
    double bMinLat = b.first.latitude, bMaxLat = b.first.latitude;
    double bMinLng = b.first.longitude, bMaxLng = b.first.longitude;
    for (final p in b) {
      if (p.latitude  < bMinLat) bMinLat = p.latitude;
      if (p.latitude  > bMaxLat) bMaxLat = p.latitude;
      if (p.longitude < bMinLng) bMinLng = p.longitude;
      if (p.longitude > bMaxLng) bMaxLng = p.longitude;
    }
    return !(aMaxLat < bMinLat || aMinLat > bMaxLat ||
             aMaxLng < bMinLng || aMinLng > bMaxLng);
  }

  /// Computes polygon area in square metres via equirectangular projection.
  /// Accurate for areas up to ~50 km across.
  static double areaM2(List<LatLng> polygon) {
    if (polygon.length < 3) return 0;
    const earthR = 6378137.0;
    double sumLat = 0;
    for (final p in polygon) sumLat += p.latitude;
    final meanLat = sumLat / polygon.length;
    final cosLat = math.cos(meanLat * math.pi / 180);
    double area = 0;
    for (int i = 0; i < polygon.length; i++) {
      final p1 = polygon[i];
      final p2 = polygon[(i + 1) % polygon.length];
      final x1 = p1.longitude * (math.pi / 180) * earthR * cosLat;
      final y1 = p1.latitude  * (math.pi / 180) * earthR;
      final x2 = p2.longitude * (math.pi / 180) * earthR * cosLat;
      final y2 = p2.latitude  * (math.pi / 180) * earthR;
      area += (x1 * y2 - x2 * y1);
    }
    return area.abs() / 2;
  }

  /// Extracts bounding box map for Firestore storage.
  static Map<String, double> bboxMap(List<LatLng> polygon) {
    double minLat = polygon.first.latitude, maxLat = polygon.first.latitude;
    double minLng = polygon.first.longitude, maxLng = polygon.first.longitude;
    for (final p in polygon) {
      if (p.latitude  < minLat) minLat = p.latitude;
      if (p.latitude  > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    return {'minLat': minLat, 'maxLat': maxLat, 'minLng': minLng, 'maxLng': maxLng};
  }

  /// Serialises a polygon to a Firestore-compatible list.
  static List<Map<String, double>> polygonToMap(List<LatLng> polygon) =>
      polygon.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList();
}
