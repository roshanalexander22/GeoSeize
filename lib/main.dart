import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import 'map_screen.dart';
import 'loading_screen.dart';
import 'login_screen.dart';
import 'username_setup_screen.dart';
import 'services/settings_service.dart';
import 'services/auth_service.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';

void main() async {
  // Ensure we can set system UI overlays
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Preferences
  await SettingsService().init();

  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  // Auth logic is handled via StreamBuilder down the tree
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
    return ValueListenableBuilder<bool>(
      valueListenable: SettingsService().isDarkTheme,
      builder: (context, isDark, child) {
        return MaterialApp(
          title: 'GeoSeize',
          debugShowCheckedModeBanner: false,
          theme: isDark ? _buildDarkTheme(context) : _buildLightTheme(context),
          home: const AuthWrapper(),
        );
      },
    );
  }

  ThemeData _buildDarkTheme(BuildContext context) {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF0D0D12),
      textTheme: GoogleFonts.rajdhaniTextTheme(
        Theme.of(context).textTheme.apply(bodyColor: Colors.white, displayColor: Colors.white),
      ),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF6C63FF),
        secondary: Color(0xFF00E5FF),
        surface: Color(0xFF1E1E28),
      ),
    );
  }

  ThemeData _buildLightTheme(BuildContext context) {
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: const Color(0xFFF5F5FA),
      textTheme: GoogleFonts.rajdhaniTextTheme(
        Theme.of(context).textTheme.apply(bodyColor: Colors.black87, displayColor: Colors.black),
      ),
      colorScheme: const ColorScheme.light(
        primary: Color(0xFF6C63FF),
        secondary: Color(0xFF00B8D4),
        surface: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.black87),
      ),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFF0D0D12),
            body: Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF))),
          );
        }

        final user = snapshot.data;
        if (user == null) {
          return const LoginScreen();
        }

        // User is logged in, check if they have a username
        return FutureBuilder<bool>(
          future: AuthService().hasUsername(user.uid),
          builder: (context, usernameSnapshot) {
            if (usernameSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                backgroundColor: Color(0xFF0D0D12),
                body: Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF))),
              );
            }

            final hasUsername = usernameSnapshot.data ?? false;
            if (!hasUsername) {
              return UsernameSetupScreen(user: user);
            }

            return const LoadingScreen();
          },
        );
      },
    );
  }
}
