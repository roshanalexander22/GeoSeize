import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../models/territory.dart';
import '../utils/polygon_clip.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MultiplayerService — singleton that owns the live territory board.
//
// Responsibilities:
//   • Stream all territories visible in the player's geographic window.
//   • Submit captures via Firestore transactions (atomic read-clip-write).
//   • Resolve all 4 ownership cases with polygon boolean operations.
//   • Never trust client clocks — always use FieldValue.serverTimestamp().
// ─────────────────────────────────────────────────────────────────────────────
class MultiplayerService {
  MultiplayerService._();
  static final MultiplayerService instance = MultiplayerService._();

  // ── Configuration ────────────────────────────────────────────────────────────
  /// Minimum area (m²) for any captured polygon to be written to Firestore.
  static const double minCaptureAreaM2 = 5.0;

  /// Minimum area (m²) for a fragmented remainder piece to be kept.
  static const double minFragmentAreaM2 = 1.0;

  /// Geographic half-window (degrees) for the territory stream.
  /// ~5.5 km at the equator; tiles outside this range are not streamed.
  static const double streamHalfWindowLat = 0.05;
  static const double streamHalfWindowLng = 0.07;

  // ── Internal state ───────────────────────────────────────────────────────────
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  final StreamController<List<Territory>> _territoryController =
      StreamController<List<Territory>>.broadcast();

  StreamSubscription<QuerySnapshot>? _firestoreSub;

  /// Live list maintained by the Firestore listener.
  final List<Territory> _cachedTerritories = [];

  // ── Public stream ────────────────────────────────────────────────────────────

  /// Broadcasts the current list of territories every time Firestore changes.
  Stream<List<Territory>> get territoriesStream => _territoryController.stream;

  /// Returns the most-recently cached list without waiting for a new event.
  List<Territory> get cachedTerritories => List.unmodifiable(_cachedTerritories);

  // ── Stream lifecycle ─────────────────────────────────────────────────────────

  /// Start (or restart) listening to the geographic window around [centre].
  /// Call this once on app start and whenever the player moves significantly.
  void startListening(LatLng centre) {
    _firestoreSub?.cancel();

    final minLat = centre.latitude  - streamHalfWindowLat;
    final maxLat = centre.latitude  + streamHalfWindowLat;
    final minLng = centre.longitude - streamHalfWindowLng;
    final maxLng = centre.longitude + streamHalfWindowLng;

    // Firestore limitation: only one field may use an inequality filter.
    // We filter by bbox.maxLat >= minLat (territories that reach into the window
    // from below), then client-side filter the remaining three sides.
    _firestoreSub = _db
        .collection('territories')
        .where('bbox.maxLat', isGreaterThanOrEqualTo: minLat)
        .snapshots()
        .listen((snapshot) {
      _cachedTerritories.clear();
      for (final doc in snapshot.docs) {
        try {
          final t = Territory.fromFirestore(doc);
          // Client-side bounding-box filter for the remaining three edges
          if (t.bboxMinLat <= maxLat &&
              t.bboxMinLng <= maxLng &&
              t.bboxMaxLng >= minLng) {
            _cachedTerritories.add(t);
          }
        } catch (e) {
          debugPrint('[Multiplayer] Failed to parse territory ${doc.id}: $e');
        }
      }
      if (!_territoryController.isClosed) {
        _territoryController.add(List.unmodifiable(_cachedTerritories));
      }
    }, onError: (e) {
      debugPrint('[Multiplayer] Firestore stream error: $e');
    });
  }

  /// Re-centres the listening window when the player moves far enough.
  void updateCentre(LatLng centre) => startListening(centre);

  /// Stop listening and release resources.
  void dispose() {
    _firestoreSub?.cancel();
    _firestoreSub = null;
    if (!_territoryController.isClosed) _territoryController.close();
  }

  // ── Capture submission ───────────────────────────────────────────────────────

  /// Submits a completed loop to Firestore.
  ///
  /// Algorithm (all inside a single atomic transaction):
  ///   1. Re-read every candidate territory doc by ID (fresh server read).
  ///   2. Own territories that overlap → delete (will be replaced by merged result).
  ///   3. Rival territories that overlap:
  ///        • conquered portion (intersection) → new doc owned by submitter.
  ///        • remainder (difference) → keep original owner, update/split doc.
  ///   4. All unclaimed land inside the loop → new doc owned by submitter.
  ///   5. Own territories from step 2 + unclaimed + conquered → union → new docs.
  ///   6. Every new doc uses FieldValue.serverTimestamp() (conflict resolution).
  ///
  /// Returns a [CaptureResult] describing what changed, or [CaptureResult.empty]
  /// if the polygon was invalid or produced no net new area.
  Future<CaptureResult> submitCapture({
    required List<LatLng> newPolygon,
    required String ownerId,
    required String ownerName,
    required Color ownerColor,
    String? regionName,
  }) async {
    // ── Pre-flight validation ─────────────────────────────────────────────────
    if (newPolygon.length < 3) return CaptureResult.empty;
    final totalArea = PolygonClip.areaM2(newPolygon);
    if (totalArea < minCaptureAreaM2) return CaptureResult.empty;

    // ── Identify candidate territories from cache ─────────────────────────────
    // Cache may be slightly stale; the transaction re-reads for consistency.
    final candidates = _cachedTerritories
        .where((t) => PolygonClip.bboxOverlap(newPolygon, t.polygon))
        .toList();

    final candidateRefs = candidates
        .map((t) => _db.collection('territories').doc(t.id))
        .toList();

    // ── Run the atomic Firestore transaction ──────────────────────────────────
    try {
      return await _db.runTransaction<CaptureResult>((txn) async {
        // Read all candidate docs atomically (Firestore guarantees consistency).
        final snapshots = candidateRefs.isEmpty
            ? <DocumentSnapshot>[]
            : await Future.wait(candidateRefs.map((ref) => txn.get(ref)));

        // Build fresh territory list from server reads.
        final fresh = <Territory>[];
        for (final snap in snapshots) {
          if (!snap.exists) continue;
          try {
            fresh.add(Territory.fromFirestore(snap));
          } catch (_) {}
        }

        // Re-filter: some may no longer overlap after a concurrent write.
        final ownOverlap = fresh
            .where((t) =>
                t.ownerId == ownerId &&
                PolygonClip.bboxOverlap(newPolygon, t.polygon) &&
                PolygonClip.intersection(newPolygon, t.polygon).isNotEmpty)
            .toList();
        final rivalOverlap = fresh
            .where((t) =>
                t.ownerId != ownerId &&
                PolygonClip.bboxOverlap(newPolygon, t.polygon) &&
                PolygonClip.intersection(newPolygon, t.polygon).isNotEmpty)
            .toList();

        // ── Step 1: Compute geometry ──────────────────────────────────────────

        // All existing polygons that overlap (own + rivals) — used to find unclaimed land.
        final allExistingPolys = [
          ...ownOverlap.map((t) => t.polygon),
          ...rivalOverlap.map((t) => t.polygon),
        ];

        // Unclaimed portions: the new polygon minus all existing territories.
        final unclaimedParts = PolygonClip.differenceMulti(newPolygon, allExistingPolys);

        // Per-rival: what is conquered, what remains with the rival.
        final conqueredParts = <List<LatLng>>[];
        final remaindersByRival = <String, List<List<LatLng>>>{}; // territoryId → remainders

        double areaFromRivals = 0;
        for (final rival in rivalOverlap) {
          final conquered = PolygonClip.intersection(newPolygon, rival.polygon);
          final remaining = PolygonClip.difference(rival.polygon, newPolygon);

          final validConquered =
              conquered.where((p) => PolygonClip.areaM2(p) >= minFragmentAreaM2).toList();
          final validRemaining =
              remaining.where((p) => PolygonClip.areaM2(p) >= minFragmentAreaM2).toList();

          if (validConquered.isNotEmpty) {
            conqueredParts.addAll(validConquered);
            areaFromRivals += validConquered.fold(0.0, (s, p) => s + PolygonClip.areaM2(p));
            remaindersByRival[rival.id] = validRemaining;
          }
        }

        // Player's full new territory = ownPolys ∪ unclaimed ∪ conquered.
        final playerPolys = PolygonClip.union(
          [...ownOverlap.map((t) => t.polygon), ...unclaimedParts],
          conqueredParts,
        );

        // Filter tiny slivers.
        final validPlayerPolys =
            playerPolys.where((p) => PolygonClip.areaM2(p) >= minCaptureAreaM2).toList();

        // Bail if nothing meaningful was captured.
        if (validPlayerPolys.isEmpty && conqueredParts.isEmpty) {
          return CaptureResult.empty;
        }

        // ── Step 2: Write to Firestore ────────────────────────────────────────

        // Delete own overlapping territories (merged into new ones below).
        for (final t in ownOverlap) {
          txn.delete(_db.collection('territories').doc(t.id));
        }

        // Process rival territories.
        for (final rival in rivalOverlap) {
          final ref = _db.collection('territories').doc(rival.id);
          final remainders = remaindersByRival[rival.id];

          if (remainders == null || remainders.isEmpty) {
            // Entire rival territory conquered — delete.
            txn.delete(ref);
          } else {
            // Partial conquest — update existing doc with first remainder,
            // create new docs for any additional fragments (territory fragmentation).
            final firstRemainder = remainders.first;
            txn.update(ref, {
              'polygon': PolygonClip.polygonToMap(firstRemainder),
              'area':    PolygonClip.areaM2(firstRemainder),
              'bbox':    PolygonClip.bboxMap(firstRemainder),
            });
            for (int i = 1; i < remainders.length; i++) {
              final newRef = _db.collection('territories').doc();
              final fragArea = PolygonClip.areaM2(remainders[i]);
              txn.set(newRef, Territory.create(
                ownerId:    rival.ownerId,
                ownerName:  rival.ownerName,
                polygon:    remainders[i],
                area:       fragArea,
                ownerColor: rival.ownerColor,
                regionName: rival.regionName,
              ).toMap());
            }
          }
        }

        // Create new territory documents for the capturing player.
        final newTerritories = <Territory>[];
        for (final poly in validPlayerPolys) {
          final area = PolygonClip.areaM2(poly);
          final newRef = _db.collection('territories').doc();
          final t = Territory.create(
            id:         newRef.id,
            ownerId:    ownerId,
            ownerName:  ownerName,
            polygon:    poly,
            area:       area,
            ownerColor: ownerColor,
            regionName: regionName,
          );
          // useServerTimestamp=true so capturedAt is assigned by Firestore.
          txn.set(newRef, t.toMap(useServerTimestamp: true));
          newTerritories.add(t);
        }

        return CaptureResult(
          ownNewTerritories: newTerritories,
          rivalsConquered:   rivalOverlap.length,
          areaFromRivals:    areaFromRivals,
        );
      }, maxAttempts: 5);
    } catch (e) {
      debugPrint('[Multiplayer] Transaction failed: $e');
      return CaptureResult.empty;
    }
  }

  // ── Migration helper ─────────────────────────────────────────────────────────

  /// Promotes existing per-user events from `users/{uid}/events` into the
  /// global `territories` collection so they become visible to other players.
  /// Safe to call multiple times — already-migrated territories are skipped.
  Future<void> migrateExistingEvents({
    required String ownerId,
    required String ownerName,
    required Color ownerColor,
    required List<Map<String, dynamic>> rawEvents,
  }) async {
    // Check if player already has territories in the global collection.
    final existing = await _db
        .collection('territories')
        .where('ownerId', isEqualTo: ownerId)
        .limit(1)
        .get();
    if (existing.docs.isNotEmpty) return; // already migrated

    debugPrint('[Multiplayer] Migrating ${rawEvents.length} existing events...');
    final batch = _db.batch();
    for (final json in rawEvents) {
      try {
        final polyRaw = json['polygon'] as List<dynamic>;
        final polygon = polyRaw
            .map((p) => LatLng(
                  (p['lat'] as num).toDouble(),
                  (p['lng'] as num).toDouble(),
                ))
            .toList();
        if (polygon.length < 3) continue;
        final area = PolygonClip.areaM2(polygon);
        if (area < minCaptureAreaM2) continue;

        final ref = _db.collection('territories').doc();
        final t = Territory.create(
          id:         ref.id,
          ownerId:    ownerId,
          ownerName:  ownerName,
          polygon:    polygon,
          area:       area,
          ownerColor: ownerColor,
          regionName: json['regionName'] as String?,
        );
        batch.set(ref, t.toMap());
      } catch (e) {
        debugPrint('[Multiplayer] Skipping bad event during migration: $e');
      }
    }
    await batch.commit().timeout(const Duration(seconds: 10));
    debugPrint('[Multiplayer] Migration complete.');
  }
}
