import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _authService = AuthService();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSignUp = false;
  bool _isLoading = false;
  String _errorMessage = '';

  Future<void> _submit() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    if (_emailController.text.trim().isEmpty || _passwordController.text.trim().isEmpty) {
      setState(() {
        _errorMessage = 'Please enter your email and password.';
        _isLoading = false;
      });
      return;
    }

    try {
      if (_isSignUp) {
        await _authService.signUpWithEmail(
          _emailController.text.trim(),
          _passwordController.text.trim(),
        );
      } else {
        await _authService.signInWithEmail(
          _emailController.text.trim(),
          _passwordController.text.trim(),
        );
      }
      // main.dart StreamBuilder will catch the auth state change and navigate
    } on FirebaseAuthException catch (e) {
      setState(() {
        _errorMessage = e.message ?? 'An error occurred. Please try again.';
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'An unexpected error occurred.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      await _authService.signInWithGoogle();
      // main.dart StreamBuilder handles navigation
    } catch (e) {
      setState(() {
        _errorMessage = 'Google Sign-In failed. Check your connection or Firebase config.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'GEOSEIZE',
                textAlign: TextAlign.center,
                style: GoogleFonts.rajdhani(
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'ACCESS TERMINAL',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: textColor.withValues(alpha: 0.5),
                  letterSpacing: 2,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 48),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                style: TextStyle(color: textColor),
                decoration: InputDecoration(
                  labelText: 'EMAIL',
                  labelStyle: TextStyle(color: textColor.withValues(alpha: 0.5), letterSpacing: 1),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: textColor.withValues(alpha: 0.2)),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: primaryColor),
                  ),
                  prefixIcon: Icon(Icons.email_outlined, color: textColor.withValues(alpha: 0.5)),
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _passwordController,
                obscureText: true,
                style: TextStyle(color: textColor),
                decoration: InputDecoration(
                  labelText: 'PASSWORD',
                  labelStyle: TextStyle(color: textColor.withValues(alpha: 0.5), letterSpacing: 1),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: textColor.withValues(alpha: 0.2)),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: primaryColor),
                  ),
                  prefixIcon: Icon(Icons.lock_outline, color: textColor.withValues(alpha: 0.5)),
                ),
              ),
              if (_errorMessage.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text(
                  _errorMessage,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 48),
              _isLoading
                  ? Center(child: CircularProgressIndicator(color: primaryColor))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ElevatedButton(
                          onPressed: _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: Text(
                            _isSignUp ? 'CREATE ACCOUNT' : 'LOGIN',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: _signInWithGoogle,
                          icon: Icon(Icons.g_mobiledata, size: 24, color: textColor),
                          label: Text(
                            'CONTINUE WITH GOOGLE',
                            style: TextStyle(
                              color: textColor,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            side: BorderSide(color: textColor.withValues(alpha: 0.2)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                        const SizedBox(height: 24),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _isSignUp = !_isSignUp;
                              _errorMessage = '';
                            });
                          },
                          child: Text(
                            _isSignUp
                                ? 'Already have an account? Login'
                                : 'No account? Create one',
                            style: TextStyle(color: textColor.withValues(alpha: 0.7)),
                          ),
                        ),
                      ],
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
