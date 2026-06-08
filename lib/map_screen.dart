import 'dart:async';
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
  
  @override
  void initState() {
    super.initState();
    _loadData();
    _checkPermissionsAndGetLocation();

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
      _isCapturing = true;
      _currentPath.clear();
      _captureInProgress = false;
      _hasBeenOutside    = false;
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
      _hasBeenOutside = false;
    });

    await _storageService.saveEvents(_events);
    // Record this journey's net area gain for per-journey statistics
    final journeyGain = newTotalArea - _totalScore;
    if (journeyGain > 1.0) {
      await _storageService.addJourneyArea(journeyGain);
    }
    _captureInProgress = false;


    if (newEvents.isNotEmpty && mounted) {
      _showSuccessMessage(newEvents.first, leveledUp: newLevel > oldLevel);
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

  void _showSuccessMessage(CaptureEvent event, {required bool leveledUp}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.rocket_launch, color: event.tierColor),
                const SizedBox(width: 12),
                Text(
                  '${event.tierName} ZONE CAPTURED!',
                  style: TextStyle(color: event.tierColor, fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('+${event.area.toStringAsFixed(1)} m²', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            if (leveledUp)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'LEVEL UP! You are now a ${LevelSystem.getRankTitle(LevelSystem.getLevel(_totalScore))}',
                  style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontStyle: FontStyle.italic),
                ),
              ),
          ],
        ),
        backgroundColor: const Color(0xFF1E1E28).withValues(alpha: 0.95),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: event.tierColor, width: 2),
        ),
        margin: const EdgeInsets.only(bottom: 100, left: 16, right: 16),
        elevation: 10,
        duration: const Duration(seconds: 4),
      ),
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
    _positionStream?.cancel();
    _pulseController.dispose();
    _markerAnimController?.dispose();
    super.dispose();
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
                onTap: _handleMapTap,
                onPositionChanged: (camera, hasGesture) {
                  // User manually panned — stop auto-following until recalibrated
                  if (hasGesture && _followingUser) {
                    setState(() { _followingUser = false; });
                  }
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: mapStyle,
                  subdomains: const ['a', 'b', 'c', 'd'],
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
                              Text('CONQUERED', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
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

          // Action Buttons (Right side)
          Positioned(
            top: MediaQuery.of(context).padding.top + 130,
            right: 16,
            child: Column(
              children: [
                // Scoreboard Button
                ClipOval(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.analytics, color: Colors.white),
                        onPressed: () {
                          Navigator.push(
                            context,
                            SlideUpPageRoute(page: const StatisticsScreen()),
                          ).then((_) {
                            // Reload data when returning from statistics
                            _loadData();
                          });
                        },
                        tooltip: 'Statistics',
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Reset Button
                ClipOval(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.3),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.refresh, color: Colors.white70),
                        onPressed: _resetData,
                        tooltip: 'Reset Simulation',
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Calibrate GPS Button
                ClipOval(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.3),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.my_location, color: Colors.white70),
                        onPressed: () async {
                          final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best);
                          final pt = LatLng(pos.latitude, pos.longitude);
                          setState(() {
                            _currentLocation  = pt;
                            _displayLocation  = pt;
                            _followingUser    = true; // re-enable camera follow
                          });
                          _mapController.move(pt, _mapController.camera.zoom);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Location Refreshed — following you again!')),
                            );
                          }
                        },
                        tooltip: 'Calibrate GPS',
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Settings Button
                ClipOval(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.3),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.settings, color: Colors.white70),
                        onPressed: () {
                          Navigator.push(
                            context,
                            SlideUpPageRoute(page: SettingsScreen(totalScore: _totalScore)),
                          );
                        },
                        tooltip: 'Settings',
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Recon Mode Toggle Button
                ClipOval(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                    child: Container(
                      decoration: BoxDecoration(
                        color: _isPlanningMode ? recColor.withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.3),
                        shape: BoxShape.circle,
                        border: Border.all(color: _isPlanningMode ? recColor : Colors.white.withValues(alpha: 0.1)),
                      ),
                      child: IconButton(
                        icon: Icon(Icons.explore, color: _isPlanningMode ? recColor : Colors.white70),
                        onPressed: _togglePlanningMode,
                        tooltip: 'Recon Mode',
                      ),
                    ),
                  ),
                ),
              ],
            ),
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

