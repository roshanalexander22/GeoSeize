import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  
  final List<LatLng> _currentPath = [];
  final List<List<LatLng>> _territories = [];
  
  StreamSubscription<Position>? _positionStream;
  bool _isCapturing = false;
  LatLng? _currentLocation;
  
  final Distance _distance = const Distance();
  
  @override
  void initState() {
    super.initState();
    _checkPermissionsAndGetLocation();
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
        
        setState(() {
          _territories.add(loopPoints);
          _currentPath.clear();
          _currentPath.add(newPoint);
        });
        
        _showSuccessMessage();
        break;
      }
    }
  }

  void _showSuccessMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Zone Captured! 🚀',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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
