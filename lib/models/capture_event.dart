import 'package:latlong2/latlong.dart';
import 'package:flutter/material.dart';

enum TerritoryTier {
  common,
  rare,
  epic,
  legendary
}

class CaptureEvent {
  final String id;
  final List<LatLng> polygon;
  final double area;
  final DateTime timestamp;
  final TerritoryTier tier;
  final String username;
  final String? regionName;

  CaptureEvent({
    required this.id,
    required this.polygon,
    required this.area,
    required this.timestamp,
    required this.tier,
    required this.username,
    this.regionName,
  });

  factory CaptureEvent.create({
    required List<LatLng> polygon,
    required double area,
    required String username,
    String? regionName,
    double playerTotalScore = 0,
  }) {
    // Tier is based on the PLAYER's overall total captured area — not per-zone.
    // This ensures all zones share one consistent color at any point in time.
    TerritoryTier assignedTier;
    if (playerTotalScore < 500) {
      assignedTier = TerritoryTier.common;
    } else if (playerTotalScore < 5000) {
      assignedTier = TerritoryTier.rare;
    } else if (playerTotalScore < 20000) {
      assignedTier = TerritoryTier.epic;
    } else {
      assignedTier = TerritoryTier.legendary;
    }

    return CaptureEvent(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      polygon: polygon,
      area: area,
      timestamp: DateTime.now(),
      tier: assignedTier,
      username: username,
      regionName: regionName,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'polygon': polygon.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList(),
      'area': area,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'tier': tier.name,
      'username': username,
      'regionName': regionName,
    };
  }

  factory CaptureEvent.fromJson(Map<String, dynamic> json) {
    return CaptureEvent(
      id: json['id'] as String,
      polygon: (json['polygon'] as List).map((p) => LatLng(p['lat'] as double, p['lng'] as double)).toList(),
      area: json['area'] as double,
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
      tier: TerritoryTier.values.firstWhere((e) => e.name == json['tier'], orElse: () => TerritoryTier.common),
      username: json['username'] as String? ?? 'AGENT',
      regionName: json['regionName'] as String?,
    );
  }

  Color get tierColor {
    switch (tier) {
      case TerritoryTier.common:
        return const Color(0xFF00E5FF); // Cyan
      case TerritoryTier.rare:
        return const Color(0xFF6C63FF); // Purple
      case TerritoryTier.epic:
        return const Color(0xFFFF007F); // Neon Pink
      case TerritoryTier.legendary:
        return const Color(0xFFFFD700); // Gold
    }
  }

  String get tierName {
    return tier.name.toUpperCase();
  }
}
