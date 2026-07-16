import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'services/weather_service.dart';
import 'services/spotify_service.dart';
import 'services/progression_service.dart';
import 'shop_screen.dart';
import 'daily_missions_screen.dart';

class QuickMenuScreen extends StatefulWidget {
  final double initialLat;
  final double initialLng;

  const QuickMenuScreen({
    super.key,
    required this.initialLat,
    required this.initialLng,
  });

  @override
  State<QuickMenuScreen> createState() => _QuickMenuScreenState();
}

class _QuickMenuScreenState extends State<QuickMenuScreen> with TickerProviderStateMixin {
  late TabController _tabController;
  final WeatherService _weatherService = WeatherService();
  final SpotifyService _spotifyService = SpotifyService();
  final ProgressionService _prog = ProgressionService.instance;

  WeatherInfo? _weatherInfo;
  bool _isWeatherLoading = true;

  // Missions / Shop quick stats
  int _coins = 0;
  int _completedMissions = 0;
  int _totalMissions = 0;

  // Animation controller for weather animations (sun pulse, rain fall, cloud drift)
  late AnimationController _weatherAnimController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    
    _weatherAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();

    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _weatherAnimController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    // 1. Fetch Weather
    final weather = await _weatherService.fetchWeather(widget.initialLat, widget.initialLng);

    // 2. Load progression quick stats
    final coins    = await _prog.getCoins();
    final missions = await _prog.getDailyMissions();

    if (mounted) {
      setState(() {
        _weatherInfo        = weather;
        _isWeatherLoading   = false;
        _coins              = coins;
        _completedMissions  = missions.where((m) => m.completed).length;
        _totalMissions      = missions.length;
      });
    }
  }

  Color _getBackgroundColor1(double value, WeatherInfo? weather) {
    Color c0 = const Color(0xFF0A0E1A);
    if (weather != null) {
      if (weather.weatherCode == 0) {
        c0 = const Color(0xFF261D12);
      } else if (weather.weatherCode >= 1 && weather.weatherCode <= 3) {
        c0 = const Color(0xFF131A26);
      } else if (weather.weatherCode >= 51 && weather.weatherCode <= 82 || weather.weatherCode >= 95) {
        c0 = const Color(0xFF111E2B);
      }
    }

    const c1 = Color(0xFF031608); // Spotify green tint
    const c2 = Color(0xFF1E0710); // Fitness red/pink tint
    const c3 = Color(0xFF0A0520); // Shop purple tint

    if (value <= 1.0) {
      return Color.lerp(c0, c1, value) ?? c0;
    } else if (value <= 2.0) {
      return Color.lerp(c1, c2, value - 1.0) ?? c1;
    } else {
      return Color.lerp(c2, c3, (value - 2.0).clamp(0.0, 1.0)) ?? c2;
    }
  }

  Color _getBackgroundColor2(double value) {
    const c0 = Color(0xFF050508);
    const c1 = Color(0xFF020403);
    const c2 = Color(0xFF040203);
    const c3 = Color(0xFF020304);

    if (value <= 1.0) {
      return Color.lerp(c0, c1, value) ?? c0;
    } else if (value <= 2.0) {
      return Color.lerp(c1, c2, value - 1.0) ?? c1;
    } else {
      return Color.lerp(c2, c3, (value - 2.0).clamp(0.0, 1.0)) ?? c2;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secColor = theme.colorScheme.secondary;
    final priColor = theme.colorScheme.primary;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF13131A),
        elevation: 0,
        title: const Text(
          'DASHBOARD',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2, fontSize: 18),
        ),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: secColor,
          labelColor: secColor,
          unselectedLabelColor: Colors.white30,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 10, letterSpacing: 1.0),
          tabs: const [
            Tab(icon: Icon(Icons.cloud_outlined), text: 'WEATHER'),
            Tab(icon: Icon(Icons.headphones_outlined), text: 'SPOTIFY'),
            Tab(icon: Icon(Icons.directions_run_outlined), text: 'FITNESS'),
            Tab(icon: Icon(Icons.storefront_outlined), text: 'SHOP'),
          ],
        ),
      ),
      body: AnimatedBuilder(
        animation: _tabController.animation!,
        builder: (context, child) {
          final val = _tabController.animation!.value;
          final color1 = _getBackgroundColor1(val, _weatherInfo);
          final color2 = _getBackgroundColor2(val);
          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [color1, color2],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: child,
          );
        },
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildWeatherTab(secColor, priColor),
            _buildSpotifyBindingTab(secColor, priColor),
            _buildFitnessTab(secColor, priColor),
            _buildShopHubTab(secColor, priColor),
          ],
        ),
      ),
    );
  }

  // ── 1. WEATHER TAB ─────────────────────────────────────────────────────────
  Widget _buildWeatherTab(Color accent, Color primary) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 600),
      switchInCurve: Curves.easeIn,
      switchOutCurve: Curves.easeOut,
      child: _isWeatherLoading
          ? const Center(
              key: ValueKey('loading'),
              child: CircularProgressIndicator(),
            )
          : Stack(
              key: const ValueKey('content'),
              children: [
                // Creative Weather Canvas Background
                AnimatedBuilder(
                  animation: _weatherAnimController,
                  builder: (context, child) {
                    final weather = _weatherInfo ?? WeatherInfo.mock();
                    return CustomPaint(
                      painter: _WeatherBackgroundPainter(
                        code: weather.weatherCode,
                        progress: _weatherAnimController.value,
                      ),
                      child: Container(),
                    );
                  },
                ),

                // Dark dim overlay for readable typography
                Container(color: Colors.black.withValues(alpha: 0.2)),

                SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Main Weather Condition Display
                      Center(
                        child: Container(
                          margin: const EdgeInsets.only(top: 20, bottom: 20),
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 20,
                                spreadRadius: 2,
                              )
                            ],
                          ),
                          child: Column(
                            children: [
                              AnimatedWeatherGraphic(weatherCode: (_weatherInfo ?? WeatherInfo.mock()).weatherCode),
                              const SizedBox(height: 16),
                              Text(
                                (_weatherInfo ?? WeatherInfo.mock()).condition.toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: 2.0,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${(_weatherInfo ?? WeatherInfo.mock()).temperature.toStringAsFixed(1)}°C',
                                style: TextStyle(
                                  fontSize: 64,
                                  fontWeight: FontWeight.w900,
                                  color: accent,
                                  height: 1.1,
                                  shadows: [
                                    Shadow(color: accent.withValues(alpha: 0.4), blurRadius: 15),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Detail Statistics Cards Grid
                      const Text(
                        'ATMOSPHERIC LOGS',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2.0,
                        ),
                      ),
                      const SizedBox(height: 12),
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                        childAspectRatio: 1.5,
                        children: [
                          _buildWeatherDetailCard(
                            icon: Icons.umbrella_outlined,
                            label: 'RAIN CHANCE',
                            value: '${(_weatherInfo ?? WeatherInfo.mock()).rainProbability.toStringAsFixed(0)}%',
                            color: Colors.lightBlueAccent,
                          ),
                          _buildWeatherDetailCard(
                            icon: Icons.water_drop_outlined,
                            label: 'HUMIDITY',
                            value: '${(_weatherInfo ?? WeatherInfo.mock()).humidity}%',
                            color: Colors.cyanAccent,
                          ),
                          _buildWeatherDetailCard(
                            icon: Icons.air_outlined,
                            label: 'WIND SPEED',
                            value: '${(_weatherInfo ?? WeatherInfo.mock()).windSpeed.toStringAsFixed(1)} km/h',
                            color: Colors.tealAccent,
                          ),
                          _buildWeatherDetailCard(
                            icon: Icons.thermostat_outlined,
                            label: 'WEATHER INDEX',
                            value: (_weatherInfo ?? WeatherInfo.mock()).weatherCode <= 3 ? 'FAVORABLE' : 'STORM WARNING',
                            color: (_weatherInfo ?? WeatherInfo.mock()).weatherCode <= 3 ? Colors.greenAccent : Colors.redAccent,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildWeatherDetailCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(color: Colors.white30, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
          Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }


  // ── 2. SPOTIFY BINDING TAB ─────────────────────────────────────────────────
  Widget _buildSpotifyBindingTab(Color accent, Color primary) {
    final configured = _spotifyService.isConfigured;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hero section
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF1DB954).withValues(alpha: 0.15),
                  Colors.transparent,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFF1DB954).withValues(alpha: 0.3)),
            ),
            child: Column(
              children: [
                const Text('🎵', style: TextStyle(fontSize: 52)),
                const SizedBox(height: 12),
                const Text(
                  'SPOTIFY MUSIC',
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 3),
                ),
                const SizedBox(height: 8),
                Text(
                  'Bind your Spotify account to control music\nwhile you capture territory.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13),
                ),
                const SizedBox(height: 20),
                // Status badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: configured
                        ? const Color(0xFF1DB954).withValues(alpha: 0.2)
                        : Colors.orange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: configured
                          ? const Color(0xFF1DB954).withValues(alpha: 0.6)
                          : Colors.orange.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        configured ? Icons.check_circle : Icons.link_off,
                        color: configured ? const Color(0xFF1DB954) : Colors.orangeAccent,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        configured ? 'CONNECTED' : 'NOT CONNECTED',
                        style: TextStyle(
                          color: configured ? const Color(0xFF1DB954) : Colors.orangeAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // How it works
          const Text(
            'HOW IT WORKS',
            style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 2),
          ),
          const SizedBox(height: 12),
          _buildHowItWorksStep(1, 'Enter your Spotify Developer API credentials below.', Icons.key_outlined, accent),
          _buildHowItWorksStep(2, 'Your playlists become available in GeoSeize.', Icons.queue_music_outlined, accent),
          _buildHowItWorksStep(3, 'Control music via the floating player on the map screen.', Icons.open_in_new, accent),
          const SizedBox(height: 28),

          // Credentials section
          _buildSpotifyCredentialsSection(accent),
          const SizedBox(height: 24),

          // Floating player info
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.music_note, color: accent, size: 20),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Floating Music Bar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                      SizedBox(height: 3),
                      Text(
                        'Once connected, a draggable player appears on the map. Drag it off-screen to dismiss.',
                        style: TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHowItWorksStep(int step, String text, IconData icon, Color accent) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 30, height: 30,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.1),
              shape: BoxShape.circle,
              border: Border.all(color: accent.withValues(alpha: 0.3)),
            ),
            child: Center(child: Text('$step', style: TextStyle(color: accent, fontWeight: FontWeight.bold, fontSize: 13))),
          ),
          const SizedBox(width: 14),
          Icon(icon, color: Colors.white38, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(color: Colors.white60, fontSize: 12))),
        ],
      ),
    );
  }
  Widget _buildSpotifyCredentialsSection(Color accent) {
    final configured = _spotifyService.isConfigured;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.music_note, color: Color(0xFF1DB954), size: 20),
              const SizedBox(width: 12),
              const Text(
                'SPOTIFY API CREDENTIALS',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.0),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: configured ? Colors.green.withValues(alpha: 0.2) : Colors.orange.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  configured ? 'ACTIVE' : 'NOT SET',
                  style: TextStyle(
                    color: configured ? Colors.greenAccent : Colors.orangeAccent,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Enter your Spotify Web API credentials to link your account.',
            style: TextStyle(color: Colors.white30, fontSize: 11),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: Icon(configured ? Icons.link_off : Icons.link, size: 18),
              label: Text(
                configured ? 'Disconnect Spotify' : 'Connect Spotify',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: configured ? Colors.red.withValues(alpha: 0.8) : const Color(0xFF1DB954),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () {
                if (configured) {
                  _spotifyService.clearCredentials();
                  setState(() {});
                } else {
                  _showCredentialsDialog(accent);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showCredentialsDialog(Color accent) {
    final clientController = TextEditingController();
    final secretController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E28),
        title: const Text('Spotify Credentials', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: clientController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Client ID',
                labelStyle: TextStyle(color: Colors.white54),
              ),
            ),
            TextField(
              controller: secretController,
              style: const TextStyle(color: Colors.white),
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Client Secret',
                labelStyle: TextStyle(color: Colors.white54),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: accent),
            onPressed: () {
              if (clientController.text.isNotEmpty && secretController.text.isNotEmpty) {
                _spotifyService.saveCredentials(clientController.text.trim(), secretController.text.trim());
                Navigator.of(ctx).pop();
                _loadData();
              }
            },
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ── 4. SHOP HUB TAB ────────────────────────────────────────────────────────
  Widget _buildShopHubTab(Color accent, Color primary) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Coin balance hero card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.amber.withValues(alpha: 0.15), Colors.amber.withValues(alpha: 0.03)],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                const Text('🪙', style: TextStyle(fontSize: 44)),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('COIN BALANCE', style: TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(
                        '$_coins',
                        style: const TextStyle(color: Colors.amber, fontSize: 36, fontWeight: FontWeight.w900),
                      ),
                      Text(
                        'Earn more by completing daily missions',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Missions quick summary
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DailyMissionsScreen()),
              ).then((_) => _loadData());
            },
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: accent.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Text('📋', style: TextStyle(fontSize: 22)),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('DAILY MISSIONS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1)),
                        const SizedBox(height: 3),
                        Text(
                          '$_completedMissions / $_totalMissions missions complete',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12),
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: _totalMissions == 0 ? 0 : _completedMissions / _totalMissions,
                            backgroundColor: Colors.white10,
                            valueColor: AlwaysStoppedAnimation<Color>(accent),
                            minHeight: 5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(Icons.chevron_right, color: accent),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Gear Shop button
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ShopScreen()),
              ).then((_) => _loadData());
            },
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [const Color(0xFF6C63FF).withValues(alpha: 0.15), Colors.transparent],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFF6C63FF).withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6C63FF).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.storefront_outlined, color: Color(0xFF6C63FF), size: 24),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('GEAR SHOP', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1)),
                        SizedBox(height: 3),
                        Text(
                          'Buy zone colors, markers, frames & titlebars',
                          style: TextStyle(color: Colors.white38, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Icon(Icons.chevron_right, color: Color(0xFF6C63FF)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 28),

          // Shop category preview
          const Text(
            'SHOP CATEGORIES',
            style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 2),
          ),
          const SizedBox(height: 14),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            childAspectRatio: 2.4,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            children: [
              _buildCategoryChip('🎨 COLORS', '8 items', const Color(0xFF00E5FF)),
              _buildCategoryChip('📍 MARKERS', '7 items', const Color(0xFF6C63FF)),
              _buildCategoryChip('🔵 FRAMES', '6 items', const Color(0xFFFFD700)),
              _buildCategoryChip('🏷️ TITLEBARS', '6 items', const Color(0xFFFF4500)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChip(String label, String subtitle, Color color) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ShopScreen())).then((_) => _loadData()),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
            Text(subtitle, style: const TextStyle(color: Colors.white30, fontSize: 10)),
          ],
        ),
      ),
    );
  }
  // ── 3. FITNESS TAB ─────────────────────────────────────────────────────────
  Widget _buildFitnessTab(Color accent, Color primary) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Big Stat Display: speed
          Center(
            child: Container(
              width: 200, height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: accent.withValues(alpha: 0.15), width: 8),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('SPEED', style: TextStyle(color: Colors.white30, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                    const SizedBox(height: 4),
                    Text(
                      '0.0',
                      style: TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: accent, height: 1.0),
                    ),
                    const Text('km/h', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),

          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            childAspectRatio: 1.5,
            children: [
              _buildFitnessCard(Icons.directions_walk, 'STEP CADENCE', '0 spm', Colors.cyanAccent),
              _buildFitnessCard(Icons.local_fire_department, 'ACTIVE CALORIES', '0 kcal', Colors.deepOrangeAccent),
              _buildFitnessCard(Icons.timer_outlined, 'ACTIVE JOURNEY', '00:00', Colors.pinkAccent),
              _buildFitnessCard(Icons.social_distance_outlined, 'TOTAL AREA', '0.0 m²', Colors.greenAccent),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFitnessCard(IconData icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: color, size: 24),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: Colors.white30, fontSize: 10, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

}


// ── CUSTOM CANVAS WEATHER BACKDROP PAINTER ──────────────────────────────────
class _WeatherBackgroundPainter extends CustomPainter {
  final int code;
  final double progress;

  _WeatherBackgroundPainter({required this.code, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final double cx = size.width;
    final double cy = size.height;

    // ── 1. Sun/Clear Backdrop ───────────────────────────────────────────────
    if (code == 0) {
      // Amber/Red sunset glow
      final Paint sunPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.amber.withValues(alpha: 0.15 + 0.05 * math.sin(progress * 2 * math.pi)),
            Colors.transparent,
          ],
          center: const Alignment(0.6, -0.6),
          radius: 0.8,
        ).createShader(Rect.fromLTWH(0, 0, cx, cy));
      canvas.drawRect(Rect.fromLTWH(0, 0, cx, cy), sunPaint);
    }
    // ── 2. Clouds Drift ─────────────────────────────────────────────────────
    else if (code >= 1 && code <= 3) {
      final Paint cloudPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.03)
        ..style = PaintingStyle.fill;
      
      // Draw 3 soft clouds drifting across
      double x1 = (cx * progress) % (cx + 200) - 100;
      canvas.drawOval(Rect.fromLTWH(x1, cy * 0.15, 180, 80), cloudPaint);

      double x2 = (cx * (progress + 0.3)) % (cx + 200) - 100;
      canvas.drawOval(Rect.fromLTWH(x2, cy * 0.25, 220, 90), cloudPaint);
      
      double x3 = (cx * (progress + 0.6)) % (cx + 200) - 100;
      canvas.drawOval(Rect.fromLTWH(x3, cy * 0.35, 140, 60), cloudPaint);
    }
    // ── 3. Rain Falling / Thunderstorm ──────────────────────────────────────
    else if (code >= 51 && code <= 82 || code >= 95) {
      // Soft thunderstorm lightning flash
      if (code >= 95 && math.sin(progress * 12 * math.pi) > 0.96) {
        final Paint flashPaint = Paint()..color = Colors.white.withValues(alpha: 0.1);
        canvas.drawRect(Rect.fromLTWH(0, 0, cx, cy), flashPaint);
      }

      // Rain streaker custom paint
      final Paint rainPaint = Paint()
        ..color = Colors.lightBlueAccent.withValues(alpha: 0.2)
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round;

      // Draw 25 rain streaks based on offset progress
      final int rainCount = code >= 95 ? 40 : 20;
      for (int i = 0; i < rainCount; i++) {
        // Deterministic pseudo-random position
        double rx = (cx * (i * 0.07 + progress * 0.35)) % cx;
        double ry = (cy * (i * 0.13 + progress * 0.95)) % cy;
        canvas.drawLine(
          Offset(rx, ry),
          Offset(rx - 3, ry + 15),
          rainPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _WeatherBackgroundPainter oldDelegate) {
    return oldDelegate.code != code || oldDelegate.progress != progress;
  }
}

// ── CUSTOM ANIMATED GLASSMORPHIC WEATHER GRAPHIC WIDGET ──────────────────────
class AnimatedWeatherGraphic extends StatefulWidget {
  final int weatherCode;
  const AnimatedWeatherGraphic({super.key, required this.weatherCode});

  @override
  State<AnimatedWeatherGraphic> createState() => _AnimatedWeatherGraphicState();
}

class _AnimatedWeatherGraphicState extends State<AnimatedWeatherGraphic> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final code = widget.weatherCode;
    
    return SizedBox(
      width: 140,
      height: 140,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final t = _controller.value;
          
          if (code == 0) {
            return _buildSunny(t);
          } else if (code >= 1 && code <= 3) {
            return _buildCloudy(t);
          } else if (code == 45 || code == 48) {
            return _buildFoggy(t);
          } else if (code >= 51 && code <= 67 || code >= 80 && code <= 82) {
            return _buildRainy(t);
          } else if (code >= 71 && code <= 77 || code >= 85 && code <= 86) {
            return _buildSnowy(t);
          } else if (code >= 95) {
            return _buildThunderstorm(t);
          } else {
            return _buildCloudy(t);
          }
        },
      ),
    );
  }

  Widget _buildSunny(double t) {
    final rotationAngle = t * 2 * math.pi;
    final pulseScale = 1.0 + 0.08 * math.sin(t * 2 * math.pi);
    
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.amber.withValues(alpha: 0.15),
            boxShadow: [
              BoxShadow(
                color: Colors.amber.withValues(alpha: 0.3),
                blurRadius: 35,
                spreadRadius: 8,
              ),
            ],
          ),
        ),
        Transform.rotate(
          angle: rotationAngle,
          child: CustomPaint(
            size: const Size(110, 110),
            painter: _SunRaysPainter(),
          ),
        ),
        Transform.scale(
          scale: pulseScale,
          child: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                colors: [
                  Colors.amberAccent,
                  Colors.orange,
                ],
                center: Alignment(-0.2, -0.2),
                radius: 0.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.orange.withValues(alpha: 0.5),
                  blurRadius: 12,
                  spreadRadius: 1,
                )
              ]
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCloudy(double t) {
    final floatOffset = math.sin(t * 2 * math.pi) * 3.0;
    
    return Stack(
      alignment: Alignment.center,
      children: [
        Positioned(
          top: 25 + floatOffset * 0.5,
          left: 25,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                colors: [Colors.amberAccent, Colors.orange],
                center: Alignment(-0.2, -0.2),
                radius: 0.8,
              ),
              boxShadow: [
                BoxShadow(color: Colors.orange.withValues(alpha: 0.25), blurRadius: 8, spreadRadius: 1)
              ],
            ),
          ),
        ),
        Positioned(
          top: 40 + floatOffset,
          child: const _GlassCloud(
            width: 100,
            height: 54,
            color: Color(0xB2FFFFFF),
            borderColor: Color(0x66FFFFFF),
          ),
        ),
      ],
    );
  }

  Widget _buildFoggy(double t) {
    final offset1 = math.sin(t * 2 * math.pi) * 10.0;
    final offset2 = math.cos(t * 2 * math.pi) * 6.0;
    final offset3 = math.sin(t * 2 * math.pi + 1.0) * 8.0;
    
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 90,
          height: 90,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.blueGrey.withValues(alpha: 0.08),
          ),
        ),
        Positioned(
          top: 45,
          left: 15 + offset1,
          child: const _FogBand(width: 75, height: 5),
        ),
        Positioned(
          top: 58,
          left: 30 + offset2,
          child: const _FogBand(width: 80, height: 5),
        ),
        Positioned(
          top: 71,
          left: 22 + offset3,
          child: const _FogBand(width: 65, height: 5),
        ),
      ],
    );
  }

  Widget _buildRainy(double t) {
    final floatOffset = math.sin(t * 2 * math.pi) * 2.0;
    
    return Stack(
      alignment: Alignment.center,
      children: [
        Positioned(
          top: 25 + floatOffset,
          child: _GlassCloud(
            width: 90,
            height: 50,
            color: Colors.blueGrey.shade700.withValues(alpha: 0.5),
            borderColor: Colors.blueGrey.shade500.withValues(alpha: 0.3),
          ),
        ),
        ...List.generate(4, (index) {
          final dropProgress = (t + (index * 0.25)) % 1.0;
          final dropY = 60.0 + dropProgress * 40.0;
          final dropX = 35.0 + (index * 20.0);
          final opacity = (1.0 - dropProgress).clamp(0.0, 1.0);
          
          return Positioned(
            top: dropY,
            left: dropX,
            child: Opacity(
              opacity: opacity,
              child: Container(
                width: 2.5,
                height: 10,
                decoration: BoxDecoration(
                  color: Colors.lightBlueAccent,
                  borderRadius: BorderRadius.circular(1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.lightBlueAccent.withValues(alpha: 0.4),
                      blurRadius: 1.5,
                    )
                  ]
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildSnowy(double t) {
    final floatOffset = math.sin(t * 2 * math.pi) * 2.0;
    
    return Stack(
      alignment: Alignment.center,
      children: [
        Positioned(
          top: 25 + floatOffset,
          child: _GlassCloud(
            width: 90,
            height: 50,
            color: Colors.blueGrey.shade800.withValues(alpha: 0.4),
            borderColor: Colors.white.withValues(alpha: 0.2),
          ),
        ),
        ...List.generate(4, (index) {
          final snowProgress = (t + (index * 0.25)) % 1.0;
          final snowY = 60.0 + snowProgress * 40.0;
          final snowX = 32.0 + (index * 22.0);
          final opacity = (1.0 - snowProgress).clamp(0.0, 1.0);
          final rotation = snowProgress * 2 * math.pi;
          
          return Positioned(
            top: snowY,
            left: snowX,
            child: Opacity(
              opacity: opacity,
              child: Transform.rotate(
                angle: rotation,
                child: const Icon(
                  Icons.ac_unit,
                  size: 10,
                  color: Colors.white,
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildThunderstorm(double t) {
    final floatOffset = math.sin(t * 2 * math.pi) * 2.0;
    final showLightning = (t > 0.1 && t < 0.18) || (t > 0.4 && t < 0.48) || (t > 0.82 && t < 0.88);
    
    return Stack(
      alignment: Alignment.center,
      children: [
        AnimatedOpacity(
          opacity: showLightning ? 0.5 : 0.0,
          duration: Duration.zero,
          child: Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.purple.withValues(alpha: 0.2),
              boxShadow: [
                BoxShadow(
                  color: Colors.purpleAccent.withValues(alpha: 0.35),
                  blurRadius: 35,
                  spreadRadius: 4,
                )
              ]
            ),
          ),
        ),
        Positioned(
          top: 25 + floatOffset,
          child: _GlassCloud(
            width: 90,
            height: 50,
            color: const Color(0xFF231F33).withValues(alpha: 0.75),
            borderColor: Colors.purple.withValues(alpha: 0.25),
          ),
        ),
        if (showLightning)
          Positioned(
            top: 65,
            child: CustomPaint(
              size: const Size(26, 38),
              painter: _LightningPainter(),
            ),
          ),
        ...List.generate(3, (index) {
          final dropProgress = (t + (index * 0.33)) % 1.0;
          final dropY = 65.0 + dropProgress * 35.0;
          final dropX = 35.0 + (index * 25.0);
          final opacity = (1.0 - dropProgress).clamp(0.0, 1.0);
          
          return Positioned(
            top: dropY,
            left: dropX,
            child: Opacity(
              opacity: opacity,
              child: Container(
                width: 1.5,
                height: 8,
                decoration: BoxDecoration(
                  color: Colors.purpleAccent.shade100,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}

class _SunRaysPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = Colors.amber.withValues(alpha: 0.4)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    const rayCount = 8;
    const innerRadius = 28.0;
    const outerRadius = 40.0;

    for (int i = 0; i < rayCount; i++) {
      final angle = (i * 2 * math.pi) / rayCount;
      final dx = math.cos(angle);
      final dy = math.sin(angle);
      canvas.drawLine(
        center + Offset(dx * innerRadius, dy * innerRadius),
        center + Offset(dx * outerRadius, dy * outerRadius),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _LightningPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.yellowAccent
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(size.width * 0.7, 0)
      ..lineTo(size.width * 0.2, size.height * 0.45)
      ..lineTo(size.width * 0.55, size.height * 0.45)
      ..lineTo(size.width * 0.1, size.height)
      ..lineTo(size.width * 0.9, size.height * 0.5)
      ..lineTo(size.width * 0.55, size.height * 0.5)
      ..close();

    canvas.drawPath(path, Paint()
      ..color = Colors.yellow.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _GlassCloud extends StatelessWidget {
  final double width;
  final double height;
  final Color color;
  final Color borderColor;

  const _GlassCloud({
    required this.width,
    required this.height,
    required this.color,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(25),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 1.5, sigmaY: 1.5),
          child: Container(color: Colors.transparent),
        ),
      ),
    );
  }
}

class _FogBand extends StatelessWidget {
  final double width;
  final double height;
  const _FogBand({required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(height / 2),
        boxShadow: [
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.08),
            blurRadius: 3,
          )
        ],
      ),
    );
  }
}
