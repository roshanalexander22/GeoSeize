import 'dart:ui';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'models/capture_event.dart';
import 'services/storage_service.dart';
import 'utils/level_system.dart';
import 'services/settings_service.dart';
import 'services/auth_service.dart';

class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  final StorageService _storageService = StorageService();
  final AuthService _authService = AuthService();
  List<CaptureEvent> _events = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final events = await _storageService.loadEvents();
    events.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    setState(() {
      _events = events;
      _isLoading = false;
    });
  }

  String _formatArea(double sqMeters) {
    bool useMetric = SettingsService().useMetric.value;
    if (useMetric) {
      if (sqMeters >= 1000000) return '${(sqMeters / 1000000).toStringAsFixed(2)} km²';
      return '${sqMeters.toStringAsFixed(1)} m²';
    } else {
      double sqFeet = sqMeters * 10.7639;
      if (sqFeet >= 27878400) return '${(sqFeet / 27878400).toStringAsFixed(2)} mi²';
      return '${sqFeet.toStringAsFixed(1)} ft²';
    }
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.5),
          border: Border.all(color: color.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.05),
              blurRadius: 10,
              spreadRadius: 1,
            )
          ]
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final totalArea = _events.fold(0.0, (sum, e) => sum + e.area);
    final avgArea = _events.isEmpty ? 0.0 : totalArea / _events.length;
    final int currentLevel = LevelSystem.getLevel(totalArea);
    final String rankTitle = LevelSystem.getRankTitle(currentLevel);

    // Calculate Aggressiveness (e.g. 5 captures in last 7 days = 100%)
    final now = DateTime.now();
    final recentCaptures = _events.where((e) => now.difference(e.timestamp).inDays <= 7).length;
    final double aggressiveness = _events.isEmpty ? 0 : (recentCaptures / 5.0).clamp(0.0, 1.0) * 100;

    final double maxArea = _events.isEmpty ? 0.0 : _events.map((e) => e.area).reduce((a, b) => a > b ? a : b);
    final int daysActive = _events.isEmpty ? 0 : now.difference(_events.map((e) => e.timestamp).reduce((a, b) => a.isBefore(b) ? a : b)).inDays + 1;

    // Calculate Regional Breakdown
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
            // Profile & Username Header
            FutureBuilder<String?>(
              future: _authService.getUsername(_authService.currentUser?.uid ?? ''),
              builder: (context, snapshot) {
                final username = snapshot.data ?? 'AGENT';
                return Row(
                  children: [
                    ValueListenableBuilder<String?>(
                      valueListenable: SettingsService().profileImagePath,
                      builder: (context, localPath, _) {
                        final googlePhotoUrl = _authService.currentUser?.photoURL;
                        Widget imageWidget;
                        if (localPath != null && localPath.isNotEmpty) {
                          imageWidget = Image.file(File(localPath), fit: BoxFit.cover);
                        } else if (googlePhotoUrl != null && googlePhotoUrl.isNotEmpty) {
                          imageWidget = Image.network(googlePhotoUrl, fit: BoxFit.cover);
                        } else {
                          imageWidget = Icon(Icons.account_circle, color: secColor, size: 60);
                        }
                        return Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: priColor, width: 2),
                            boxShadow: [
                              BoxShadow(color: priColor.withValues(alpha: 0.3), blurRadius: 15, spreadRadius: 2),
                            ],
                          ),
                          child: ClipOval(child: imageWidget),
                        );
                      }
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
                );
              }
            ),
            const SizedBox(height: 24),

            // Rank Banner
            Container(
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
                    decoration: BoxDecoration(
                      color: priColor.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.shield, color: priColor, size: 32),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('LEVEL $currentLevel', style: const TextStyle(fontSize: 14, color: Colors.white70, fontWeight: FontWeight.bold, letterSpacing: 2)),
                      Text(rankTitle, style: TextStyle(fontSize: 24, color: secColor, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            // Primary Stats Grid
            Row(
              children: [
                _buildStatCard('TOTAL AREA', _formatArea(totalArea), Icons.map_outlined, secColor),
                _buildStatCard('AVG CAPTURE', _formatArea(avgArea), Icons.pie_chart_outline, Colors.orangeAccent),
              ],
            ),
            Row(
              children: [
                _buildStatCard('ZONES OWNED', '${_events.length}', Icons.flag_outlined, Colors.greenAccent),
                _buildStatCard('TACTICAL AGG.', '${aggressiveness.toInt()}%', Icons.local_fire_department_outlined, Colors.redAccent),
              ],
            ),
            Row(
              children: [
                _buildStatCard('MAX CAPTURE', _formatArea(maxArea), Icons.star_border, Colors.purpleAccent),
                _buildStatCard('DAYS ACTIVE', '$daysActive', Icons.calendar_today, Colors.blueAccent),
              ],
            ),
            const SizedBox(height: 24),

            // Multiplayer Placeholders
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
                  Column(
                    children: [
                      const Text('GLOBAL RANK', style: TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 1.5)),
                      const SizedBox(height: 8),
                      Text('UNRANKED', style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                  Container(width: 1, height: 40, color: Colors.white12),
                  Column(
                    children: [
                      const Text('REGIONAL RANK', style: TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 1.5)),
                      const SizedBox(height: 8),
                      Text('UNRANKED', style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 32),
            Text('TERRITORIAL PRESENCE', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontWeight: FontWeight.bold, letterSpacing: 2, fontSize: 12)),
            const SizedBox(height: 12),
            
            if (sortedRegions.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Center(
                  child: Text('NO TERRITORIES DETECTED', style: TextStyle(color: Colors.white.withValues(alpha: 0.3), letterSpacing: 2)),
                ),
              )
            else
              ...sortedRegions.map((entry) {
                final region = entry.key;
                final area = entry.value;
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
                            child: Text(
                              region.toUpperCase(),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '${percentage.toStringAsFixed(1)}%',
                            style: TextStyle(color: secColor, fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: percentage / 100,
                          backgroundColor: Colors.white10,
                          color: secColor,
                          minHeight: 6,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _formatArea(area),
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                );
              }),
            const SizedBox(height: 32),
            
            Text('RECENT ACTIVITY LOG', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontWeight: FontWeight.bold, letterSpacing: 2, fontSize: 12)),
            const SizedBox(height: 12),
            
            if (_events.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Center(
                  child: Text('NO RECENT ACTIVITY', style: TextStyle(color: Colors.white.withValues(alpha: 0.3), letterSpacing: 2)),
                ),
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
