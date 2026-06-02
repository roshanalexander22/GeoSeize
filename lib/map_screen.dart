import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'models/capture_event.dart';
import 'services/storage_service.dart';
import 'utils/geo_calculator.dart';
import 'utils/level_system.dart';
import 'scoreboard_screen.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with SingleTickerProviderStateMixin {
  final MapController _mapController = MapController();
  final StorageService _storageService = StorageService();
  
  final List<LatLng> _currentPath = [];
  List<CaptureEvent> _events = [];
  double _totalScore = 0.0;
  
  StreamSubscription<Position>? _positionStream;
  bool _isCapturing = false;
  LatLng? _currentLocation;
  
  final Distance _distance = const Distance();

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  
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
  }

  Future<void> _loadData() async {
    final loadedEvents = await _storageService.loadEvents();
    final loadedScore = await _storageService.loadTotalArea();
    setState(() {
      _events = loadedEvents;
      _totalScore = loadedScore;
    });
  }
  
  Future<void> _checkPermissionsAndGetLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    try {
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location services are disabled. Please enable them in your device settings.')),
          );
        }
        return;
      }

      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Location permissions are denied. We need this to track your conquests!')),
            );
          }
          return;
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permissions are permanently denied. Please enable them in app settings.')),
          );
        }
        return;
      } 

      Position position = await Geolocator.getCurrentPosition();
      if (mounted) {
        setState(() {
          _currentLocation = LatLng(position.latitude, position.longitude);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error getting location: $e')),
        );
      }
    }
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
      if (_currentLocation != null) {
        _currentPath.add(_currentLocation!);
      }
    });

    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 3, 
      ),
    ).listen((Position position) {
      final newPoint = LatLng(position.latitude, position.longitude);
      
      setState(() {
        _currentLocation = newPoint;
        if (_isCapturing) {
          _currentPath.add(newPoint);
          _checkForLoop(newPoint);
        }
      });
      _mapController.move(newPoint, _mapController.camera.zoom);
    });
  }

  void _stopCapturing() {
    _positionStream?.cancel();
    setState(() {
      _isCapturing = false;
      _currentPath.clear();
    });
  }

  void _checkForLoop(LatLng newPoint) {
    if (_currentPath.length < 15) return; 

    // Look back at earlier points to see if we've crossed our path
    for (int i = 0; i < _currentPath.length - 10; i++) {
      final oldPoint = _currentPath[i];
      final distanceInMeters = _distance.as(LengthUnit.Meter, newPoint, oldPoint);
      
      if (distanceInMeters < 15) {
        final loopPoints = _currentPath.sublist(i).toList();
        final double areaCaptured = GeoCalculator.calculateArea(loopPoints);
        
        final newEvent = CaptureEvent.create(polygon: loopPoints, area: areaCaptured);

        final int oldLevel = LevelSystem.getLevel(_totalScore);
        final int newLevel = LevelSystem.getLevel(_totalScore + areaCaptured);

        setState(() {
          _events.add(newEvent);
          _totalScore += areaCaptured;
          _currentPath.clear();
          _currentPath.add(newPoint);
        });
        
        _storageService.saveEvents(_events);
        
        _showSuccessMessage(newEvent, leveledUp: newLevel > oldLevel);
        break;
      }
    }
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

  @override
  void dispose() {
    _positionStream?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    int currentLevel = LevelSystem.getLevel(_totalScore);

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
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
                  subdomains: const ['a', 'b', 'c', 'd'],
                  userAgentPackageName: 'com.example.geoseize',
                ),
                PolygonLayer(
                  polygons: _events.map((event) => Polygon(
                    points: event.polygon,
                    color: event.tierColor.withValues(alpha: 0.25),
                    borderColor: event.tierColor,
                    borderStrokeWidth: 3,
                  )).toList(),
                ),
                PolylineLayer(
                  polylines: [
                    if (_currentPath.isNotEmpty)
                      Polyline(
                        points: _currentPath,
                        color: Theme.of(context).colorScheme.primary,
                        strokeWidth: 5,
                        strokeCap: StrokeCap.round,
                        strokeJoin: StrokeJoin.round,
                      ),
                  ],
                ),
                if (_currentLocation != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _currentLocation!,
                        width: 40,
                        height: 40,
                        child: AnimatedBuilder(
                          animation: _pulseAnimation,
                          builder: (context, child) {
                            return Transform.scale(
                              scale: _pulseAnimation.value,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Container(
                                    width: 14,
                                    height: 14,
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
                                  ),
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
                          Text('${_totalScore.toStringAsFixed(1)} m²', style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
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
                        icon: const Icon(Icons.leaderboard, color: Colors.white),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const ScoreboardScreen()),
                          ).then((_) {
                            // Reload data when returning from scoreboard in case we add delete features later
                            _loadData();
                          });
                        },
                        tooltip: 'Command Center',
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
              ],
            ),
          ),

          // Custom Capture Button
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
  }
}

