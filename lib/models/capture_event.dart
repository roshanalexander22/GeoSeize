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

  CaptureEvent({
    required this.id,
    required this.polygon,
    required this.area,
    required this.timestamp,
    required this.tier,
  });

  factory CaptureEvent.create({required List<LatLng> polygon, required double area}) {
    TerritoryTier assignedTier;
    if (area < 100) {
      assignedTier = TerritoryTier.common;
    } else if (area < 500) {
      assignedTier = TerritoryTier.rare;
    } else if (area < 2000) {
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
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'polygon': polygon.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList(),
      'area': area,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'tier': tier.name,
    };
  }

  factory CaptureEvent.fromJson(Map<String, dynamic> json) {
    return CaptureEvent(
      id: json['id'] as String,
      polygon: (json['polygon'] as List).map((p) => LatLng(p['lat'] as double, p['lng'] as double)).toList(),
      area: json['area'] as double,
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int),
      tier: TerritoryTier.values.firstWhere((e) => e.name == json['tier'], orElse: () => TerritoryTier.common),
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
