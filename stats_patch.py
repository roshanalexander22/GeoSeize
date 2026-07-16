"""Patch statistics_screen.dart to load other players' stats from Firestore."""
import re

with open('lib/statistics_screen.dart', 'r', encoding='utf-8') as f:
    src = f.read()

# ── 1. Add _isRemotePlayer and _remoteStats fields after _isLoading ───────────
src = src.replace(
    '  bool               _isLoading    = true;\n',
    '  bool               _isLoading    = true;\n'
    '  bool               _isRemotePlayer = false;\n'
    '  // Firestore summary stats for another player (null when viewing own stats)\n'
    '  Map<String, dynamic>? _remoteStats;\n',
    1
)

# ── 2. Replace _loadData() to branch on ownerUsername ─────────────────────────
old_load = '''  Future<void> _loadData() async {
    final events  = await _storageService.loadEvents();
    final journeys = await _storageService.loadJourneyAreas();
    events.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    setState(() {
      _events       = events;
      _journeyAreas = journeys;
      _isLoading    = false;
    });
  }'''

new_load = '''  Future<void> _loadData() async {
    if (widget.ownerUsername != null) {
      // ── Remote player: load from Firestore ─────────────────────────────────
      _isRemotePlayer = true;
      final data = await _authService.getUserStatsByUsername(widget.ownerUsername!);
      if (!mounted) return;
      setState(() {
        _remoteStats = data?['stats'] as Map<String, dynamic>?;
        _isLoading   = false;
      });
    } else {
      // ── Own player: load from local storage ─────────────────────────────────
      _isRemotePlayer = false;
      final events   = await _storageService.loadEvents();
      final journeys = await _storageService.loadJourneyAreas();
      events.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      if (!mounted) return;
      setState(() {
        _events       = events;
        _journeyAreas = journeys;
        _isLoading    = false;
      });
    }
  }'''

src = src.replace(old_load, new_load, 1)

# ── 3. Replace computed stats block in build() ────────────────────────────────
old_stats = '''    final totalArea     = _events.fold(0.0, (sum, e) => sum + e.area);
    final int currentLevel  = LevelSystem.getLevel(totalArea);
    final String rankTitle  = LevelSystem.getRankTitle(currentLevel);

    // Per-journey stats (uses journey history, not zone sizes)
    final double maxJourneyArea = _journeyAreas.isEmpty ? 0.0 : _journeyAreas.reduce((a, b) => a > b ? a : b);
    final double avgJourneyArea = _journeyAreas.isEmpty ? 0.0 : totalArea / _journeyAreas.length;

    final now = DateTime.now();
    final recentCaptures = _events.where((e) => now.difference(e.timestamp).inDays <= 7).length;
    final double aggressiveness = _events.isEmpty ? 0 : (recentCaptures / 5.0).clamp(0.0, 1.0) * 100;
    final int daysActive = _events.isEmpty
        ? 0
        : now.difference(_events.map((e) => e.timestamp).reduce((a, b) => a.isBefore(b) ? a : b)).inDays + 1;

    final regionAreas = <String, double>{};
    for (var e in _events) {
      final region = e.regionName ?? 'UNKNOWN SECTOR';
      regionAreas[region] = (regionAreas[region] ?? 0) + e.area;
    }
    final sortedRegions = regionAreas.entries.toList()..sort((a, b) => b.value.compareTo(a.value));'''

new_stats = '''    // ── Determine data source: own (local) or another player (Firestore) ───────
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
    final sortedRegions = regionAreas.entries.toList()..sort((a, b) => b.value.compareTo(a.value));'''

src = src.replace(old_stats, new_stats, 1)

# ── 4. Update ZONES OWNED stat card to use zonesCount ────────────────────────
src = src.replace(
    "_buildStatCard('ZONES OWNED',  '${_events.length}'",
    "_buildStatCard('ZONES OWNED',  '$zonesCount'",
    1
)

# ── 5. Update profile header: show generic avatar for remote players ──────────
old_profile_pic = '''            ValueListenableBuilder<String?>(
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
                        return Container(
                          width: 80, height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: priColor, width: 2),
                            boxShadow: [BoxShadow(color: priColor.withValues(alpha: 0.3), blurRadius: 15, spreadRadius: 2)],
                          ),
                          child: ClipOval(child: imageWidget),
                        );
                      },
                    ),'''

new_profile_pic = '''            _isRemotePlayer
                      // For remote players we don't have their photo — show a
                      // generic avatar with their initial
                      ? Container(
                          width: 80, height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: priColor, width: 2),
                            boxShadow: [BoxShadow(color: priColor.withValues(alpha: 0.3), blurRadius: 15, spreadRadius: 2)],
                            gradient: LinearGradient(
                              colors: [priColor.withValues(alpha: 0.4), priColor.withValues(alpha: 0.1)],
                              begin: Alignment.topLeft, end: Alignment.bottomRight,
                            ),
                          ),
                          child: Center(child: Icon(Icons.person, color: priColor, size: 40)),
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
                            return Container(
                              width: 80, height: 80,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: priColor, width: 2),
                                boxShadow: [BoxShadow(color: priColor.withValues(alpha: 0.3), blurRadius: 15, spreadRadius: 2)],
                              ),
                              child: ClipOval(child: imageWidget),
                            );
                          },
                        ),'''

src = src.replace(old_profile_pic, new_profile_pic, 1)

# ── 6. Replace territorial presence section with remote-aware version ──────────
old_territory = '''            // Territorial presence
            Text('TERRITORIAL PRESENCE', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontWeight: FontWeight.bold, letterSpacing: 2, fontSize: 12)),
            const SizedBox(height: 12),
            if (sortedRegions.isEmpty)
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
              }),'''

new_territory = '''            // Territorial presence
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
              }),'''

src = src.replace(old_territory, new_territory, 1)

# ── 7. Replace activity log section with remote-aware version ─────────────────
old_activity = '''            // Recent activity
            Text('RECENT ACTIVITY LOG', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontWeight: FontWeight.bold, letterSpacing: 2, fontSize: 12)),
            const SizedBox(height: 12),
            if (_events.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Center(child: Text('NO RECENT ACTIVITY', style: TextStyle(color: Colors.white.withValues(alpha: 0.3), letterSpacing: 2))),
              )
            else
              ...(_events.take(5).map((e) {'''

new_activity = '''            // Recent activity
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
              ...(_events.take(5).map((e) {'''

src = src.replace(old_activity, new_activity, 1)

with open('lib/statistics_screen.dart', 'w', encoding='utf-8') as f:
    f.write(src)

# Verify patches
checks = [
    ('_isRemotePlayer field', '_isRemotePlayer = false;'),
    ('_remoteStats field', 'Map<String, dynamic>? _remoteStats;'),
    ('Remote _loadData branch', 'getUserStatsByUsername(widget.ownerUsername!)'),
    ('Unified totalArea', 'final double totalArea;'),
    ('zonesCount variable', 'final int    zonesCount;'),
    ('Remote profile pic', '_isRemotePlayer\n                      // For remote players'),
    ('Territory private', 'Territory details are private'),
    ('Activity private', 'Activity log is private'),
    ('zonesCount in stat card', "_buildStatCard('ZONES OWNED',  '$zonesCount'"),
]

all_ok = True
for name, pattern in checks:
    found = pattern in src
    status = 'OK' if found else 'MISSING'
    print(f'  [{status}] {name}')
    if not found:
        all_ok = False

print()
print('All checks passed!' if all_ok else 'Some checks FAILED - review above')
print(f'Total lines: {src.count(chr(10))}')
