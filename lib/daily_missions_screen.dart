import 'package:flutter/material.dart';
import 'models/daily_mission.dart';
import 'services/progression_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DailyMissionsScreen — shown as a full screen or bottom sheet
// ─────────────────────────────────────────────────────────────────────────────
class DailyMissionsScreen extends StatefulWidget {
  const DailyMissionsScreen({super.key});

  @override
  State<DailyMissionsScreen> createState() => _DailyMissionsScreenState();
}

class _DailyMissionsScreenState extends State<DailyMissionsScreen>
    with TickerProviderStateMixin {
  final ProgressionService _prog = ProgressionService.instance;

  List<DailyMission> _missions = [];
  int _coins = 0;
  bool _isLoading = true;

  // Coin reward animation
  late AnimationController _coinPopController;

  @override
  void initState() {
    super.initState();
    _coinPopController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _loadData();
  }

  @override
  void dispose() {
    _coinPopController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final missions = await _prog.getDailyMissions();
    final coins    = await _prog.getCoins();
    if (!mounted) return;
    setState(() {
      _missions  = missions;
      _coins     = coins;
      _isLoading = false;
    });
  }

  Future<void> _claimMission(DailyMission mission) async {
    final awarded = await _prog.claimMission(mission.id);
    if (awarded > 0) {
      _coinPopController.forward(from: 0);
      await _loadData();
      if (mounted) {
        _showCoinToast('+$awarded coins earned!');
      }
    }
  }

  void _showCoinToast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(
        children: [
          const Text('🪙', style: TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Text(message, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
      backgroundColor: Colors.amber.shade800,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }

  String _timeUntilReset() {
    final now   = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final diff  = tomorrow.difference(now);
    final h     = diff.inHours;
    final m     = diff.inMinutes % 60;
    return '${h}h ${m}m';
  }

  IconData _missionIcon(MissionType type) {
    switch (type) {
      case MissionType.walk:      return Icons.directions_walk;
      case MissionType.capture:   return Icons.flag_outlined;
      case MissionType.territory: return Icons.add_location_alt_outlined;
      case MissionType.visit:     return Icons.explore_outlined;
    }
  }

  Color _missionColor(MissionType type) {
    switch (type) {
      case MissionType.walk:      return const Color(0xFF00E5FF);
      case MissionType.capture:   return const Color(0xFF6C63FF);
      case MissionType.territory: return const Color(0xFF00FF88);
      case MissionType.visit:     return const Color(0xFFFFD700);
    }
  }

  @override
  Widget build(BuildContext context) {
    final secColor = Theme.of(context).colorScheme.secondary;

    return Scaffold(
      backgroundColor: const Color(0xFF080810),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E0E1A),
        elevation: 0,
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('📋', style: TextStyle(fontSize: 18)),
              SizedBox(width: 8),
              Text('DAILY MISSIONS', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2)),
            ],
          ),
        ),
        centerTitle: true,
        actions: [
          // Coin balance
          Container(
            margin: const EdgeInsets.only(right: 16, top: 10, bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                Colors.amber.withValues(alpha: 0.2),
                Colors.amber.withValues(alpha: 0.05),
              ]),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🪙', style: TextStyle(fontSize: 14)),
                const SizedBox(width: 4),
                Text('$_coins', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // ── Reset countdown ────────────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.schedule, color: Colors.white38, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Missions reset in ${_timeUntilReset()}',
                            style: const TextStyle(color: Colors.white54, fontSize: 13),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: secColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: secColor.withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            '${_missions.where((m) => m.claimed).length}/${_missions.length} DONE',
                            style: TextStyle(color: secColor, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── How to earn coins hint ─────────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(14),
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        Colors.amber.withValues(alpha: 0.08),
                        Colors.transparent,
                      ]),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amber.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      children: [
                        const Text('🪙', style: TextStyle(fontSize: 20)),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Complete missions to earn coins.\nSpend them in the Gear Shop!',
                            style: TextStyle(color: Colors.white60, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── Mission cards ──────────────────────────────────────────────
                  ..._missions.map((mission) => Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _MissionCard(
                      mission: mission,
                      missionColor: _missionColor(mission.type),
                      missionIcon: _missionIcon(mission.type),
                      onClaim: () => _claimMission(mission),
                    ),
                  )),
                ],
              ),
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Mission card widget
// ─────────────────────────────────────────────────────────────────────────────
class _MissionCard extends StatelessWidget {
  final DailyMission mission;
  final Color missionColor;
  final IconData missionIcon;
  final VoidCallback onClaim;

  const _MissionCard({
    required this.mission,
    required this.missionColor,
    required this.missionIcon,
    required this.onClaim,
  });

  @override
  Widget build(BuildContext context) {
    final isDone    = mission.completed;
    final isClaimed = mission.claimed;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isClaimed
            ? Colors.white.withValues(alpha: 0.02)
            : isDone
                ? missionColor.withValues(alpha: 0.05)
                : const Color(0xFF0E0E1A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isClaimed
              ? Colors.white10
              : isDone
                  ? missionColor.withValues(alpha: 0.5)
                  : Colors.white12,
          width: isDone && !isClaimed ? 1.5 : 1,
        ),
        boxShadow: isDone && !isClaimed
            ? [BoxShadow(color: missionColor.withValues(alpha: 0.12), blurRadius: 16)]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: missionColor.withValues(alpha: isClaimed ? 0.05 : 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(missionIcon, color: isClaimed ? Colors.white24 : missionColor, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mission.title,
                      style: TextStyle(
                        color: isClaimed ? Colors.white38 : Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      mission.description,
                      style: TextStyle(
                        color: isClaimed ? Colors.white24 : Colors.white54,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              // Coin reward badge
              Column(
                children: [
                  const Text('🪙', style: TextStyle(fontSize: 18)),
                  Text(
                    '+${mission.coinReward}',
                    style: TextStyle(
                      color: isClaimed ? Colors.white24 : Colors.amber,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: mission.progressFraction,
              backgroundColor: Colors.white10,
              valueColor: AlwaysStoppedAnimation<Color>(
                isClaimed ? Colors.white24 : missionColor,
              ),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 8),

          // Progress label + claim button
          Row(
            children: [
              Text(
                mission.progressLabel,
                style: TextStyle(
                  color: isClaimed ? Colors.white24 : Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (isClaimed)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check, color: Colors.white24, size: 12),
                      SizedBox(width: 4),
                      Text('CLAIMED', style: TextStyle(color: Colors.white24, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                    ],
                  ),
                )
              else if (isDone)
                GestureDetector(
                  onTap: onClaim,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        Colors.amber.shade600,
                        Colors.amber.shade400,
                      ]),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [BoxShadow(color: Colors.amber.withValues(alpha: 0.3), blurRadius: 10)],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('🪙', style: TextStyle(fontSize: 12)),
                        SizedBox(width: 4),
                        Text('CLAIM', style: TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
                      ],
                    ),
                  ),
                )
              else
                Text(
                  '${(mission.progressFraction * 100).toInt()}%',
                  style: TextStyle(
                    color: missionColor.withValues(alpha: 0.7),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
