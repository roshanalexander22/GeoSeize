import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/capture_event.dart';

class StorageService {
  FirebaseFirestore get _db => FirebaseFirestore.instance;
  FirebaseAuth get _auth => FirebaseAuth.instance;

  String? get _userId => _auth.currentUser?.uid;

  /// Saves the list of capture events to Firestore
  Future<void> saveEvents(List<CaptureEvent> events) async {
    final uid = _userId;
    if (uid == null) return;
    final serializableEvents = events.map((e) => e.toJson()).toList();
    await _db.collection('users').doc(uid).set({
      'events': serializableEvents,
    }, SetOptions(merge: true));
  }

  /// Loads the list of capture events from Firestore
  Future<List<CaptureEvent>> loadEvents() async {
    final uid = _userId;
    if (uid == null) return [];
    try {
      final doc = await _db.collection('users').doc(uid).get();
      if (!doc.exists || doc.data() == null) return [];
      final data = doc.data()!;
      if (data['events'] == null) return [];
      final eventsList = data['events'] as List<dynamic>;
      return eventsList
          .map((json) => CaptureEvent.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('Error loading events from Firestore: $e');
      return [];
    }
  }

  /// Calculates total area from all events
  Future<double> loadTotalArea() async {
    final events = await loadEvents();
    return events.fold<double>(0.0, (sum, e) => sum + e.area);

  }

  // ── Journey-level stats ─────────────────────────────────────────────────────
  // Each element is the net area (m²) gained in one capture journey.
  // Stored separately so they survive zone merges / fusions.

  /// Appends the area gained by a single journey to the persistent history.
  Future<void> addJourneyArea(double area) async {
    final uid = _userId;
    if (uid == null) return;
    final current = await loadJourneyAreas();
    current.add(area);
    await _db.collection('users').doc(uid).set({
      'journeyAreas': current,
    }, SetOptions(merge: true));
  }

  /// Returns all per-journey area values (oldest first).
  Future<List<double>> loadJourneyAreas() async {
    final uid = _userId;
    if (uid == null) return [];
    try {
      final doc = await _db.collection('users').doc(uid).get();
      if (!doc.exists || doc.data() == null) return [];
      final raw = doc.data()!['journeyAreas'];
      if (raw == null) return [];
      return (raw as List<dynamic>).map((v) => (v as num).toDouble()).toList();
    } catch (_) {
      return [];
    }
  }

  /// Wipe all data to start over (deletes the whole user document)
  Future<void> wipeData() async {
    final uid = _userId;
    if (uid == null) return;
    await _db.collection('users').doc(uid).delete();
  }

  /// Remove events whose timestamps fall within [from, to] and save the rest.
  /// Journey history is always cleared because it has no timestamps for filtering.
  Future<void> resetEventsByDateRange(DateTime from, DateTime to) async {
    final uid = _userId;
    if (uid == null) return;
    final events = await loadEvents();
    final remaining = events
        .where((e) => e.timestamp.isBefore(from) || e.timestamp.isAfter(to))
        .toList();
    final serialised = remaining.map((e) => e.toJson()).toList();
    await _db.collection('users').doc(uid).set({
      'events': serialised,
      'journeyAreas': <double>[],
    }, SetOptions(merge: true));
  }
}
