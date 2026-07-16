import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Territory — one owned polygon on the global multiplayer board.
// All territories live in Firestore: `territories/{id}`.
// ─────────────────────────────────────────────────────────────────────────────

class Territory {
  final String id;          // Firestore document ID
  final String ownerId;     // Firebase Auth UID
  final String ownerName;   // display name at time of capture
  final List<LatLng> polygon; // ordered ring
  final double area;        // square metres
  final DateTime capturedAt; // from Firestore serverTimestamp — authoritative
  final Color ownerColor;   // territory fill colour
  final String? regionName; // reverse-geocoded name (optional)

  // Bounding box — denormalised into Firestore for efficient geo queries
  final double bboxMinLat;
  final double bboxMaxLat;
  final double bboxMinLng;
  final double bboxMaxLng;

  const Territory({
    required this.id,
    required this.ownerId,
    required this.ownerName,
    required this.polygon,
    required this.area,
    required this.capturedAt,
    required this.ownerColor,
    this.regionName,
    required this.bboxMinLat,
    required this.bboxMaxLat,
    required this.bboxMinLng,
    required this.bboxMaxLng,
  });

  // ── Firestore serialisation ─────────────────────────────────────────────────

  /// Converts to a Firestore-ready map.
  /// Pass [useServerTimestamp] = true when creating a new document so Firestore
  /// assigns the authoritative timestamp (used for conflict resolution).
  Map<String, dynamic> toMap({bool useServerTimestamp = false}) {
    return {
      'ownerId':    ownerId,
      'ownerName':  ownerName,
      'ownerColor': ownerColor.value.toRadixString(16).padLeft(8, '0'),
      'polygon':    polygon.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList(),
      'area':       area,
      'capturedAt': useServerTimestamp
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(capturedAt),
      'regionName': regionName,
      'bbox': {
        'minLat': bboxMinLat,
        'maxLat': bboxMaxLat,
        'minLng': bboxMinLng,
        'maxLng': bboxMaxLng,
      },
    };
  }

  factory Territory.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    final polyRaw = data['polygon'] as List<dynamic>;
    final polygon = polyRaw
        .map((p) => LatLng(
              (p['lat'] as num).toDouble(),
              (p['lng'] as num).toDouble(),
            ))
        .toList();

    final colorHex = data['ownerColor'] as String? ?? 'ff00e5ff';
    final colorVal = int.tryParse(colorHex, radix: 16) ?? 0xFF00E5FF;

    final ts = data['capturedAt'];
    final DateTime capturedAt =
        ts is Timestamp ? ts.toDate() : DateTime.now();

    final bbox = (data['bbox'] as Map<String, dynamic>?) ?? {};

    return Territory(
      id:          doc.id,
      ownerId:     data['ownerId']   as String,
      ownerName:   (data['ownerName']  as String?) ?? 'Unknown',
      polygon:     polygon,
      area:        (data['area'] as num).toDouble(),
      capturedAt:  capturedAt,
      ownerColor:  Color(colorVal),
      regionName:  data['regionName'] as String?,
      bboxMinLat:  (bbox['minLat'] as num?)?.toDouble() ?? 0,
      bboxMaxLat:  (bbox['maxLat'] as num?)?.toDouble() ?? 0,
      bboxMinLng:  (bbox['minLng'] as num?)?.toDouble() ?? 0,
      bboxMaxLng:  (bbox['maxLng'] as num?)?.toDouble() ?? 0,
    );
  }

  // ── Factory from raw polygon + metadata ─────────────────────────────────────

  factory Territory.create({
    String? id,
    required String ownerId,
    required String ownerName,
    required List<LatLng> polygon,
    required double area,
    required Color ownerColor,
    String? regionName,
  }) {
    double minLat = polygon.first.latitude, maxLat = polygon.first.latitude;
    double minLng = polygon.first.longitude, maxLng = polygon.first.longitude;
    for (final p in polygon) {
      if (p.latitude  < minLat) minLat = p.latitude;
      if (p.latitude  > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    return Territory(
      id:         id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      ownerId:    ownerId,
      ownerName:  ownerName,
      polygon:    polygon,
      area:       area,
      capturedAt: DateTime.now(),
      ownerColor: ownerColor,
      regionName: regionName,
      bboxMinLat: minLat,
      bboxMaxLat: maxLat,
      bboxMinLng: minLng,
      bboxMaxLng: maxLng,
    );
  }

  Territory copyWithPolygon({
    required List<LatLng> polygon,
    required double area,
  }) => Territory.create(
    id:         id,
    ownerId:    ownerId,
    ownerName:  ownerName,
    polygon:    polygon,
    area:       area,
    ownerColor: ownerColor,
    regionName: regionName,
  );
}

// ── Result returned by MultiplayerService.submitCapture ──────────────────────
class CaptureResult {
  /// New territories the player owns after this capture (merged, clipped).
  final List<Territory> ownNewTerritories;

  /// How many distinct rival territories were at least partially conquered.
  final int rivalsConquered;

  /// Total area captured from rivals (m²).
  final double areaFromRivals;

  const CaptureResult({
    required this.ownNewTerritories,
    required this.rivalsConquered,
    required this.areaFromRivals,
  });

  static const CaptureResult empty = CaptureResult(
    ownNewTerritories: [],
    rivalsConquered:   0,
    areaFromRivals:    0,
  );

  double get totalNewArea =>
      ownNewTerritories.fold(0.0, (s, t) => s + t.area);
}
