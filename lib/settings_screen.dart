import 'dart:ui';
import 'dart:io' show File;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'services/settings_service.dart';
import 'services/auth_service.dart';
import 'services/storage_service.dart';
import 'utils/rewards_system.dart';
import 'utils/level_system.dart';
import 'main.dart';
import 'utils/page_transitions.dart';


class SettingsScreen extends StatefulWidget {
  final double totalScore;
  const SettingsScreen({super.key, this.totalScore = 0});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SettingsService _settings = SettingsService();
  final AuthService _authService = AuthService();

  Color get _textColor => Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white;
  int get _playerLevel => LevelSystem.getLevel(widget.totalScore);

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
            const SizedBox(height: 16),
            _buildMapScaleToggle(),
            const SizedBox(height: 24),

            _buildSectionHeader('REWARDS — TERRITORY COLOR'),
            _buildColorRewardGrid(),
            const SizedBox(height: 24),

            _buildSectionHeader('REWARDS — MAP AVATAR'),
            _buildAvatarRewardGrid(),
            const SizedBox(height: 24),

            _buildSectionHeader('RECON ROUTE'),
            _buildReconColorSelector(),
            const SizedBox(height: 24),

            _buildSectionHeader('CONQUEST RESET'),
            _buildDangerZone(),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // ─── Section header ─────────────────────────────────────────────────────────
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

  // ─── Glass card ─────────────────────────────────────────────────────────────
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

  // ─── Colour reward grid ─────────────────────────────────────────────────────
  Widget _buildColorRewardGrid() {
    return _buildCard(
      child: AnimatedBuilder(
        animation: _settings.selectedColorIndex,
        builder: (context, _) {
          final selectedIdx = _settings.selectedColorIndex.value;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(RewardsSystem.colors.length, (i) {
                final reward   = RewardsSystem.colors[i];
                final unlocked = _playerLevel >= reward.requiredLevel;
                final selected = i == selectedIdx;

                return Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: GestureDetector(
                    onTap: unlocked ? () => _settings.setSelectedColorIndex(i) : null,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                color: unlocked
                                    ? reward.color
                                    : reward.color.withValues(alpha: 0.2),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: selected ? Colors.white : Colors.transparent,
                                  width: 3,
                                ),
                                boxShadow: selected
                                    ? [BoxShadow(color: reward.color.withValues(alpha: 0.6), blurRadius: 14, spreadRadius: 2)]
                                    : [],
                              ),
                              child: selected
                                  ? const Icon(Icons.check, color: Colors.white, size: 22)
                                  : null,
                            ),
                            if (!unlocked)
                              Container(
                                width: 52, height: 52,
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.55),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.lock, color: Colors.white70, size: 20),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          reward.name,
                          style: TextStyle(
                            color: unlocked ? _textColor.withValues(alpha: 0.8) : _textColor.withValues(alpha: 0.3),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (!unlocked)
                          Text(
                            'LVL ${reward.requiredLevel}',
                            style: const TextStyle(color: Colors.amber, fontSize: 9, fontWeight: FontWeight.bold),
                          ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          );
        },
      ),
    );
  }

  // ─── Avatar reward grid ─────────────────────────────────────────────────────
  Widget _buildAvatarRewardGrid() {
    return _buildCard(
      child: AnimatedBuilder(
        animation: Listenable.merge([_settings.selectedAvatarIndex, _settings.profileImagePath]),
        builder: (context, _) {
          final selectedIdx = _settings.selectedAvatarIndex.value;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(RewardsSystem.avatars.length, (i) {
                final reward   = RewardsSystem.avatars[i];
                final unlocked = _playerLevel >= reward.requiredLevel;
                final selected = i == selectedIdx;

                Widget preview;
                if (reward.emoji != null) {
                  preview = Text(reward.emoji!, style: TextStyle(fontSize: 24, color: unlocked ? null : Colors.white30));
                } else if (reward.id == 'default') {
                  preview = Container(
                    width: 24, height: 24,
                    decoration: BoxDecoration(
                      color: unlocked ? Theme.of(context).colorScheme.secondary : Colors.white24,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  );
                } else if (reward.id == 'profile') {
                  final localPath   = _settings.profileImagePath.value;
                  final googlePhoto = _authService.currentUser?.photoURL;
                  Widget img;
                  if (localPath != null && localPath.isNotEmpty && !kIsWeb) {
                    img = Image.file(File(localPath), fit: BoxFit.cover);
                  } else if (googlePhoto != null && googlePhoto.isNotEmpty) {
                    img = Image.network(googlePhoto, fit: BoxFit.cover);
                  } else {
                    img = const Icon(Icons.person, color: Colors.white, size: 20);
                  }
                  preview = SizedBox(width: 28, height: 28, child: ClipOval(child: img));
                } else {
                  preview = Icon(reward.icon ?? Icons.circle, color: unlocked ? Colors.white : Colors.white30, size: 24);
                }

                return Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: GestureDetector(
                    onTap: unlocked ? () => _settings.setSelectedAvatarIndex(i) : null,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: 56, height: 56,
                              decoration: BoxDecoration(
                                color: selected
                                    ? Theme.of(context).colorScheme.secondary.withValues(alpha: 0.25)
                                    : _textColor.withValues(alpha: unlocked ? 0.06 : 0.03),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: selected
                                      ? Theme.of(context).colorScheme.secondary
                                      : _textColor.withValues(alpha: 0.1),
                                  width: 2,
                                ),
                                boxShadow: selected
                                    ? [BoxShadow(color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.4), blurRadius: 10)]
                                    : [],
                              ),
                              child: Center(child: preview),
                            ),
                            if (!unlocked)
                              Container(
                                width: 56, height: 56,
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.55),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(Icons.lock, color: Colors.white70, size: 20),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          reward.name,
                          style: TextStyle(
                            color: unlocked ? _textColor.withValues(alpha: 0.8) : _textColor.withValues(alpha: 0.3),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (!unlocked)
                          Text(
                            'LVL ${reward.requiredLevel}',
                            style: const TextStyle(color: Colors.amber, fontSize: 9, fontWeight: FontWeight.bold),
                          ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          );
        },
      ),
    );
  }

  // ─── Recon colour selector (unchanged) ──────────────────────────────────────
  Widget _buildReconColorSelector() {
    final List<Color> reconColors = [
      Colors.cyanAccent,
      Colors.greenAccent,
      Colors.amberAccent,
      Colors.redAccent,
      Colors.purpleAccent,
      Colors.pinkAccent,
      Colors.deepOrangeAccent,
      Colors.white,
    ];
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('RECON ROUTE COLOR', style: TextStyle(color: _textColor, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          SizedBox(
            height: 50,
            child: AnimatedBuilder(
              animation: _settings.reconColor,
              builder: (context, _) {
                final selected = _settings.reconColor.value;
                return ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: reconColors.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, i) {
                    final color    = reconColors[i];
                    final isSel    = color.value == selected.value;
                    return GestureDetector(
                      onTap: () => _settings.setReconColor(color),
                      child: Container(
                        width: 50,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(color: isSel ? Colors.white : Colors.transparent, width: 3),
                          boxShadow: isSel ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 10, spreadRadius: 2)] : [],
                        ),
                        child: isSel ? const Icon(Icons.check, color: Colors.white) : null,
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

  // ─── Profile section ────────────────────────────────────────────────────────
  Widget _buildProfileSection() {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: _pickImage,
                child: AnimatedBuilder(
                  animation: _settings.profileImagePath,
                  builder: (context, _) {
                    final localPath    = _settings.profileImagePath.value;
                    final googlePhoto  = _authService.currentUser?.photoURL;
                    Widget imageWidget;
                    if (localPath != null && localPath.isNotEmpty && !kIsWeb) {
                      imageWidget = Image.file(File(localPath), fit: BoxFit.cover);
                    } else if (googlePhoto != null && googlePhoto.isNotEmpty) {
                      imageWidget = Image.network(googlePhoto, fit: BoxFit.cover);
                    } else {
                      imageWidget = Icon(Icons.account_circle, color: Theme.of(context).colorScheme.secondary, size: 40);
                    }
                    return Container(
                      width: 50, height: 50,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Theme.of(context).colorScheme.secondary, width: 2),
                      ),
                      child: Stack(children: [
                        Positioned.fill(child: ClipOval(child: imageWidget)),
                        Positioned(
                          right: 0, bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, shape: BoxShape.circle),
                            child: Icon(Icons.edit, size: 12, color: Theme.of(context).colorScheme.secondary),
                          ),
                        ),
                      ]),
                    );
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FutureBuilder<String?>(
                      future: _authService.getUsername(_authService.currentUser?.uid ?? ''),
                      builder: (context, snapshot) => Text(
                        snapshot.data?.toUpperCase() ?? 'AGENT',
                        style: TextStyle(color: _textColor, fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                    ),
                    Text(
                      _authService.currentUser?.email ?? 'Unknown User',
                      style: TextStyle(color: _textColor.withValues(alpha: 0.54), fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Level $_playerLevel · ${LevelSystem.getRankTitle(_playerLevel)}',
                      style: TextStyle(color: Theme.of(context).colorScheme.secondary, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: _changeUsername,
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.5)),
              foregroundColor: Theme.of(context).colorScheme.secondary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('CHANGE CALLSIGN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: ElevatedButton(
                onPressed: () async {
                  await _authService.signOut();
                  if (mounted) {
                    Navigator.of(context).pushAndRemoveUntil(FadePageRoute(page: const AuthWrapper()), (r) => false);
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
          ]),
        ],
      ),
    );
  }

  // ─── Theme / Map / Unit helpers ─────────────────────────────────────────────
  Widget _buildThemeToggle() {
    return _buildCard(
      child: AnimatedBuilder(
        animation: _settings.isDarkTheme,
        builder: (context, _) => SwitchListTile(
          title: Text('Cyberpunk Dark Mode', style: TextStyle(color: _textColor, fontWeight: FontWeight.bold)),
          subtitle: Text('Toggle between dark and light app themes', style: TextStyle(color: _textColor.withValues(alpha: 0.54), fontSize: 12)),
          value: _settings.isDarkTheme.value,
          activeColor: Theme.of(context).colorScheme.secondary,
          contentPadding: EdgeInsets.zero,
          onChanged: (v) => _settings.setDarkTheme(v),
        ),
      ),
    );
  }

  Widget _buildMapStyleSelector() {
    return _buildCard(
      child: AnimatedBuilder(
        animation: _settings.mapStyle,
        builder: (context, _) {
          final cur = _settings.mapStyle.value;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Map Style', style: TextStyle(color: _textColor, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              _radio('Tactical Dark',  SettingsService.mapStyleDark,      cur),
              _radio('Recon Light',    SettingsService.mapStyleLight,     cur),
              _radio('Standard Map',   SettingsService.mapStyleStreet,    cur),
              _radio('Satellite View', SettingsService.mapStyleSatellite, cur),
            ],
          );
        },
      ),
    );
  }

  Widget _radio(String label, String val, String group) {
    return Theme(
      data: Theme.of(context).copyWith(unselectedWidgetColor: _textColor.withValues(alpha: 0.54)),
      child: RadioListTile<String>(
        title: Text(label, style: TextStyle(color: _textColor.withValues(alpha: 0.7))),
        value: val,
        groupValue: group,
        activeColor: Theme.of(context).colorScheme.secondary,
        contentPadding: EdgeInsets.zero,
        onChanged: (v) { if (v != null) _settings.setMapStyle(v); },
      ),
    );
  }

  // ─── Danger zone / Reset ────────────────────────────────────────────────────
  Widget _buildDangerZone() {
    final storage = StorageService();

    Future<void> doReset(String label, Future<void> Function() action) async {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Theme.of(ctx).colorScheme.surface,
          title: Text(label.toUpperCase(),
              style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 14)),
          content: Text(
            'This will permanently delete all conquest data for the selected period. This cannot be undone.',
            style: TextStyle(color: _textColor.withValues(alpha: 0.8), fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('CANCEL', style: TextStyle(color: _textColor.withValues(alpha: 0.7))),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              child: const Text('RESET', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
      if (confirm != true || !mounted) return;
      await action();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$label complete.'),
            backgroundColor: Colors.redAccent.withValues(alpha: 0.9),
          ),
        );
      }
    }

    final now = DateTime.now();
    final startOfToday    = DateTime(now.year, now.month, now.day);
    final startOfWeek     = startOfToday.subtract(Duration(days: now.weekday - 1));
    final startOfMonth    = DateTime(now.year, now.month, 1);

    final resets = [
      (
        icon: Icons.today,
        label: "Reset Today's Conquest",
        action: () => storage.resetEventsByDateRange(startOfToday, now),
      ),
      (
        icon: Icons.date_range,
        label: "Reset This Week's Conquest",
        action: () => storage.resetEventsByDateRange(startOfWeek, now),
      ),
      (
        icon: Icons.calendar_month,
        label: "Reset This Month's Conquest",
        action: () => storage.resetEventsByDateRange(startOfMonth, now),
      ),
      (
        icon: Icons.delete_forever,
        label: "Reset All-Time Conquest",
        action: () => storage.wipeData(),
      ),
    ];

    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber, color: Colors.redAccent, size: 18),
              const SizedBox(width: 8),
              Text('DANGER ZONE', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, letterSpacing: 1)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Permanently removes captured territories. Cannot be undone.',
            style: TextStyle(color: _textColor.withValues(alpha: 0.5), fontSize: 11),
          ),
          const SizedBox(height: 16),
          ...resets.map((r) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: Icon(r.icon, size: 16, color: Colors.redAccent),
                label: Text(r.label,
                    style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.redAccent, width: 1),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  backgroundColor: Colors.redAccent.withValues(alpha: 0.04),
                ),
                onPressed: () => doReset(r.label, r.action),
              ),
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildUnitToggle() {
    return _buildCard(
      child: AnimatedBuilder(
        animation: _settings.useMetric,
        builder: (context, _) => SwitchListTile(
          title: Text('Use Metric System', style: TextStyle(color: _textColor, fontWeight: FontWeight.bold)),
          subtitle: Text('Meters/KM vs Feet/Miles', style: TextStyle(color: _textColor.withValues(alpha: 0.54), fontSize: 12)),
          value: _settings.useMetric.value,
          activeColor: Theme.of(context).colorScheme.secondary,
          contentPadding: EdgeInsets.zero,
          onChanged: (v) => _settings.setUseMetric(v),
        ),
      ),
    );
  }

  Widget _buildMapScaleToggle() {
    return _buildCard(
      child: AnimatedBuilder(
        animation: _settings.showMapScale,
        builder: (context, _) => SwitchListTile(
          title: Text('Show Map Scale', style: TextStyle(color: _textColor, fontWeight: FontWeight.bold)),
          subtitle: Text('Display "1 cm = X m" scale indicator on map', style: TextStyle(color: _textColor.withValues(alpha: 0.54), fontSize: 12)),
          value: _settings.showMapScale.value,
          activeColor: Theme.of(context).colorScheme.secondary,
          contentPadding: EdgeInsets.zero,
          onChanged: (v) => _settings.setShowMapScale(v),
        ),
      ),
    );
  }

  // ─── Dialogs ────────────────────────────────────────────────────────────────
  Future<void> _changeUsername() async {
    final controller = TextEditingController();
    final newUsername = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).colorScheme.surface,
        title: Text('CHANGE CALLSIGN', style: TextStyle(color: _textColor, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          style: TextStyle(color: _textColor),
          decoration: InputDecoration(
            hintText: 'New Callsign',
            hintStyle: TextStyle(color: _textColor.withValues(alpha: 0.5)),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: _textColor.withValues(alpha: 0.2))),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Theme.of(ctx).colorScheme.secondary)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text('CANCEL', style: TextStyle(color: _textColor.withValues(alpha: 0.7)))),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            style: ElevatedButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.primary),
            child: const Text('SAVE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (newUsername != null && newUsername.isNotEmpty) {
      final user = _authService.currentUser;
      if (user != null) {
        await _authService.setUsername(user.uid, newUsername);
        setState(() {});
      }
    }
  }

  Future<void> _deleteAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).colorScheme.surface,
        title: const Text('DELETE ACCOUNT', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to permanently delete your account? This action cannot be undone.', style: TextStyle(color: _textColor)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text('CANCEL', style: TextStyle(color: _textColor.withValues(alpha: 0.7)))),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent), child: const Text('DELETE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await _authService.deleteAccount();
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(FadePageRoute(page: const AuthWrapper()), (r) => false);
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to delete account. Please logout, login again, and retry.'), backgroundColor: Colors.redAccent));
        }
      }
    }
  }

  Future<void> _pickImage() async {
    final picker     = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) await _settings.setProfileImagePath(pickedFile.path);
  }
}
