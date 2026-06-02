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
    if (uid == null) return; // Not logged in
    
    // We save all events in a single document array to minimize Firestore write costs
    List<Map<String, dynamic>> serializableEvents = events.map((e) => e.toJson()).toList();
    
    await _db.collection('users').doc(uid).set({
      'events': serializableEvents
    });
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

      List<dynamic> eventsList = data['events'];
      return eventsList.map((dynamic jsonMap) {
        return CaptureEvent.fromJson(jsonMap as Map<String, dynamic>);
      }).toList();
    } catch (e) {
      print("Error loading events from Firestore: $e");
      return [];
    }
  }

  /// Calculates total area from all events
  Future<double> loadTotalArea() async {
    final events = await loadEvents();
    double total = 0.0;
    for (var event in events) {
      total += event.area;
    }
    return total;
  }

  /// Wipe all data to start over
  Future<void> wipeData() async {
    final uid = _userId;
    if (uid == null) return;
    
    await _db.collection('users').doc(uid).delete();
  }
}
