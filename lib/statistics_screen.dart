import 'dart:ui';
import 'dart:io' show File;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'models/capture_event.dart';
import 'models/shop_item.dart';
import 'services/storage_service.dart';
import 'services/settings_service.dart';
import 'services/auth_service.dart';
import 'services/progression_service.dart';
import 'utils/level_system.dart';
import 'utils/rewards_system.dart';

class StatisticsScreen extends StatefulWidget {
  /// When null → shows the signed-in player's own stats.
  /// When set → header shows this username (multiplayer: will load that user's Firestore data).
  final String? ownerUsername;
  const StatisticsScreen({super.key, this.ownerUsername});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  final StorageService _storageService = StorageService();
  final AuthService    _authService    = AuthService();

  List<CaptureEvent> _events       = [];
  List<double>       _journeyAreas = []; // per-journey area history
  bool               _isLoading    = true;
  bool               _isRemotePlayer = false;
  // Firestore summary stats for another player (null when viewing own stats)
  Map<String, dynamic>? _remoteStats;
  // Equipped cosmetics for the profile being viewed
  Map<String, String?> _cosmetics = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    String currentUsername = 'AGENT';
    final user = _authService.currentUser;
    if (user != null) {
      final name = await _authService.getUsername(user.uid);
      if (name != null && name.isNotEmpty) {
        currentUsername = name;
      }
    }

    if (widget.ownerUsername != null && widget.ownerUsername != currentUsername) {
      // ── Remote player: load from Firestore ─────────────────────────────────
      _isRemotePlayer = true;
      final data = await _authService.getUserStatsByUsername(widget.ownerUsername!);
      // Load their equipped cosmetics by UID (from stats data if available)
      Map<String, String?> cosmetics = {};
      final remoteUid = data?['uid'] as String?;
      if (remoteUid != null) {
        cosmetics = await ProgressionService.instance.getEquippedForUser(remoteUid);
      }
      if (!mounted) return;
      setState(() {
        _remoteStats = data?['stats'] as Map<String, dynamic>?;
        _cosmetics   = cosmetics;
        _isLoading   = false;
      });
    } else {
      // ── Own player: load from local storage ─────────────────────────────────
      _isRemotePlayer = false;
      final events   = await _storageService.loadEvents();
      final journeys = await _storageService.loadJourneyAreas();
      final cosmetics = await ProgressionService.instance.getEquipped();
      events.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      if (!mounted) return;
      setState(() {
        _events       = events;
        _journeyAreas = journeys;
        _cosmetics    = cosmetics;
        _isLoading    = false;
      });
    }
  }

  // ── Formatting ───────────────────────────────────────────────────────────────
  String _formatArea(double sqMeters) {
    final useMetric = SettingsService().useMetric.value;
    if (useMetric) {
      if (sqMeters >= 1000000) return '${(sqMeters / 1000000).toStringAsFixed(2)} km²';
      return '${sqMeters.toStringAsFixed(1)} m²';
    } else {
      final sqFeet = sqMeters * 10.7639;
      if (sqFeet >= 27878400) return '${(sqFeet / 27878400).toStringAsFixed(2)} mi²';
      return '${sqFeet.toStringAsFixed(1)} ft²';
    }
  }

  // ── Rank overview bottom sheet ───────────────────────────────────────────────
  void _showRankSheet(int currentLevel) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        builder: (ctx, scroll) {
          final secColor = Theme.of(context).colorScheme.secondary;
          return Container(
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              children: [
                // Drag handle
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 8),
                  child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Row(
                    children: [
                      Icon(Icons.military_tech, color: secColor),
                      const SizedBox(width: 10),
                      Text('RANK OVERVIEW', style: TextStyle(color: secColor, fontWeight: FontWeight.bold, letterSpacing: 2, fontSize: 14)),
                    ],
                  ),
                ),
                const Divider(color: Colors.white10),
                Expanded(
                  child: ListView.builder(
                    controller: scroll,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: LevelSystem.maxLevel,
                    itemBuilder: (_, i) {
                      final level      = i + 1;
                      final rankName   = LevelSystem.getRankTitle(level);
                      final minArea    = LevelSystem.getMinAreaForLevel(level);
                      final isCurrent  = level == currentLevel;
                      final isUnlocked = level <= currentLevel;

                      // Rewards at this level
                      final unlockedColors  = RewardsSystem.colors .where((c) => c.requiredLevel == level).toList();
                      final unlockedAvatars = RewardsSystem.avatars.where((a) => a.requiredLevel == level).toList();

                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isCurrent
                              ? secColor.withValues(alpha: 0.12)
                              : isUnlocked
                                  ? Colors.white.withValues(alpha: 0.04)
                                  : Colors.black.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isCurrent
                                ? secColor.withValues(alpha: 0.6)
                                : isUnlocked
                                    ? Colors.white.withValues(alpha: 0.1)
                                    : Colors.white.withValues(alpha: 0.04),
                            width: isCurrent ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                // Level badge
                                Container(
                                  width: 36, height: 36,
                                  decoration: BoxDecoration(
                                    color: isUnlocked ? secColor.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isUnlocked ? secColor : Colors.white24,
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      '$level',
                                      style: TextStyle(
                                        color: isUnlocked ? secColor : Colors.white38,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        rankName,
                                        style: TextStyle(
                                          color: isUnlocked ? Colors.white : Colors.white38,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                        ),
                                      ),
                                      Text(
                                        minArea == 0 ? 'Starting rank' : '≥ ${_formatArea(minArea)}',
                                        style: TextStyle(
                                          color: isUnlocked ? Colors.white54 : Colors.white24,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isCurrent)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: secColor.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: secColor.withValues(alpha: 0.5)),
                                    ),
                                    child: Text('CURRENT', style: TextStyle(color: secColor, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1)),
                                  ),
                                if (!isUnlocked)
                                  const Icon(Icons.lock, color: Colors.white24, size: 16),
                              ],
                            ),

                            // Rewards row
                            if (unlockedColors.isNotEmpty || unlockedAvatars.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              const Divider(color: Colors.white10, height: 1),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  const Icon(Icons.card_giftcard, color: Colors.amber, size: 13),
                                  const SizedBox(width: 6),
                                  Text(
                                    'REWARDS',
                                    style: TextStyle(color: Colors.amber.withValues(alpha: 0.8), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                children: [
                                  ...unlockedColors.map((c) => _rewardChip(
                                    label: c.name,
                                    color: c.color,
                                    isColor: true,
                                    unlocked: isUnlocked,
                                  )),
                                  ...unlockedAvatars.map((a) => _rewardChip(
                                    label: a.name,
                                    emoji: a.emoji,
                                    color: secColor,
                                    isColor: false,
                                    unlocked: isUnlocked,
                                  )),
                                ],
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _rewardChip({
    required String label,
    String? emoji,
    required Color color,
    required bool isColor,
    required bool unlocked,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: unlocked ? 0.15 : 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: unlocked ? 0.4 : 0.1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isColor)
            Container(width: 10, height: 10, decoration: BoxDecoration(color: unlocked ? color : Colors.white24, shape: BoxShape.circle))
          else
            Text(emoji ?? '⭐', style: TextStyle(fontSize: 12, color: unlocked ? null : Colors.white24)),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(color: unlocked ? Colors.white70 : Colors.white24, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  // ── Framed avatar (renders equipped frame ring or default border) ────────────
  Widget _buildFramedAvatar({
    required Widget child,
    required ShopItem? frame,
    required Color priColor,
  }) {
    if (frame != null && frame.frameColors != null) {
      final colors = frame.frameColors!;
      return Container(
        width: 84, height: 84,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: SweepGradient(colors: [...colors, colors.first]),
          boxShadow: [BoxShadow(color: colors.first.withValues(alpha: 0.5), blurRadius: 16)],
        ),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Container(
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF080810)),
            child: ClipOval(child: child),
          ),
        ),
      );
    }
    // Default priColor border
    return Container(
      width: 84, height: 84,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: priColor, width: 2),
        boxShadow: [BoxShadow(color: priColor.withValues(alpha: 0.3), blurRadius: 15, spreadRadius: 2)],
      ),
      child: ClipOval(child: child),
    );
  }

  // ── Stat card ────────────────────────────────────────────────────────────────
  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.5),
          border: Border.all(color: color.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.05), blurRadius: 10, spreadRadius: 1)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 12),
            Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 4),
            Text(title, style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.5), letterSpacing: 1, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // ── Determine data source: own (local) or another player (Firestore) ───────
    final double totalArea;
    final double maxJourneyArea;
    final double avgJourneyArea;
    final int    zonesCount;
    final int    daysActive;
    final double aggressiveness;

    if (_isRemotePlayer) {
      final s = _remoteStats;
      if (s != null) {
        totalArea      = (s['totalArea']      as num?)?.toDouble() ?? 0.0;
        maxJourneyArea = (s['maxJourneyArea'] as num?)?.toDouble() ?? 0.0;
        avgJourneyArea = (s['avgJourneyArea'] as num?)?.toDouble() ?? 0.0;
        zonesCount     = (s['zonesCount']     as num?)?.toInt()    ?? 0;
        daysActive     = (s['daysActive']     as num?)?.toInt()    ?? 0;
        aggressiveness = (s['aggressiveness'] as num?)?.toDouble() ?? 0.0;
      } else {
        // Player exists but hasn't synced stats to Firestore yet
        totalArea = 0; maxJourneyArea = 0; avgJourneyArea = 0;
        zonesCount = 0; daysActive = 0; aggressiveness = 0;
      }
    } else {
      totalArea = _events.fold(0.0, (sum, e) => sum + e.area);
      maxJourneyArea = _journeyAreas.isEmpty ? 0.0 : _journeyAreas.reduce((a, b) => a > b ? a : b);
      avgJourneyArea = _journeyAreas.isEmpty ? 0.0 : totalArea / _journeyAreas.length;
      zonesCount = _events.length;
      final now2 = DateTime.now();
      final recentCaptures = _events.where((e) => now2.difference(e.timestamp).inDays <= 7).length;
      aggressiveness = _events.isEmpty ? 0 : (recentCaptures / 5.0).clamp(0.0, 1.0) * 100;
      daysActive = _events.isEmpty
          ? 0
          : now2.difference(_events.map((e) => e.timestamp).reduce((a, b) => a.isBefore(b) ? a : b)).inDays + 1;
    }

    final int currentLevel  = LevelSystem.getLevel(totalArea);
    final String rankTitle  = LevelSystem.getRankTitle(currentLevel);

    final regionAreas = <String, double>{};
    for (var e in _events) {
      final region = e.regionName ?? 'UNKNOWN SECTOR';
      regionAreas[region] = (regionAreas[region] ?? 0) + e.area;
    }
    final sortedRegions = regionAreas.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    final Color secColor = Theme.of(context).colorScheme.secondary;
    final Color priColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('STATISTICS', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile header
            FutureBuilder<String?>(
              future: _authService.getUsername(_authService.currentUser?.uid ?? ''),
              builder: (context, snapshot) {
                // If opened from a zone tap, show that zone owner's name;
                // otherwise fall back to the signed-in user's display name.
                final username = widget.ownerUsername ?? snapshot.data ?? 'AGENT';

                // ── Equipped cosmetics ──────────────────────────────────────
                final frameId    = _cosmetics['frame'];
                final titlebarId = _cosmetics['titlebar'];

                final equippedFrame = frameId != null
                    ? ShopCatalogue.frames.where((f) => f.id == frameId).firstOrNull
                    : null;
                final equippedTitlebar = titlebarId != null
                    ? ShopCatalogue.titlebars.where((t) => t.id == titlebarId).firstOrNull
                    : null;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Titlebar banner ────────────────────────────────────
                    if (equippedTitlebar != null)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 400),
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: equippedTitlebar.frameColors ?? [const Color(0xFF1A1A2E), const Color(0xFF0D0D1A)],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Text(
                          equippedTitlebar.titlebarLabel ?? equippedTitlebar.name,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),

                    // ── Avatar + callsign row ──────────────────────────────
                    Row(
                      children: [
                        // Avatar with optional frame
                        _isRemotePlayer
                          ? _buildFramedAvatar(
                              child: Container(
                                width: 80, height: 80,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    colors: [priColor.withValues(alpha: 0.4), priColor.withValues(alpha: 0.1)],
                                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                                  ),
                                ),
                                child: Center(child: Icon(Icons.person, color: priColor, size: 40)),
                              ),
                              frame: equippedFrame,
                              priColor: priColor,
                            )
                          : ValueListenableBuilder<String?>(
                              valueListenable: SettingsService().profileImagePath,
                              builder: (context, localPath, _) {
                                final googlePhotoUrl = _authService.currentUser?.photoURL;
                                Widget imageWidget;
                                if (localPath != null && localPath.isNotEmpty && !kIsWeb) {
                                  imageWidget = Image.file(File(localPath), fit: BoxFit.cover);
                                } else if (googlePhotoUrl != null && googlePhotoUrl.isNotEmpty) {
                                  imageWidget = Image.network(googlePhotoUrl, fit: BoxFit.cover);
                                } else {
                                  imageWidget = Icon(Icons.account_circle, color: secColor, size: 60);
                                }
                                return _buildFramedAvatar(
                                  child: Container(
                                    width: 80, height: 80,
                                    child: ClipOval(child: imageWidget),
                                  ),
                                  frame: equippedFrame,
                                  priColor: priColor,
                                );
                              },
                            ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('CALLSIGN', style: TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 2)),
                              Text(username.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 2)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),

            // ── Rank banner (tappable) ─────────────────────────────────────
            GestureDetector(
              onTap: () => _showRankSheet(currentLevel),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [priColor.withValues(alpha: 0.3), Colors.transparent],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(color: priColor.withValues(alpha: 0.5)),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: priColor.withValues(alpha: 0.2), shape: BoxShape.circle),
                      child: Icon(Icons.shield, color: priColor, size: 32),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('LEVEL $currentLevel', style: const TextStyle(fontSize: 14, color: Colors.white70, fontWeight: FontWeight.bold, letterSpacing: 2)),
                          Text(rankTitle, style: TextStyle(fontSize: 24, color: secColor, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                        ],
                      ),
                    ),
                    Column(
                      children: [
                        Icon(Icons.chevron_right, color: Colors.white38),
                        Text('ALL RANKS', style: TextStyle(color: Colors.white38, fontSize: 9, letterSpacing: 1)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // ── Stats grid ─────────────────────────────────────────────────
            Row(children: [
              _buildStatCard('TOTAL AREA',   _formatArea(totalArea),      Icons.map_outlined,               secColor),
              _buildStatCard('AVG CAPTURE',  _formatArea(avgJourneyArea), Icons.pie_chart_outline,           Colors.orangeAccent),
            ]),
            Row(children: [
              _buildStatCard('ZONES OWNED',  '$zonesCount',         Icons.flag_outlined,               Colors.greenAccent),
              _buildStatCard('TACTICAL AGG.','${aggressiveness.toInt()}%', Icons.local_fire_department_outlined, Colors.redAccent),
            ]),
            Row(children: [
              _buildStatCard('MAX CAPTURE',  _formatArea(maxJourneyArea), Icons.star_border,                 Colors.purpleAccent),
              _buildStatCard('DAYS ACTIVE',  '$daysActive',               Icons.calendar_today,              Colors.blueAccent),
            ]),
            const SizedBox(height: 24),

            // Global Networks placeholder
            Text('GLOBAL NETWORKS', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontWeight: FontWeight.bold, letterSpacing: 2, fontSize: 12)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(children: [
                    const Text('GLOBAL RANK', style: TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 1.5)),
                    const SizedBox(height: 8),
                    Text('UNRANKED', style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontWeight: FontWeight.bold, fontSize: 16)),
                  ]),
                  Container(width: 1, height: 40, color: Colors.white12),
                  Column(children: [
                    const Text('REGIONAL RANK', style: TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 1.5)),
                    const SizedBox(height: 8),
                    Text('UNRANKED', style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontWeight: FontWeight.bold, fontSize: 16)),
                  ]),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Territorial presence
            Text('TERRITORIAL PRESENCE', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontWeight: FontWeight.bold, letterSpacing: 2, fontSize: 12)),
            const SizedBox(height: 12),
            if (_isRemotePlayer)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.lock_outline, color: Colors.white30, size: 20),
                    const SizedBox(width: 12),
                    Text('Territory details are private', style: TextStyle(color: Colors.white30, fontSize: 13)),
                  ],
                ),
              )
            else if (sortedRegions.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Center(child: Text('NO TERRITORIES DETECTED', style: TextStyle(color: Colors.white.withValues(alpha: 0.3), letterSpacing: 2))),
              )
            else
              ...sortedRegions.map((entry) {
                final region     = entry.key;
                final area       = entry.value;
                final percentage = totalArea > 0 ? (area / totalArea) * 100 : 0.0;
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(region.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1), overflow: TextOverflow.ellipsis),
                          ),
                          Text('${percentage.toStringAsFixed(1)}%', style: TextStyle(color: secColor, fontWeight: FontWeight.bold, fontSize: 16)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(value: percentage / 100, backgroundColor: Colors.white10, color: secColor, minHeight: 6),
                      ),
                      const SizedBox(height: 8),
                      Text(_formatArea(area), style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ),
                );
              }),
            const SizedBox(height: 32),

            // Recent activity
            Text('RECENT ACTIVITY LOG', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontWeight: FontWeight.bold, letterSpacing: 2, fontSize: 12)),
            const SizedBox(height: 12),
            if (_isRemotePlayer)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.lock_outline, color: Colors.white30, size: 20),
                    const SizedBox(width: 12),
                    Text('Activity log is private', style: TextStyle(color: Colors.white30, fontSize: 13)),
                  ],
                ),
              )
            else if (_events.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Center(child: Text('NO RECENT ACTIVITY', style: TextStyle(color: Colors.white.withValues(alpha: 0.3), letterSpacing: 2))),
              )
            else
              ...(_events.take(5).map((e) {
                final dateStr = '${e.timestamp.year}-${e.timestamp.month.toString().padLeft(2, '0')}-${e.timestamp.day.toString().padLeft(2, '0')}';
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: e.tierColor.withValues(alpha: 0.5), width: 1.5),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.add_location_alt, color: e.tierColor, size: 20),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(e.regionName ?? 'UNKNOWN SECTOR', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            Text(dateStr, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 10)),
                          ],
                        ),
                      ),
                      Text('+${_formatArea(e.area)}', style: TextStyle(color: e.tierColor, fontWeight: FontWeight.bold)),
                    ],
                  ),
                );
              })),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
