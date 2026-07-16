import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/daily_mission.dart';
import '../models/shop_item.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ProgressionService — coins, shop purchases, equipped cosmetics, daily missions
// All data lives in Firestore under users/{uid}/progression
// ─────────────────────────────────────────────────────────────────────────────
class ProgressionService {
  ProgressionService._();
  static final ProgressionService instance = ProgressionService._();

  FirebaseFirestore get _db => FirebaseFirestore.instance;
  FirebaseAuth get _auth => FirebaseAuth.instance;
  String? get _uid => _auth.currentUser?.uid;

  // ── Helpers ─────────────────────────────────────────────────────────────────
  DocumentReference? get _doc {
    final uid = _uid;
    if (uid == null) return null;
    return _db.collection('users').doc(uid).collection('progression').doc('data');
  }

  Future<Map<String, dynamic>> _getData() async {
    final ref = _doc;
    if (ref == null) return {};
    try {
      final snap = await ref.get().timeout(const Duration(seconds: 6));
      if (!snap.exists) return {};
      return (snap.data() as Map<String, dynamic>?) ?? {};
    } catch (_) {
      // Covers TimeoutException, network errors, Firestore rules denials, etc.
      return {};
    }
  }

  Future<void> _setData(Map<String, dynamic> data) async {
    final ref = _doc;
    if (ref == null) return;
    try {
      await ref.set(data, SetOptions(merge: true)).timeout(const Duration(seconds: 6));
    } catch (_) {
      // Swallow write errors silently — UI should not be blocked by saves
    }
  }

  // ── Coin wallet ──────────────────────────────────────────────────────────────
  Future<int> getCoins() async {
    final data = await _getData();
    return (data['coins'] as num?)?.toInt() ?? 0;
  }

  Future<void> addCoins(int amount) async {
    final current = await getCoins();
    await _setData({'coins': current + amount});
  }

  /// Returns true if successful, false if insufficient funds.
  Future<bool> spendCoins(int amount) async {
    final current = await getCoins();
    if (current < amount) return false;
    await _setData({'coins': current - amount});
    return true;
  }

  // ── Purchased items ──────────────────────────────────────────────────────────
  Future<List<String>> getPurchasedItems() async {
    final data = await _getData();
    final raw = data['purchasedItems'];
    if (raw == null) return [];
    return (raw as List<dynamic>).cast<String>();
  }

  Future<bool> isOwned(String itemId) async {
    final owned = await getPurchasedItems();
    return owned.contains(itemId);
  }

  /// Attempts to buy an item. Returns true on success, false if already owned
  /// or insufficient funds.
  Future<bool> purchaseItem(ShopItem item) async {
    if (await isOwned(item.id)) return false;
    final success = await spendCoins(item.price);
    if (!success) return false;
    final owned = await getPurchasedItems();
    owned.add(item.id);
    await _setData({'purchasedItems': owned});
    return true;
  }

  // ── Equipped cosmetics ───────────────────────────────────────────────────────
  Future<Map<String, String?>> getEquipped() async {
    final data = await _getData();
    return {
      'color':     data['equippedColor']    as String?,
      'marker':    data['equippedMarker']   as String?,
      'frame':     data['equippedFrame']    as String?,
      'titlebar':  data['equippedTitlebar'] as String?,
    };
  }

  Future<void> equipItem(String slot, String? itemId) async {
    final key = 'equipped${slot[0].toUpperCase()}${slot.substring(1)}';
    await _setData({key: itemId});
  }

  // ── Load another player's equipped cosmetics (for Statistics screen) ─────────
  Future<Map<String, String?>> getEquippedForUser(String uid) async {
    try {
      final snap = await _db
          .collection('users')
          .doc(uid)
          .collection('progression')
          .doc('data')
          .get();
      if (!snap.exists) return {};
      final data = (snap.data() as Map<String, dynamic>?) ?? {};
      return {
        'color':    data['equippedColor']    as String?,
        'marker':   data['equippedMarker']   as String?,
        'frame':    data['equippedFrame']    as String?,
        'titlebar': data['equippedTitlebar'] as String?,
      };
    } catch (_) {
      return {};
    }
  }

  // ── Daily missions ───────────────────────────────────────────────────────────
  String _todayStr() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  /// Returns today's missions, generating fresh ones if the date has changed.
  Future<List<DailyMission>> getDailyMissions() async {
    final data = await _getData();
    final storedDate = data['missionsDate'] as String?;
    final today = _todayStr();

    if (storedDate == today) {
      // Return existing missions for today
      final raw = data['missions'] as List<dynamic>?;
      if (raw != null && raw.isNotEmpty) {
        return raw
            .map((j) => DailyMission.fromJson(j as Map<String, dynamic>))
            .toList();
      }
    }

    // New day → generate fresh missions (no progress carried over)
    final missions = MissionTemplates.forDate(today);
    await _setData({
      'missionsDate': today,
      'missions': missions.map((m) => m.toJson()).toList(),
    });
    return missions;
  }

  /// Updates the progress of a specific mission type.
  /// [type] is the mission type enum, [delta] is the amount of progress to add.
  Future<void> addMissionProgress(MissionType type, double delta) async {
    if (delta <= 0) return;
    final missions = await getDailyMissions();
    bool changed = false;

    for (final m in missions) {
      if (m.type == type && !m.completed) {
        m.progress = (m.progress + delta).clamp(0, m.goal);
        if (m.progress >= m.goal) {
          m.completed = true;
        }
        changed = true;
      }
    }

    if (changed) {
      await _setData({
        'missions': missions.map((m) => m.toJson()).toList(),
      });
    }
  }

  /// Claims the reward for a completed mission. Returns coins awarded, or 0.
  Future<int> claimMission(String missionId) async {
    final missions = await getDailyMissions();
    final idx = missions.indexWhere((m) => m.id == missionId);
    if (idx < 0) return 0;
    final mission = missions[idx];
    if (!mission.completed || mission.claimed) return 0;

    mission.claimed = true;
    await addCoins(mission.coinReward);
    await _setData({
      'missions': missions.map((m) => m.toJson()).toList(),
    });
    return mission.coinReward;
  }
}
