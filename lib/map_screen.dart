import 'dart:async';
import 'dart:math' show cos, log, pi, pow;
import 'dart:ui';
import 'dart:io' show File, Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'models/capture_event.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'services/storage_service.dart';
import 'utils/geo_calculator.dart';
import 'utils/capture_engine.dart';
import 'utils/level_system.dart';
import 'utils/rewards_system.dart';
import 'statistics_screen.dart';
import 'utils/page_transitions.dart';
import 'services/settings_service.dart';
import 'settings_screen.dart';
import 'services/auth_service.dart';


class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  final StorageService _storageService = StorageService();
  String _currentUsername = 'AGENT';
  
  final List<LatLng> _currentPath = [];
  List<CaptureEvent> _events = [];
  double _totalScore = 0.0;
  
  StreamSubscription<Position>? _positionStream;
  bool _isCapturing = false;
  LatLng? _currentLocation;
  
  bool _isPlanningMode = false;
  final List<LatLng> _plannedPath = [];
  double _plannedDistance = 0.0;
  double _plannedArea = 0.0;
  int _plannedTimeMinutes = 0;
  
  final Distance _distance = const Distance();

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Smooth marker movement
  AnimationController? _markerAnimController;
  Animation<double>? _animatedLat;
  Animation<double>? _animatedLng;
  LatLng? _displayLocation; // interpolated position used for rendering
  bool _followingUser = true; // whether the camera auto-follows the marker
  bool _sidebarExpanded = false; // whether the collapsible action buttons are shown

  // ── Journey capture tracking ──────────────────────────────────────────────
  DateTime? _captureStartTime;  // when the current capture session began
  double _captureDistance = 0.0; // metres walked this capture segment

  // ── Map camera tracking (for scale widget) ────────────────────────────────
  double _mapZoom = 16.5;
  double _mapLat  = 0.0;
  
  @override
  void initState() {
    super.initState();
    _loadData();
    _checkPermissionsAndGetLocation();
    // Snap zoom when user switches to satellite while over-zoomed
    SettingsService().mapStyle.addListener(_onMapStyleChanged);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.5).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Marker position animation — slides between GPS fixes instead of jumping
    _markerAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _markerAnimController!.addListener(() {
      if (!mounted) return;
      final lat = _animatedLat?.value;
      final lng = _animatedLng?.value;
      if (lat != null && lng != null) {
        final pos = LatLng(lat, lng);
        setState(() { _displayLocation = pos; });
        // Only move the camera if the user hasn't manually panned away
        if (_followingUser && _mapController.camera.zoom > 0) {
          _mapController.move(pos, _mapController.camera.zoom);
        }
      }
    });
  }

  Future<void> _loadData() async {
    final loadedEvents = await _storageService.loadEvents();
    final loadedScore = await _storageService.loadTotalArea();
    
    String tempUsername = 'AGENT';
    final user = AuthService().currentUser;
    if (user != null) {
      final name = await AuthService().getUsername(user.uid);
      if (name != null && name.isNotEmpty) {
        tempUsername = name;
      }
    }
    
    if (mounted) {
      setState(() {
        _events = loadedEvents;
        _totalScore = loadedScore;
        _currentUsername = tempUsername;
      });
    }
  }
  
  Future<void> _checkPermissionsAndGetLocation() async {
    try {
      // LoadingScreen has already guaranteed we have permissions and GPS is active!
      Position position = await Geolocator.getCurrentPosition();
      if (mounted) {
        final initialLoc = LatLng(position.latitude, position.longitude);
        setState(() {
          _currentLocation = initialLoc;
          _displayLocation = initialLoc; // show marker immediately
        });
        // Do NOT call _mapController.move() here — FlutterMap hasn't
        // rendered yet (still showing the loading spinner).
        // The map uses initialCenter: _currentLocation! so it centres itself.
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error getting location: $e')),
        );
      }
    }
    // Start the always-on stream so the blue dot moves continuously.
    // Path recording only happens when _isCapturing is true (guarded inside _onNewGpsPoint).
    _initLocationStream();
  }

  void _toggleCapture() {
    if (_isCapturing) {
      _stopCapturing();
    } else {
      _startCapturing();
    }
  }

  void _startCapturing() {
    setState(() {
      _isCapturing       = true;
      _currentPath.clear();
      _captureInProgress = false;
      _hasBeenOutside    = false;
      _captureStartTime  = DateTime.now();
      _captureDistance   = 0.0;
      if (_currentLocation != null) {
        _currentPath.add(_currentLocation!);
      }
    });
    // Stream is already running (started in _checkPermissionsAndGetLocation).
    // No need to start a second one.
  }

  void _initLocationStream() {
    // Cancel any existing stream first (idempotent)
    _positionStream?.cancel();

    LocationSettings locationSettings;
    if (kIsWeb) {
      // Web uses the browser Geolocation API — no Android/Apple specifics.
      locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 2,
      );
    } else if (Platform.isAndroid) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 2,
        forceLocationManager: false,
      );
    } else if (Platform.isIOS || Platform.isMacOS) {
      locationSettings = AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 2,
        activityType: ActivityType.fitness,
        pauseLocationUpdatesAutomatically: false,
      );
    } else {
      // Linux / Windows — geolocator has no native support; use generic
      // settings and let the error handler show a graceful message.
      locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 2,
      );
    }

    // Kalman-style smoothing state (exponential moving average)
    double? _smoothLat;
    double? _smoothLng;
    const double alpha = 0.4; // 0 = max smoothing, 1 = raw GPS

    // Speed validation: track last accepted position + timestamp
    LatLng? _lastAcceptedPoint;
    DateTime? _lastAcceptedTime;

    _positionStream = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((Position position) {
      // ── Gate 1: Accuracy ─────────────────────────────────────────────────
      if (position.accuracy > 8.0) return;

      // ── Gate 2: Speed Validation ─────────────────────────────────────────
      final rawSpeed = position.speed < 0 ? 0.0 : position.speed;
      if (rawSpeed > 8.0) return;

      final currentRaw = LatLng(position.latitude, position.longitude);
      if (_lastAcceptedPoint != null && _lastAcceptedTime != null) {
        final elapsed = DateTime.now().difference(_lastAcceptedTime!).inMilliseconds;
        if (elapsed > 0) {
          final jumped = const Distance().as(LengthUnit.Meter, _lastAcceptedPoint!, currentRaw);
          final impliedSpeed = jumped / (elapsed / 1000.0);
          if (impliedSpeed > 8.0) return;
        }
      }
      _lastAcceptedPoint = currentRaw;
      _lastAcceptedTime  = DateTime.now();

      // ── Gate 3: Stationary Detection ─────────────────────────────────────
      final isStationary = rawSpeed < 0.4;

      // ── EMA Smoother ─────────────────────────────────────────────────────
      _smoothLat = _smoothLat == null
          ? position.latitude
          : alpha * position.latitude + (1 - alpha) * _smoothLat!;
      _smoothLng = _smoothLng == null
          ? position.longitude
          : alpha * position.longitude + (1 - alpha) * _smoothLng!;

      final smoothed = LatLng(_smoothLat!, _smoothLng!);

      _currentLocation = smoothed;

      if (_displayLocation == null) {
        setState(() { _displayLocation = smoothed; });
        _mapController.move(smoothed, _mapController.camera.zoom);
      } else {
        _animateMarkerTo(smoothed);
      }

      if (_isCapturing && !isStationary) _onNewGpsPoint(smoothed);
    });
  }

  void _stopCapturing() {
    setState(() {
      _isCapturing       = false;
      _currentPath.clear();
      _captureInProgress = false;
      _hasBeenOutside    = false;
    });
    // Keep the stream alive so the marker keeps moving between captures.
  }

  // ── State for the new engine ───────────────────────────────────────────────
  bool _captureInProgress = false;
  bool _hasBeenOutside    = false; // cached: did path ever leave all zones?

  // ── Main entry-point called for every smoothed GPS point ──────────────────
  void _onNewGpsPoint(LatLng smoothed) {
    if (_captureInProgress) return;

    // First point: just seed the path
    if (_currentPath.isEmpty) {
      setState(() { _currentPath.add(smoothed); });
      return;
    }

    // Minimum movement gate (3 m) to suppress standing-still noise
    final dist = const Distance().as(LengthUnit.Meter, _currentPath.last, smoothed);
    if (dist < 3.0) return;

    // Accumulate journey distance for the capture summary dialog
    _captureDistance += dist;

    final prev  = _currentPath.last;
    final zones = _events.map((e) => e.polygon).toList();

    // Update _hasBeenOutside lazily (set once, never cleared until next capture)
    if (!_hasBeenOutside && zones.isNotEmpty) {
      if (!GeoCalculator.isPointInPolygons(smoothed, zones)) {
        _hasBeenOutside = true;
      }
    }

    // ── Case 3A/3B/4/8: Zone-boundary crossing ───────────────────────────────
    if (zones.isNotEmpty && _hasBeenOutside) {
      final zoneCross = CaptureEngine.checkZoneCrossing(prev, smoothed, zones);
      if (zoneCross != null) {
        _triggerZoneCrossCapture(zoneCross.crossPoint, zones);
        return;
      }
    }

    // ── Case 1/2/6: Self-intersection ────────────────────────────────────────
    // Require at least 15 points recorded before checking, and skip the
    // 10 most-recent segments, to prevent false triggers on straight walks.
    if (_currentPath.length >= 15) {
      final selfCross = CaptureEngine.checkSelfIntersection(
          prev, smoothed, _currentPath, skipRecent: 10);
      if (selfCross != null) {
        _triggerSelfIntersectCapture(
            selfCross.crossPoint, selfCross.segmentIndex, zones);
        return;
      }
    }

    setState(() { _currentPath.add(smoothed); });
  }

  // ── Self-intersection capture (Cases 1, 2, 6) ─────────────────────────────
  void _triggerSelfIntersectCapture(
      LatLng crossPoint, int segmentIndex, List<List<LatLng>> zones) {
    // The closed loop = crossPoint + path[segmentIndex+1 .. end] + crossPoint
    final polygon = <LatLng>[crossPoint];
    for (int i = segmentIndex + 1; i < _currentPath.length; i++) {
      polygon.add(_currentPath[i]);
    }
    polygon.add(crossPoint);

    // The journey before the crossing continues as the next capture session
    final remaining = _currentPath.sublist(0, segmentIndex + 1).toList()
      ..add(crossPoint);

    _executeCapture(polygon, zones, remainingPath: remaining);
  }

  // ── Zone re-entry capture (Cases 3A, 3B, 4, 8) ───────────────────────────
  void _triggerZoneCrossCapture(LatLng crossPoint, List<List<LatLng>> zones) {
    // Find the last path point that was inside a zone (the "last inside" anchor)
    int anchorIdx = 0;
    for (int i = _currentPath.length - 1; i >= 0; i--) {
      if (GeoCalculator.isPointInPolygons(_currentPath[i], zones)) {
        anchorIdx = i;
        break;
      }
    }

    // Build capture polygon:
    //   anchorPoint (inside zone) → outside path → crossPoint (back at boundary)
    final polygon = <LatLng>[_currentPath[anchorIdx]];
    for (int i = anchorIdx + 1; i < _currentPath.length; i++) {
      polygon.add(_currentPath[i]);
    }
    polygon.add(crossPoint);
    polygon.add(_currentPath[anchorIdx]); // close

    _executeCapture(polygon, zones, remainingPath: [crossPoint]);
  }

  // ── Execute a capture: resolve → save → update UI ─────────────────────────
  Future<void> _executeCapture(
      List<LatLng> polygon,
      List<List<LatLng>> zones,
      {List<LatLng>? remainingPath}) async {
    _captureInProgress = true;

    final newZones = CaptureEngine.resolveCapture(polygon, zones);

    // Case 5: nested loop — no new area added (same list reference)
    if (identical(newZones, zones)) {
      setState(() {
        _currentPath.clear();
        if (remainingPath != null) _currentPath.addAll(remainingPath);
        _hasBeenOutside = false;
      });
      _captureInProgress = false;
      return;
    }

    // Compute total area of the merged result
    double newTotalArea = 0;
    for (final z in newZones) {
      newTotalArea += GeoCalculator.calculateArea(z);
    }

    // If the area barely changed (< 1 m²) also treat as nested loop
    if (newTotalArea - _totalScore < 1.0) {
      setState(() {
        _currentPath.clear();
        if (remainingPath != null) _currentPath.addAll(remainingPath);
        _hasBeenOutside = false;
      });
      _captureInProgress = false;
      return;
    }

    // Reverse-geocode — not available on web or Linux/Windows.
    String? regionName;
    final supportsGeocoding = !kIsWeb &&
        (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);
    if (supportsGeocoding) {
      try {
        final placemarks = await geo.placemarkFromCoordinates(
          polygon.first.latitude, polygon.first.longitude,
        ).timeout(const Duration(seconds: 3));
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          regionName = [p.locality, p.administrativeArea]
              .where((e) => e != null && e.isNotEmpty)
              .join(', ');
          if (regionName.isEmpty) regionName = p.country;
        }
      } catch (_) {}
    }

    final newEvents = <CaptureEvent>[];
    for (final z in newZones) {
      final area = GeoCalculator.calculateArea(z);
      newEvents.add(CaptureEvent.create(
        polygon: z,
        area: area,
        username: _currentUsername,
        regionName: regionName,
        playerTotalScore: newTotalArea,
      ));
    }

    final int oldLevel = LevelSystem.getLevel(_totalScore);
    final int newLevel = LevelSystem.getLevel(newTotalArea);

    // Snapshot journey tracking BEFORE we reset state
    final double journeyDist  = _captureDistance;
    final DateTime journeyStart = _captureStartTime ?? DateTime.now();

    // Compute journey gain while _totalScore is still the OLD value
    final double journeyGain = newTotalArea - _totalScore;

    if (!mounted) { _captureInProgress = false; return; }

    setState(() {
      _events     = newEvents;
      _totalScore = newTotalArea;
      _currentPath.clear();
      if (remainingPath != null && remainingPath.isNotEmpty) {
        _currentPath.addAll(remainingPath);
      } else if (polygon.isNotEmpty) {
        _currentPath.add(polygon.last);
      }
      _hasBeenOutside    = false;
      // Reset per-segment journey tracking for the next territory
      _captureDistance   = 0.0;
      _captureStartTime  = DateTime.now();
    });

    await _storageService.saveEvents(_events);
    if (journeyGain > 1.0) {
      await _storageService.addJourneyArea(journeyGain);
    }
    _captureInProgress = false;

    if (newEvents.isNotEmpty && mounted) {
      await _showCaptureResult(
        event: newEvents.first,
        leveledUp: newLevel > oldLevel,
        newLevel: newLevel,
        journeyDistance: journeyDist,
        journeyStartTime: journeyStart,
      );
    }
  }

  void _handleMapTap(TapPosition tapPosition, LatLng point) {
    if (!_isPlanningMode) return;
    setState(() {
      _plannedPath.add(point);
      _updatePlanStats();
    });
  }

  void _updatePlanStats() {
    if (_plannedPath.length < 2) {
      _plannedDistance = 0;
      _plannedArea = 0;
      _plannedTimeMinutes = 0;
      return;
    }
    
    double totalDist = 0;
    for (int i = 0; i < _plannedPath.length - 1; i++) {
      totalDist += _distance.as(LengthUnit.Meter, _plannedPath[i], _plannedPath[i+1]);
    }
    
    if (_plannedPath.length >= 3) {
      totalDist += _distance.as(LengthUnit.Meter, _plannedPath.last, _plannedPath.first);
      _plannedArea = GeoCalculator.calculateArea(_plannedPath);
    } else {
      _plannedArea = 0;
    }
    
    _plannedDistance = totalDist;
    _plannedTimeMinutes = (_plannedDistance / 82.8).ceil(); // ~5 km/h
  }

  void _togglePlanningMode() {
    setState(() {
      _isPlanningMode = !_isPlanningMode;
      if (!_isPlanningMode) {
        _plannedPath.clear();
        _plannedDistance = 0;
        _plannedArea = 0;
        _plannedTimeMinutes = 0;
      }
    });
  }

  String _formatDistance(double meters) {
    bool useMetric = SettingsService().useMetric.value;
    if (useMetric) {
      if (meters >= 1000) return '${(meters / 1000).toStringAsFixed(2)} km';
      return '${meters.toStringAsFixed(0)} m';
    } else {
      double feet = meters * 3.28084;
      if (feet >= 5280) return '${(feet / 5280).toStringAsFixed(2)} mi';
      return '${feet.toStringAsFixed(0)} ft';
    }
  }

  String _formatArea(double sqMeters) {
    bool useMetric = SettingsService().useMetric.value;
    if (useMetric) {
      return '${sqMeters.toStringAsFixed(1)} m²';
    } else {
      double sqFeet = sqMeters * 10.7639;
      return '${sqFeet.toStringAsFixed(1)} ft²';
    }
  }

  // ── Sidebar button helper ─────────────────────────────────────────────────
  Widget _buildSidebarBtn({
    required IconData icon,
    Color? color,
    Color iconColor = Colors.white70,
    BoxBorder? border,
    required VoidCallback onPressed,
    String? tooltip,
  }) {
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: Container(
          decoration: BoxDecoration(
            color: color ?? Colors.black.withValues(alpha: 0.3),
            shape: BoxShape.circle,
            border: border ?? Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: IconButton(
            icon: Icon(icon, color: iconColor),
            onPressed: onPressed,
            tooltip: tooltip,
          ),
        ),
      ),
    );
  }

  Widget _buildPlanStatItem(IconData icon, String label, String value, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 8),
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 1.5)),
      ],
    );
  }

  // ── Capture result dialog ─────────────────────────────────────────────────
  Future<void> _showCaptureResult({
    required CaptureEvent event,
    required bool leveledUp,
    required int newLevel,
    required double journeyDistance,
    required DateTime journeyStartTime,
  }) async {
    if (!mounted) return;
    final settings    = SettingsService();
    final bool metric = settings.useMetric.value;
    final duration    = DateTime.now().difference(journeyStartTime);
    final durationStr = _formatDuration(duration);
    final double distKm   = journeyDistance / 1000;
    final double speedKmh = duration.inSeconds > 0 ? distKm / (duration.inSeconds / 3600) : 0.0;
    final int calories    = (distKm * 60).round();

    final String distStr = metric
        ? (journeyDistance >= 1000 ? '${(journeyDistance/1000).toStringAsFixed(2)} km' : '${journeyDistance.toStringAsFixed(0)} m')
        : () { final ft = journeyDistance * 3.28084; return ft >= 5280 ? '${(ft/5280).toStringAsFixed(2)} mi' : '${ft.toStringAsFixed(0)} ft'; }();

    final String speedStr = metric ? '${speedKmh.toStringAsFixed(1)} km/h' : '${(speedKmh*0.621371).toStringAsFixed(1)} mph';

    final int currentLvl    = LevelSystem.getLevel(_totalScore);
    final double nextLvlReq = LevelSystem.getNextLevelXpStart(currentLvl);
    final double needed     = (nextLvlReq - _totalScore).clamp(0.0, nextLvlReq);
    final bool maxLvl       = currentLvl >= LevelSystem.maxLevel;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 60),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF12121C).withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: event.tierColor.withValues(alpha: 0.6), width: 1.5),
                boxShadow: [BoxShadow(color: event.tierColor.withValues(alpha: 0.25), blurRadius: 30, spreadRadius: 2)],
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: event.tierColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(50),
                        border: Border.all(color: event.tierColor.withValues(alpha: 0.4)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.emoji_events, color: event.tierColor, size: 20),
                        const SizedBox(width: 8),
                        Text('TERRITORY CAPTURED',
                            style: TextStyle(color: event.tierColor, fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 12)),
                      ]),
                    ),
                    const SizedBox(height: 20),
                    _captureStatRow('📐', 'Area', _formatArea(event.area)),
                    _captureStatRow('🚶', 'Distance Walked', distStr),
                    _captureStatRow('⏱', 'Duration', durationStr),
                    _captureStatRow('⚡', 'Average Speed', speedStr),
                    _captureStatRow('🔥', 'Calories Burned', '${calories > 0 ? calories : "<1"} kcal'),
                    const Divider(color: Colors.white12, height: 28),
                    _captureStatRow('🏅', 'Current Rank', LevelSystem.getRankTitle(currentLvl)),
                    if (!maxLvl) ...[
                      _captureStatRow('📊', 'Progress to Next Rank',
                          '${_totalScore.toStringAsFixed(0)} / ${nextLvlReq.toStringAsFixed(0)} m²'),
                      _captureStatRow('🎯', 'Need', '${needed.toStringAsFixed(0)} m² more'),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: LevelSystem.getProgressToNextLevel(_totalScore),
                          backgroundColor: Colors.white12,
                          valueColor: AlwaysStoppedAnimation<Color>(event.tierColor),
                          minHeight: 6,
                        ),
                      ),
                    ] else
                      _captureStatRow('🏆', 'Status', 'GEO MASTER — MAX LEVEL!'),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: event.tierColor,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('CONTINUE',
                            style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (leveledUp && mounted) await _showLevelUpDialog(newLevel);
  }

  Widget _captureStatRow(String emoji, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(children: [
      Text(emoji, style: const TextStyle(fontSize: 16)),
      const SizedBox(width: 10),
      Expanded(child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13))),
      Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
    ]),
  );

  // ── Level-up celebration ──────────────────────────────────────────────────
  Future<void> _showLevelUpDialog(int newLevel) async {
    if (!mounted) return;
    final newColors  = RewardsSystem.colors.where((r) => r.requiredLevel == newLevel).toList();
    final newAvatars = RewardsSystem.avatars.where((r) => r.requiredLevel == newLevel).toList();
    final rankTitle  = LevelSystem.getRankTitle(newLevel);

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 80),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: [Color(0xFF1A1A2E), Color(0xFF16213E)]),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.7), width: 1.5),
                boxShadow: [BoxShadow(
                    color: Colors.amberAccent.withValues(alpha: 0.3), blurRadius: 40, spreadRadius: 4)],
              ),
              padding: const EdgeInsets.all(28),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('🎉', style: TextStyle(fontSize: 48)),
                const SizedBox(height: 8),
                const Text('LEVEL UP!',
                    style: TextStyle(color: Colors.amberAccent, fontSize: 28,
                        fontWeight: FontWeight.w900, letterSpacing: 4)),
                const SizedBox(height: 4),
                Text('You are now a',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13)),
                const SizedBox(height: 6),
                Text(rankTitle,
                    style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                Text('Level $newLevel',
                    style: TextStyle(
                        color: Colors.amberAccent.withValues(alpha: 0.8),
                        fontSize: 13, fontWeight: FontWeight.bold)),
                if (newColors.isNotEmpty || newAvatars.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.2)),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('🔓 REWARDS UNLOCKED',
                          style: TextStyle(color: Colors.amberAccent, fontSize: 10,
                              fontWeight: FontWeight.bold, letterSpacing: 2)),
                      const SizedBox(height: 12),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        ...newColors.map((r) => Column(mainAxisSize: MainAxisSize.min, children: [
                          Container(
                            width: 32, height: 32,
                            decoration: BoxDecoration(
                              color: r.color, shape: BoxShape.circle,
                              border: Border.all(color: Colors.white30, width: 1.5)),
                          ),
                          const SizedBox(height: 4),
                          Text(r.name, style: const TextStyle(color: Colors.white70, fontSize: 9)),
                        ])),
                        ...newAvatars.map((r) => Column(mainAxisSize: MainAxisSize.min, children: [
                          Container(
                            width: 32, height: 32,
                            decoration: BoxDecoration(
                              color: Colors.white10, shape: BoxShape.circle,
                              border: Border.all(color: Colors.white30, width: 1.5)),
                            child: Center(
                              child: r.emoji != null
                                  ? Text(r.emoji!, style: const TextStyle(fontSize: 16))
                                  : Icon(r.icon, size: 16, color: Colors.white70),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(r.name, style: const TextStyle(color: Colors.white70, fontSize: 9)),
                        ])),
                      ]),
                    ]),
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amberAccent, foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('AWESOME!',
                        style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2)),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  String _formatDuration(Duration d) {
    final m = d.inMinutes; final s = d.inSeconds % 60;
    return m == 0 ? '${s}s' : '${m}m ${s}s';
  }

  String _getMapScale(double zoom, double latDeg, bool metric) {
    const double earthCirc = 40075016.686;
    final metersPerPx = earthCirc * cos(latDeg * pi / 180) / (256.0 * pow(2, zoom));
    final double mPerCm = metersPerPx * 63.0;
    if (metric) {
      return mPerCm >= 1000
          ? '1 cm = ${(mPerCm/1000).toStringAsFixed(1)} km'
          : '1 cm = ${mPerCm.toStringAsFixed(0)} m';
    }
    final fPerCm = mPerCm * 3.28084;
    return fPerCm >= 5280
        ? '1 cm = ${(fPerCm/5280).toStringAsFixed(1)} mi'
        : '1 cm = ${fPerCm.toStringAsFixed(0)} ft';
  }

  // ── Google Maps-style scale bar ──────────────────────────────────────────
  ({double widthPx, String label}) _computeScaleBar(double zoom, double latDeg, bool metric) {
    final metersPerPx = 40075016.686 * cos(latDeg * pi / 180) / (256.0 * pow(2, zoom));
    const double targetWidthPx = 90.0;
    final double targetMeters  = metersPerPx * targetWidthPx;

    final niceM = [1, 2, 5, 10, 20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000, 50000];
    double chosen = niceM[0].toDouble();
    for (final d in niceM) {
      if (d.toDouble() <= targetMeters) chosen = d.toDouble();
      else break;
    }

    final barWidthPx = chosen / metersPerPx;

    String label;
    if (metric) {
      label = chosen >= 1000
          ? '${(chosen / 1000).toStringAsFixed(chosen >= 10000 ? 0 : 1)} km'
          : '${chosen.toStringAsFixed(0)} m';
    } else {
      final feet = chosen * 3.28084;
      label = feet >= 5280
          ? '${(feet / 5280).toStringAsFixed(1)} mi'
          : '${feet.toStringAsFixed(0)} ft';
    }
    return (widthPx: barWidthPx, label: label);
  }

  Widget _buildMapScaleWidget(bool metric) {
    final bar = _computeScaleBar(_mapZoom, _mapLat, metric);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Distance label
        Text(
          bar.label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            shadows: [Shadow(blurRadius: 3, color: Colors.black87)],
          ),
        ),
        const SizedBox(height: 3),
        // I-beam bar
        SizedBox(
          width: bar.widthPx,
          height: 9,
          child: CustomPaint(
            painter: _ScaleBarPainter(),
          ),
        ),
      ],
    );
  }


  void _resetData() async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E28),
        title: const Text('Reset Conquest?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text('This will wipe all captured territories and your total score.', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('CANCEL', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await _storageService.wipeData();
              if (mounted) {
                setState(() {
                  _events.clear();
                  _totalScore = 0.0;
                  _currentPath.clear();
                  if (_isCapturing) _stopCapturing();
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Simulation reset. Begin anew.'),
                    backgroundColor: Theme.of(context).colorScheme.primary,
                  ),
                );
              }
            },
            child: const Text('RESET', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // Animate the player dot smoothly from its current display position to [target]
  void _animateMarkerTo(LatLng target) {
    final from = _displayLocation ?? target;
    _markerAnimController!.stop();
    _animatedLat = Tween<double>(begin: from.latitude,  end: target.latitude)
        .animate(CurvedAnimation(parent: _markerAnimController!, curve: Curves.easeOut));
    _animatedLng = Tween<double>(begin: from.longitude, end: target.longitude)
        .animate(CurvedAnimation(parent: _markerAnimController!, curve: Curves.easeOut));
    _markerAnimController!.forward(from: 0.0);
  }

  @override
  void dispose() {
    SettingsService().mapStyle.removeListener(_onMapStyleChanged);
    _positionStream?.cancel();
    _pulseController.dispose();
    _markerAnimController?.dispose();
    super.dispose();
  }

  /// Computes the maximum zoom level for Satellite view such that the map
  /// scale never drops below 27 m/cm — the point where ESRI tiles run out.
  /// The result varies with latitude (cos projection).
  double _satelliteMaxZoom() {
    const double minMetersPerCm = 27.0; // scale threshold requested by user
    const double earthCirc      = 40075016.686;
    const double dpPerCm        = 63.0;  // Flutter logical pixels per cm
    final cosLat = cos(_mapLat * pi / 180).clamp(0.001, 1.0);
    final val    = earthCirc * cosLat * dpPerCm / (256.0 * minMetersPerCm);
    return log(val) / log(2);
  }

  /// Called whenever the map style changes.
  /// If the user switches TO satellite while zoomed in past the tile limit,
  /// snap the camera back to the computed satellite max zoom.
  void _onMapStyleChanged() {
    if (!mounted) return;
    if (SettingsService().mapStyle.value == SettingsService.mapStyleSatellite) {
      final maxZ = _satelliteMaxZoom();
      if (_mapController.camera.zoom > maxZ) {
        _mapController.move(_mapController.camera.center, maxZ);
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    int currentLevel = LevelSystem.getLevel(_totalScore);
    final settings = SettingsService();

    return AnimatedBuilder(
      animation: Listenable.merge([
        settings.mapStyle,
        settings.reconColor,
        settings.useMetric,
        settings.markerType,
        settings.profileImagePath,
        settings.selectedColorIndex,
        settings.showMapScale,
      ]),
      builder: (context, _) {
        final mapStyle = settings.mapStyle.value;
        final recColor = settings.reconColor.value;

        final playerColor = settings.selectedColor;

        return Scaffold(
          body: Stack(
        children: [
          if (_currentLocation == null)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    color: Theme.of(context).colorScheme.secondary,
                    strokeWidth: 3,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'CALIBRATING SENSORS...',
                    style: TextStyle(color: Colors.white70, letterSpacing: 2, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            )
          else
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _currentLocation!,
                initialZoom: 16.5,
                minZoom: 3.0,
                maxZoom: mapStyle == SettingsService.mapStyleSatellite ? _satelliteMaxZoom() : null,

                onTap: _handleMapTap,
                onPositionChanged: (camera, hasGesture) {
                  final newZoom = camera.zoom;
                  final newLat  = camera.center.latitude;
                  final panGesture = hasGesture && _followingUser;
                  if (panGesture || newZoom != _mapZoom || (newLat - _mapLat).abs() > 0.0001) {
                    setState(() {
                      _mapZoom = newZoom;
                      _mapLat  = newLat;
                      if (panGesture) _followingUser = false;
                    });
                  }
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: mapStyle,
                  // Only use subdomains for tile URLs that contain the {s} placeholder
                  subdomains: mapStyle.contains('{s}') ? const <String>['a', 'b', 'c', 'd'] : const <String>[],
                  userAgentPackageName: 'com.example.geoseize',
                ),
                PolygonLayer(
                  polygons: _events.map((event) => Polygon(
                    points: event.polygon,
                    color: playerColor.withValues(alpha: 0.25),
                    borderColor: playerColor,
                    borderStrokeWidth: 3,
                  )).toList(),
                ),
                MarkerLayer(
                  markers: _events.map((event) {
                    // getVisualCenter is always inside the polygon, even for
                    // concave or fused L-shaped / T-shaped zones.
                    final center = GeoCalculator.getVisualCenter(event.polygon);
                    final fontSize = GeoCalculator.getZoneLabelFontSize(event.area);
                    // Scale the marker widget width proportionally so text always fits
                    final markerWidth = (fontSize * event.username.length * 0.75).clamp(80.0, 300.0);
                    return Marker(
                      point: center,
                      width: markerWidth,
                      height: fontSize + 12,
                      child: GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            SlideUpPageRoute(
                              page: StatisticsScreen(
                                // Pass the zone owner's username.
                                // When multiplayer launches, swap this for a userId
                                // and load that user's data from Firestore.
                                ownerUsername: event.username,
                              ),
                            ),
                          );
                        },
                        child: Center(
                          child: Text(
                            event.username.toUpperCase(),
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: fontSize,
                              shadows: [
                                const Shadow(blurRadius: 4.0, color: Colors.black),
                                Shadow(blurRadius: 8.0, color: playerColor),
                                Shadow(blurRadius: 12.0, color: playerColor),
                              ],
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                PolylineLayer(
                  polylines: [
                    if (_currentPath.isNotEmpty)
                      Polyline(
                        points: _currentPath,
                        color: playerColor,
                        strokeWidth: 5,
                        strokeCap: StrokeCap.round,
                        strokeJoin: StrokeJoin.round,
                      ),
                  ],
                ),
                if (_isPlanningMode && _plannedPath.length >= 3)
                  PolygonLayer(
                    polygons: [
                      Polygon(
                        points: _plannedPath,
                        color: recColor.withValues(alpha: 0.2),
                        borderColor: recColor,
                        borderStrokeWidth: 2,
                      ),
                    ],
                  ),
                if (_isPlanningMode && _plannedPath.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _plannedPath,
                        color: recColor,
                        strokeWidth: 4,
                      ),
                      if (_plannedPath.length >= 3)
                        Polyline(
                          points: [_plannedPath.last, _plannedPath.first],
                          color: recColor.withValues(alpha: 0.5),
                          strokeWidth: 4,
                        ),
                    ],
                  ),
                if (_isPlanningMode && _plannedPath.isNotEmpty)
                  MarkerLayer(
                    markers: _plannedPath.map((p) => Marker(
                      point: p,
                      width: 12,
                      height: 12,
                      child: Container(
                        decoration: BoxDecoration(
                          color: recColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.black, width: 2),
                        ),
                      ),
                    )).toList(),
                  ),
                if (_displayLocation != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _displayLocation!,
                        width: 40,
                        height: 40,
                        child: AnimatedBuilder(
                          animation: _pulseAnimation,
                          builder: (context, child) {
                            final markerType = settings.markerType.value;
                            Widget centerWidget;

                            if (markerType == 'profile') {
                              final localPath = settings.profileImagePath.value;
                              final googlePhotoUrl = AuthService().currentUser?.photoURL;
                              
                              Widget imageWidget;
                              if (localPath != null && localPath.isNotEmpty && !kIsWeb) {
                                imageWidget = Image.file(File(localPath), fit: BoxFit.cover);
                              } else if (googlePhotoUrl != null && googlePhotoUrl.isNotEmpty) {
                                imageWidget = Image.network(googlePhotoUrl, fit: BoxFit.cover);
                              } else {
                                imageWidget = Icon(Icons.account_circle, color: Theme.of(context).colorScheme.secondary, size: 24);
                              }
                              
                              centerWidget = Container(
                                width: 26, height: 26,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 2),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Theme.of(context).colorScheme.secondary,
                                      blurRadius: 8,
                                      spreadRadius: 2,
                                    )
                                  ]
                                ),
                                child: ClipOval(child: imageWidget),
                              );
                            } else if (markerType != 'default') {
                              // Emoji avatar
                              centerWidget = Container(
                                width: 28, height: 28,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white.withValues(alpha: 0.9),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Theme.of(context).colorScheme.secondary,
                                      blurRadius: 8,
                                      spreadRadius: 2,
                                    )
                                  ]
                                ),
                                child: Center(
                                  child: Text(markerType, style: const TextStyle(fontSize: 18)),
                                ),
                              );
                            } else {
                              // Default dot
                              centerWidget = Container(
                                width: 14, height: 14,
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.secondary,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 2),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Theme.of(context).colorScheme.secondary,
                                      blurRadius: 8,
                                      spreadRadius: 2,
                                    )
                                  ]
                                ),
                              );
                            }

                            return Transform.scale(
                              scale: _pulseAnimation.value,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: centerWidget,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
              ],
            ),

          // Glassmorphism HUD
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            right: 16,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E28).withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text('LVL $currentLevel', style: TextStyle(color: Theme.of(context).colorScheme.secondary, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                              const SizedBox(width: 8),
                              Text(
                                LevelSystem.getRankTitle(currentLevel).toUpperCase(),
                                style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(_formatArea(_totalScore), style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('ZONES', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                          const SizedBox(height: 4),
                          Text('${_events.length}', style: TextStyle(color: Theme.of(context).colorScheme.secondary, fontSize: 26, fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Action Buttons (Right side) ─────────────────────────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 130,
            right: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // ── Always-visible: Stats ─────────────────────────────────────
                _buildSidebarBtn(
                  icon: Icons.analytics,
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
                  iconColor: Colors.white,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                  onPressed: () {
                    Navigator.push(
                      context,
                      SlideUpPageRoute(page: const StatisticsScreen()),
                    ).then((_) => _loadData());
                  },
                  tooltip: 'Statistics',
                ),
                const SizedBox(height: 12),

                // ── Always-visible: Expand / Collapse arrow ───────────────────
                GestureDetector(
                  onTap: () => setState(() => _sidebarExpanded = !_sidebarExpanded),
                  child: ClipOval(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.35),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: AnimatedRotation(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                            turns: _sidebarExpanded ? 0.5 : 0.0, // flips arrow up/down
                            child: const Icon(Icons.keyboard_arrow_down, color: Colors.white70, size: 24),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // ── Expandable section ────────────────────────────────────────
                AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  alignment: Alignment.topCenter,
                  child: _sidebarExpanded
                      ? Column(
                          children: [
                            const SizedBox(height: 12),
                            // Calibrate / Re-centre GPS
                            _buildSidebarBtn(
                              icon: Icons.my_location,
                              onPressed: () async {
                                final pos = await Geolocator.getCurrentPosition(
                                    desiredAccuracy: LocationAccuracy.best);
                                final pt = LatLng(pos.latitude, pos.longitude);
                                setState(() {
                                  _currentLocation = pt;
                                  _displayLocation = pt;
                                  _followingUser   = true;
                                });
                                _mapController.move(pt, _mapController.camera.zoom);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Location refreshed — following you again!')),
                                  );
                                }
                              },
                              tooltip: 'Calibrate GPS',
                            ),
                            const SizedBox(height: 12),
                            // Settings
                            _buildSidebarBtn(
                              icon: Icons.settings,
                              onPressed: () => Navigator.push(
                                context,
                                SlideUpPageRoute(
                                  page: SettingsScreen(totalScore: _totalScore),
                                ),
                              ),
                              tooltip: 'Settings',
                            ),
                            const SizedBox(height: 12),
                            // Recon / Planning mode
                            _buildSidebarBtn(
                              icon: Icons.explore,
                              color: _isPlanningMode
                                  ? recColor.withValues(alpha: 0.2)
                                  : Colors.black.withValues(alpha: 0.3),
                              iconColor: _isPlanningMode ? recColor : Colors.white70,
                              border: Border.all(
                                color: _isPlanningMode ? recColor : Colors.white.withValues(alpha: 0.1),
                              ),
                              onPressed: _togglePlanningMode,
                              tooltip: 'Recon Mode',
                            ),
                          ],
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),


          // Map scale indicator — bottom-left, Google Maps style
          if (settings.showMapScale.value)
            Positioned(
              bottom: 16,
              left: 16,
              child: _buildMapScaleWidget(settings.useMetric.value),
            ),

          // Planning Stats Panel
          if (_isPlanningMode)
            Positioned(
              bottom: 40,
              left: 16,
              right: 16,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E28).withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.3), width: 1),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'RECONNAISSANCE MODE',
                          style: TextStyle(color: recColor, fontWeight: FontWeight.bold, letterSpacing: 3),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildPlanStatItem(Icons.route, 'DISTANCE', _formatDistance(_plannedDistance), recColor),
                            _buildPlanStatItem(Icons.timer, 'EST. TIME', '$_plannedTimeMinutes min', recColor),
                            _buildPlanStatItem(Icons.square_foot, 'AREA YIELD', _formatArea(_plannedArea), recColor),
                          ],
                        ),
                        if (_plannedPath.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          TextButton.icon(
                            onPressed: () {
                              setState(() {
                                _plannedPath.clear();
                                _updatePlanStats();
                              });
                            },
                            icon: const Icon(Icons.clear, color: Colors.white54, size: 18),
                            label: const Text('CLEAR ROUTE', style: TextStyle(color: Colors.white54, letterSpacing: 1.5)),
                          )
                        ]
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // Custom Capture Button (hide if planning)
          if (!_isPlanningMode)
            Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _toggleCapture,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  decoration: BoxDecoration(
                    color: _isCapturing ? Colors.transparent : Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                      color: _isCapturing ? Colors.redAccent : Colors.transparent,
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _isCapturing ? Colors.redAccent.withValues(alpha: 0.4) : Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
                        blurRadius: 15,
                        spreadRadius: 2,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isCapturing ? Icons.stop_circle_outlined : Icons.play_circle_fill,
                        color: _isCapturing ? Colors.redAccent : Colors.white,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _isCapturing ? 'STOP CAPTURE' : 'BEGIN CAPTURE',
                        style: TextStyle(
                          color: _isCapturing ? Colors.redAccent : Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
        ),
        );
      },
    );
  }
}

// ── Scale bar painter — Google Maps I-beam style ──────────────────────────────────────────
class _ScaleBarPainter extends CustomPainter {
  const _ScaleBarPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final double cx = size.width;
    final double cy = size.height / 2;
    const double tickH = 9.0;

    final outline = Paint()
      ..color = Colors.black.withValues(alpha: 0.65)
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.square
      ..style = PaintingStyle.stroke;

    canvas.drawLine(Offset(1, 0), Offset(1, tickH), outline);
    canvas.drawLine(Offset(1, cy), Offset(cx - 1, cy), outline);
    canvas.drawLine(Offset(cx - 1, 0), Offset(cx - 1, tickH), outline);

    final white = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.square
      ..style = PaintingStyle.stroke;

    canvas.drawLine(Offset(1, 0), Offset(1, tickH), white);
    canvas.drawLine(Offset(1, cy), Offset(cx - 1, cy), white);
    canvas.drawLine(Offset(cx - 1, 0), Offset(cx - 1, tickH), white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
