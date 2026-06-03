import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'services/settings_service.dart';
import 'services/auth_service.dart';
import 'main.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SettingsService _settings = SettingsService();
  final AuthService _authService = AuthService();

  final List<Color> _availableColors = [
    const Color(0xFF6C63FF), // Default Primary
    Colors.cyanAccent,
    Colors.redAccent,
    Colors.greenAccent,
    Colors.amberAccent,
    Colors.deepOrangeAccent,
    Colors.purpleAccent,
    Colors.pinkAccent,
  ];

  Color get _textColor => Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'COMMAND CENTER',
          style: GoogleFonts.rajdhani(
            fontWeight: FontWeight.bold,
            letterSpacing: 3,
            color: Theme.of(context).colorScheme.secondary,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: _textColor.withValues(alpha: 0.7)),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('PROFILE'),
            _buildProfileSection(),
            const SizedBox(height: 24),

            _buildSectionHeader('APPEARANCE'),
            _buildThemeToggle(),
            const SizedBox(height: 24),
            
            _buildSectionHeader('MAP & NAVIGATION'),
            _buildMapStyleSelector(),
            const SizedBox(height: 16),
            _buildUnitToggle(),
            const SizedBox(height: 24),

            _buildSectionHeader('CUSTOMIZATION'),
            _buildColorSelector(
              title: 'CAPTURE ROUTE COLOR',
              notifier: _settings.captureColor,
              onColorSelected: _settings.setCaptureColor,
            ),
            const SizedBox(height: 16),
            _buildColorSelector(
              title: 'RECON ROUTE COLOR',
              notifier: _settings.reconColor,
              onColorSelected: _settings.setReconColor,
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 8.0, bottom: 16.0),
      child: Text(
        title,
        style: TextStyle(
          color: _textColor.withValues(alpha: 0.5),
          fontWeight: FontWeight.bold,
          letterSpacing: 2,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildCard({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _textColor.withValues(alpha: 0.05)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: child,
          ),
        ),
      ),
    );
  }
  Future<void> _changeUsername() async {
    final controller = TextEditingController();
    final newUsername = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text('CHANGE CALLSIGN', style: TextStyle(color: _textColor, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          style: TextStyle(color: _textColor),
          decoration: InputDecoration(
            hintText: 'New Callsign',
            hintStyle: TextStyle(color: _textColor.withValues(alpha: 0.5)),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: _textColor.withValues(alpha: 0.2))),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Theme.of(context).colorScheme.secondary)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('CANCEL', style: TextStyle(color: _textColor.withValues(alpha: 0.7))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary),
            child: const Text('SAVE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (newUsername != null && newUsername.isNotEmpty) {
      final user = _authService.currentUser;
      if (user != null) {
        await _authService.setUsername(user.uid, newUsername);
        setState(() {}); // trigger rebuild to show new username
      }
    }
  }

  Future<void> _deleteAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: const Text('DELETE ACCOUNT', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
        content: Text(
          'Are you sure you want to permanently delete your account? This action cannot be undone.',
          style: TextStyle(color: _textColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('CANCEL', style: TextStyle(color: _textColor.withValues(alpha: 0.7))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('DELETE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _authService.deleteAccount();
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const AuthWrapper()),
            (route) => false,
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to delete account. Please logout, login again, and retry.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    }
  }

  Widget _buildProfileSection() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.account_circle, color: Theme.of(context).colorScheme.secondary, size: 40),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FutureBuilder<String?>(
                      future: _authService.getUsername(_authService.currentUser?.uid ?? ''),
                      builder: (context, snapshot) {
                        return Text(
                          snapshot.data?.toUpperCase() ?? 'AGENT',
                          style: TextStyle(color: _textColor, fontWeight: FontWeight.bold, fontSize: 18),
                        );
                      },
                    ),
                    Text(
                      _authService.currentUser?.email ?? 'Unknown User',
                      style: TextStyle(color: _textColor.withValues(alpha: 0.54), fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _changeUsername,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.5)),
                    foregroundColor: Theme.of(context).colorScheme.secondary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('CHANGE CALLSIGN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () async {
                    await _authService.signOut();
                    if (mounted) {
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const AuthWrapper()),
                        (route) => false,
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor: _textColor.withValues(alpha: 0.7),
                    elevation: 0,
                    side: BorderSide(color: _textColor.withValues(alpha: 0.2)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('LOGOUT', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _deleteAccount,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent.withValues(alpha: 0.1),
                    foregroundColor: Colors.redAccent,
                    elevation: 0,
                    side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.3)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('DELETE', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildThemeToggle() {
    return _buildCard(
      child: ValueListenableBuilder<bool>(
        valueListenable: _settings.isDarkTheme,
        builder: (context, isDark, _) {
          return SwitchListTile(
            title: Text('Cyberpunk Dark Mode', style: TextStyle(color: _textColor, fontWeight: FontWeight.bold)),
            subtitle: Text('Toggle between dark and light app themes', style: TextStyle(color: _textColor.withValues(alpha: 0.54), fontSize: 12)),
            value: isDark,
            activeColor: Theme.of(context).colorScheme.secondary,
            contentPadding: EdgeInsets.zero,
            onChanged: (value) => _settings.setDarkTheme(value),
          );
        },
      ),
    );
  }

  Widget _buildMapStyleSelector() {
    return _buildCard(
      child: ValueListenableBuilder<String>(
        valueListenable: _settings.mapStyle,
        builder: (context, currentStyle, _) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Map Style', style: TextStyle(color: _textColor, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              _buildRadioOption('Tactical Dark', SettingsService.mapStyleDark, currentStyle, _settings.setMapStyle),
              _buildRadioOption('Recon Light', SettingsService.mapStyleLight, currentStyle, _settings.setMapStyle),
              _buildRadioOption('Standard Map', SettingsService.mapStyleStreet, currentStyle, _settings.setMapStyle),
            ],
          );
        },
      ),
    );
  }

  Widget _buildRadioOption(String title, String value, String groupValue, Function(String) onChanged) {
    return Theme(
      data: Theme.of(context).copyWith(
        unselectedWidgetColor: _textColor.withValues(alpha: 0.54),
      ),
      child: RadioListTile<String>(
        title: Text(title, style: TextStyle(color: _textColor.withValues(alpha: 0.7))),
        value: value,
        groupValue: groupValue,
        activeColor: Theme.of(context).colorScheme.secondary,
        contentPadding: EdgeInsets.zero,
        onChanged: (val) {
          if (val != null) onChanged(val);
        },
      ),
    );
  }

  Widget _buildUnitToggle() {
    return _buildCard(
      child: ValueListenableBuilder<bool>(
        valueListenable: _settings.useMetric,
        builder: (context, useMetric, _) {
          return SwitchListTile(
            title: Text('Use Metric System', style: TextStyle(color: _textColor, fontWeight: FontWeight.bold)),
            subtitle: Text('Meters/KM vs Feet/Miles', style: TextStyle(color: _textColor.withValues(alpha: 0.54), fontSize: 12)),
            value: useMetric,
            activeColor: Theme.of(context).colorScheme.secondary,
            contentPadding: EdgeInsets.zero,
            onChanged: (value) => _settings.setUseMetric(value),
          );
        },
      ),
    );
  }

  Widget _buildColorSelector({
    required String title,
    required ValueNotifier<Color> notifier,
    required Function(Color) onColorSelected,
  }) {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: _textColor, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          SizedBox(
            height: 50,
            child: ValueListenableBuilder<Color>(
              valueListenable: notifier,
              builder: (context, selectedColor, _) {
                return ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _availableColors.length,
                  separatorBuilder: (context, index) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final color = _availableColors[index];
                    final isSelected = color.value == selectedColor.value;
                    return GestureDetector(
                      onTap: () => onColorSelected(color),
                      child: Container(
                        width: 50,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected ? _textColor : Colors.transparent,
                            width: 3,
                          ),
                          boxShadow: isSelected
                              ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 10, spreadRadius: 2)]
                              : [],
                        ),
                        child: isSelected ? const Icon(Icons.check, color: Colors.white) : null,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
