import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:math' as math;
import 'map_screen.dart';

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  String _statusMessage = "INITIALIZING...";

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(); // Continuously spin in one direction

    _initializeApp();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _initializeApp() async {
    // 1. Check Location Services
    setState(() => _statusMessage = "CHECKING SATELLITE UPLINK...");
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    while (!serviceEnabled) {
      setState(() => _statusMessage = "WAITING FOR GPS HARDWARE...");
      await Future.delayed(const Duration(seconds: 2));
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
    }

    // 2. Check Permissions
    setState(() => _statusMessage = "REQUESTING CLEARANCE...");
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() => _statusMessage = "CLEARANCE DENIED. CANNOT PROCEED.");
        return; // Halt
      }
    }

    if (permission == LocationPermission.deniedForever) {
      setState(() => _statusMessage = "CLEARANCE PERMANENTLY DENIED. CHECK SETTINGS.");
      return; // Halt
    }

    // 3. Acquire first GPS lock
    setState(() => _statusMessage = "ACQUIRING POSITION FIX...");
    try {
      await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );
    } catch (e) {
      // If it times out or fails, we might just try to fall back or keep waiting
      // But usually getCurrentPosition handles it. If it fails, let's just proceed 
      // and let the map handle the stream.
      print("Warning: initial GPS fix took too long or failed: $e");
    }

    // 4. All Green, proceed to MapScreen
    setState(() => _statusMessage = "ACCESS GRANTED.");
    await Future.delayed(const Duration(milliseconds: 500)); // Brief pause for dramatic effect

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => const MapScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 800),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D12),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Spinning Globe Animation
            AnimatedBuilder(
              animation: _animationController,
              builder: (context, child) {
                return Transform.rotate(
                  angle: _animationController.value * 2 * math.pi,
                  child: Container(
                    width: 150,
                    height: 150,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00E5FF).withOpacity(0.5),
                          blurRadius: 40,
                          spreadRadius: 10,
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        'assets/app_icon.png',
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 60),
            // Title
            Text(
              'GEOSEIZE',
              style: GoogleFonts.rajdhani(
                fontSize: 48,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 8,
                shadows: [
                  Shadow(
                    color: const Color(0xFF6C63FF).withOpacity(0.8),
                    blurRadius: 20,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Status Message
            Text(
              _statusMessage,
              style: GoogleFonts.rajdhani(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF00E5FF),
                letterSpacing: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
