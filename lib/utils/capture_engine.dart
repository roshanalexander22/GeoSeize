import 'package:latlong2/latlong.dart';
import 'package:clipper2/clipper2.dart';

/// Pure-geometry territory capture engine.
/// No Flutter imports — all logic is testable in isolation.
///
/// Implements every case from the Territory Capture Logic Specification:
///   Case 1   – First capture via self-crossing loop
///   Case 2   – Multiple independent loops in one journey
///   Case 3A  – Expand zone by exiting and reconnecting to own boundary
///   Case 3B  – Start outside, pass through zone, reconnect to boundary
///   Case 4   – Connect / fuse multiple existing zones
///   Case 5   – Nested loop inside existing territory (no-op)
///   Case 6   – Self-intersection creating several loops
///   Case 7   – Touching without crossing (no capture)
///   Case 8   – Reconnect to any owned zone boundary
///   Case 9   – Overlapping existing territory (union handles it)
class CaptureEngine {

  // ──────────────────────────────────────────────────────────────────────────
  // 1.  PRIMITIVE — exact 2-D line-segment intersection
  // ──────────────────────────────────────────────────────────────────────────

  /// Returns the intersection point if segments AB and CD properly cross,
  /// null when parallel, collinear, or touching only at an endpoint.
  ///
  /// Works in lat/lng degrees — accurate for areas < a few kilometres.
  static LatLng? segmentIntersection(
      LatLng a, LatLng b, LatLng c, LatLng d) {
    final dxAB = b.longitude - a.longitude;
    final dyAB = b.latitude  - a.latitude;
    final dxCD = d.longitude - c.longitude;
    final dyCD = d.latitude  - c.latitude;

    final denom = dxAB * dyCD - dyAB * dxCD;
    if (denom.abs() < 1e-14) return null; // parallel / collinear

    final dxAC = c.longitude - a.longitude;
    final dyAC = c.latitude  - a.latitude;

    final t = (dxAC * dyCD - dyAC * dxCD) / denom;
    final u = (dxAC * dyAB - dyAC * dxAB) / denom;

    // Use a small epsilon to avoid endpoint-only touches (GPS artefacts)
    const eps = 0.0001;
    if (t > eps && t < 1 - eps && u > eps && u < 1 - eps) {
      return LatLng(a.latitude + t * dyAB, a.longitude + t * dxAB);
    }
    return null;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 2.  ZONE-BOUNDARY CROSSING  (Cases 3A, 3B, 4, 8)
  // ──────────────────────────────────────────────────────────────────────────

  /// Checks whether the walk-step [prev → curr] crosses any edge of any
  /// existing zone.  Returns the exact crossing point and zone index, or null.
  static ({LatLng crossPoint, int zoneIndex})? checkZoneCrossing(
      LatLng prev, LatLng curr, List<List<LatLng>> zones) {
    for (int z = 0; z < zones.length; z++) {
      final poly = zones[z];
      for (int i = 0; i < poly.length; i++) {
        final p1 = poly[i];
        final p2 = poly[(i + 1) % poly.length];
        final hit = segmentIntersection(prev, curr, p1, p2);
        if (hit != null) return (crossPoint: hit, zoneIndex: z);
      }
    }
    return null;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 3.  SELF-INTERSECTION  (Cases 1, 2, 6)
  // ──────────────────────────────────────────────────────────────────────────

  /// Checks whether the walk-step [prev → curr] crosses any earlier segment
  /// of [path].  The [skipRecent] most-recent segments are ignored to avoid
  /// false positives from consecutive GPS points on a straight line.
  ///
  /// Returns the exact crossing point and the index of the crossed segment
  /// (i.e. the segment from path[segmentIndex] to path[segmentIndex+1]).
  static ({LatLng crossPoint, int segmentIndex})? checkSelfIntersection(
      LatLng prev, LatLng curr, List<LatLng> path,
      {int skipRecent = 10}) {
    final limit = path.length - skipRecent - 1;
    if (limit < 2) return null;

    for (int i = 0; i < limit; i++) {
      final hit = segmentIntersection(prev, curr, path[i], path[i + 1]);
      if (hit != null) return (crossPoint: hit, segmentIndex: i);
    }
    return null;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 4.  RESOLVE & MERGE  (all cases)
  // ──────────────────────────────────────────────────────────────────────────

  /// Merges [newPolygon] with [existingZones] via Clipper2 polygon union.
  ///
  /// Returns [existingZones] (the SAME list reference) when [newPolygon] is
  /// entirely inside existing territory (Case 5 — nested loop).  The caller
  /// can detect this cheaply with `identical(result, existingZones)`.
  ///
  /// Otherwise returns the new merged zone list (Case 9 overlap is handled
  /// automatically by the union operation).
  static List<List<LatLng>> resolveCapture(
      List<LatLng> newPolygon, List<List<LatLng>> existingZones) {
    if (newPolygon.length < 3) return existingZones;

    const double scale = 10000000.0;

    Path64 toPath64(List<LatLng> pts) => pts
        .map((p) => Point64(
              (p.longitude * scale).round(),
              (p.latitude  * scale).round(),
            ))
        .toList();

    final newPath64       = toPath64(newPolygon);
    final existingPaths64 = existingZones.map(toPath64).toList();

    // ── Union ────────────────────────────────────────────────────────────────
    final clipper = Clipper64();
    clipper.addPath(newPath64, PathType.subject);
    if (existingPaths64.isNotEmpty) {
      clipper.addPaths(existingPaths64, PathType.clip);
    }

    final tree = clipper
            .executeTree(ClipType.union, FillRule.nonZero)
            ?.tree ??
        PolyTree64();

    final merged = <Path64>[];
    void extractOuters(PolyPath64 node) {
      if (!node.isHole &&
          node.polygon != null &&
          node.polygon!.isNotEmpty) {
        merged.add(node.polygon!);
      }
      for (final child in node.children) extractOuters(child);
    }
    for (final child in tree.children) extractOuters(child);

    // Convert back to LatLng polygons
    final result = <List<LatLng>>[];
    for (final p in merged) {
      final poly = <LatLng>[];
      for (final pt in p) {
        final lat = pt.y / scale;
        final lng = pt.x / scale;
        if (!lat.isNaN && !lat.isInfinite &&
            !lng.isNaN && !lng.isInfinite &&
            lat >= -90  && lat <= 90 &&
            lng >= -180 && lng <= 180) {
          poly.add(LatLng(lat, lng));
        }
      }
      if (poly.length >= 3) result.add(poly);
    }

    if (result.isEmpty) return existingZones;

    // ── Case 5 detection ─────────────────────────────────────────────────────
    // If the union added essentially no new area, the new polygon was entirely
    // inside existing territory.  Return the same reference so the caller can
    // detect the no-op with `identical()`.
    final existingArea = _pathsArea64(existingPaths64);
    final resultArea   = _pathsArea64(merged);
    if (existingArea > 0 && (resultArea - existingArea) / existingArea < 0.005) {
      return existingZones; // ← same reference, < 0.5 % new area added
    }

    return result;
  }

  // ── private helpers ───────────────────────────────────────────────────────

  static double _area64(Path64 path) {
    double a = 0;
    for (int i = 0; i < path.length; i++) {
      final p1 = path[i];
      final p2 = path[(i + 1) % path.length];
      a += (p1.x * p2.y - p2.x * p1.y).toDouble();
    }
    return a.abs() / 2;
  }

  static double _pathsArea64(List<Path64> paths) =>
      paths.fold(0.0, (sum, p) => sum + _area64(p));
}
