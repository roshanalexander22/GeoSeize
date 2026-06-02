import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'models/capture_event.dart';
import 'services/storage_service.dart';
import 'utils/level_system.dart';

class ScoreboardScreen extends StatefulWidget {
  const ScoreboardScreen({super.key});

  @override
  State<ScoreboardScreen> createState() => _ScoreboardScreenState();
}

class _ScoreboardScreenState extends State<ScoreboardScreen> with SingleTickerProviderStateMixin {
  final StorageService _storageService = StorageService();
  List<CaptureEvent> _allEvents = [];
  bool _isLoading = true;
  
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadEvents();
  }

  Future<void> _loadEvents() async {
    final events = await _storageService.loadEvents();
    // Sort descending by time
    events.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    setState(() {
      _allEvents = events;
      _isLoading = false;
    });
  }

  List<CaptureEvent> _getEventsForTab(int tabIndex) {
    final now = DateTime.now();
    if (tabIndex == 0) { // Today
      return _allEvents.where((e) => 
        e.timestamp.year == now.year && 
        e.timestamp.month == now.month && 
        e.timestamp.day == now.day
      ).toList();
    } else if (tabIndex == 1) { // This Week
      final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
      return _allEvents.where((e) => e.timestamp.isAfter(startOfWeek)).toList();
    }
    // All Time
    return _allEvents;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    Color _textColor = Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white;

    final double totalAreaAllTime = _allEvents.fold(0.0, (sum, e) => sum + e.area);
    final int currentLevel = LevelSystem.getLevel(totalAreaAllTime);
    final String rankTitle = LevelSystem.getRankTitle(currentLevel);
    final double levelProgress = LevelSystem.getProgressToNextLevel(totalAreaAllTime);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('COMMAND CENTER', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2)),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Theme.of(context).colorScheme.secondary,
          labelColor: Theme.of(context).colorScheme.secondary,
          unselectedLabelColor: _textColor.withValues(alpha: 0.54),
          tabs: const [
            Tab(text: 'TODAY'),
            Tab(text: 'THIS WEEK'),
            Tab(text: 'ALL TIME'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Player Progression Card
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                  Colors.transparent,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('LVL $currentLevel', style: TextStyle(color: _textColor, fontSize: 24, fontWeight: FontWeight.w900)),
                        Text(rankTitle, style: TextStyle(color: Theme.of(context).colorScheme.secondary, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                      ],
                    ),
                    Icon(Icons.shield, color: _textColor.withValues(alpha: 0.7), size: 40),
                  ],
                ),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: levelProgress,
                    backgroundColor: _textColor.withValues(alpha: 0.1),
                    color: Theme.of(context).colorScheme.primary,
                    minHeight: 8,
                  ),
                ),
                const SizedBox(height: 8),
                Text('${(levelProgress * 100).toInt()}% TO NEXT RANK', style: TextStyle(color: _textColor.withValues(alpha: 0.54), fontSize: 10, letterSpacing: 1)),
              ],
            ),
          ),
          
          // Tab Views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildTabContent(0),
                _buildTabContent(1),
                _buildTabContent(2),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabContent(int tabIndex) {
    final events = _getEventsForTab(tabIndex);
    
    if (events.isEmpty) {
      Color textColor = Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white;
      return Center(
        child: Text('NO TERRITORIES CAPTURED\nIN THIS TIMEFRAME', textAlign: TextAlign.center, style: TextStyle(color: textColor.withValues(alpha: 0.3), letterSpacing: 2)),
      );
    }

    final double totalArea = events.fold(0.0, (sum, e) => sum + e.area);
    final double maxArea = events.map((e) => e.area).reduce((a, b) => a > b ? a : b);

    return Column(
      children: [
        // Summary Stats for this timeframe
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _StatWidget(label: 'AREA ($tabIndex)', value: '${totalArea.toStringAsFixed(1)} m²'),
              _StatWidget(label: 'ZONES', value: '${events.length}'),
              _StatWidget(label: 'BEST', value: '${maxArea.toStringAsFixed(1)} m²'),
            ],
          ),
        ),
        Divider(color: Theme.of(context).textTheme.bodyLarge?.color?.withValues(alpha: 0.1) ?? Colors.white10, height: 32),
        // Timeline List
        Expanded(
          child: ListView.builder(
            itemCount: events.length,
            itemBuilder: (context, index) {
              final event = events[index];
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: Theme.of(context).textTheme.bodyLarge?.color?.withValues(alpha: 0.05) ?? Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: event.tierColor.withValues(alpha: 0.3)),
                ),
                child: ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: event.tierColor.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.map, color: event.tierColor),
                  ),
                  title: Text('${event.area.toStringAsFixed(1)} m²', style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color, fontWeight: FontWeight.bold, fontSize: 18)),
                  subtitle: Text(DateFormat('MMM d, h:mm a').format(event.timestamp), style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color?.withValues(alpha: 0.54))),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: event.tierColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: event.tierColor),
                    ),
                    child: Text(event.tierName, style: TextStyle(color: event.tierColor, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _StatWidget extends StatelessWidget {
  final String label;
  final String value;

  const _StatWidget({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    Color textColor = Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white;
    return Column(
      children: [
        Text(value, style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(label.replaceAll(RegExp(r'\(\d\)'), ''), style: TextStyle(color: textColor.withValues(alpha: 0.3), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
      ],
    );
  }
}
