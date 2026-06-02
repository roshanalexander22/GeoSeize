import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'services/storage_service.dart';
import 'utils/geo_calculator.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  final StorageService _storageService = StorageService();
  
  final List<LatLng> _currentPath = [];
  List<List<LatLng>> _territories = [];
  double _totalScore = 0.0;
  
  StreamSubscription<Position>? _positionStream;
  bool _isCapturing = false;
  LatLng? _currentLocation;
  
  final Distance _distance = const Distance();
  
  @override
  void initState() {
    super.initState();
    _loadData();
    _checkPermissionsAndGetLocation();
  }

  Future<void> _loadData() async {
    final loadedTerritories = await _storageService.loadTerritories();
    final loadedScore = await _storageService.loadTotalArea();
    setState(() {
      _territories = loadedTerritories;
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
        
        setState(() {
          _territories.add(loopPoints);
          _totalScore += areaCaptured;
          _currentPath.clear();
          _currentPath.add(newPoint);
        });
        
        _storageService.saveTerritories(_territories);
        _storageService.saveTotalArea(_totalScore);
        
        _showSuccessMessage(areaCaptured);
        break;
      }
    }
  }

  void _showSuccessMessage(double area) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Zone Captured! 🚀 (+${area.toStringAsFixed(1)} m²)',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        backgroundColor: Colors.cyanAccent.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GeoSeize'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              await _storageService.wipeData();
              if (mounted) {
                setState(() {
                  _territories.clear();
                  _totalScore = 0.0;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Stats reset! Time to conquer anew!'), backgroundColor: Colors.deepPurple),
                );
              }
            },
            tooltip: 'Reset Stats',
          ),
        ],
      ),
      body: Stack(
        children: [
          if (_currentLocation == null)
            const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.deepPurpleAccent),
                  SizedBox(height: 16),
                  Text('Acquiring GPS Location...', style: TextStyle(color: Colors.white70)),
                ],
              ),
            )
          else
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _currentLocation!,
                initialZoom: 16.0,
              ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.geoseize',
              ),
              PolygonLayer(
                polygons: _territories.map((territory) => Polygon(
                  points: territory,
                  color: Colors.cyanAccent.withValues(alpha: 0.4),
                  borderColor: Colors.cyanAccent,
                  borderStrokeWidth: 2,
                )).toList(),
              ),
              PolylineLayer(
                polylines: [
                  if (_currentPath.isNotEmpty)
                    Polyline(
                      points: _currentPath,
                      color: Colors.deepPurpleAccent,
                      strokeWidth: 4,
                    ),
                ],
              ),
              if (_currentLocation != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _currentLocation!,
                      width: 20,
                      height: 20,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.redAccent,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E).withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.5), width: 1.5),
                boxShadow: const [
                  BoxShadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, 4)),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('CONQUERED AREA', style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                      const SizedBox(height: 4),
                      Text('${_totalScore.toStringAsFixed(1)} m²', style: const TextStyle(color: Colors.cyanAccent, fontSize: 20, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('ZONES', style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                      const SizedBox(height: 4),
                      Text('${_territories.length}', style: const TextStyle(color: Colors.deepPurpleAccent, fontSize: 20, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 30,
            left: 0,
            right: 0,
            child: Center(
              child: FloatingActionButton.extended(
                onPressed: _toggleCapture,
                backgroundColor: _isCapturing ? Colors.redAccent : Colors.deepPurpleAccent,
                icon: Icon(_isCapturing ? Icons.stop : Icons.play_arrow),
                label: Text(
                  _isCapturing ? 'Stop Capturing' : 'Start Capturing',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
