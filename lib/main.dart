import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import 'map_screen.dart';
import 'loading_screen.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';

void main() async {
  // Ensure we can set system UI overlays
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  // Sign in anonymously if not already signed in
  try {
    if (FirebaseAuth.instance.currentUser == null) {
      await FirebaseAuth.instance.signInAnonymously();
    }
  } catch (e) {
    print("Failed to sign in anonymously. Is Anonymous Auth enabled in Firebase Console? Error: $e");
  }
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent, // Make status bar transparent
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const GeoSeizeApp());
}

class GeoSeizeApp extends StatelessWidget {
  const GeoSeizeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GeoSeize',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0D0D12), // Deep, dark background
        textTheme: GoogleFonts.rajdhaniTextTheme(
          Theme.of(context).textTheme.apply(bodyColor: Colors.white, displayColor: Colors.white),
        ),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6C63FF), // Sleek vibrant purple
          secondary: Color(0xFF00E5FF), // Cyber cyan
          surface: Color(0xFF1E1E28),
        ),
      ),
      home: const LoadingScreen(),
    );
  }
}
