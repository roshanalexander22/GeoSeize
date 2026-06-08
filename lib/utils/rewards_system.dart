import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Colour reward
// ─────────────────────────────────────────────────────────────────────────────
class ColorReward {
  final Color color;
  final String name;
  final int requiredLevel;

  const ColorReward({
    required this.color,
    required this.name,
    required this.requiredLevel,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Avatar / marker reward
// ─────────────────────────────────────────────────────────────────────────────
class AvatarReward {
  /// The string key stored in SharedPreferences (matches SettingsService.markerType).
  final String id;
  final String name;

  /// Emoji or null (null = use the custom widget below)
  final String? emoji;

  /// If emoji is null, this icon is rendered as the preview
  final IconData? icon;

  final int requiredLevel;

  const AvatarReward({
    required this.id,
    required this.name,
    this.emoji,
    this.icon,
    required this.requiredLevel,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// RewardsSystem — single source of truth
// ─────────────────────────────────────────────────────────────────────────────
class RewardsSystem {
  RewardsSystem._();

  // ── Colours ─────────────────────────────────────────────────────────────────
  static const List<ColorReward> colors = [
    ColorReward(color: Color(0xFF00E5FF), name: 'Cyan',         requiredLevel: 1),
    ColorReward(color: Color(0xFF6C63FF), name: 'Nebula',        requiredLevel: 2),
    ColorReward(color: Color(0xFFFF007F), name: 'Neon Pink',     requiredLevel: 3),
    ColorReward(color: Color(0xFFFFD700), name: 'Gold',          requiredLevel: 5),
    ColorReward(color: Color(0xFF00FF88), name: 'Matrix Green',  requiredLevel: 7),
    ColorReward(color: Color(0xFFFF4500), name: 'Inferno',       requiredLevel: 10),
    ColorReward(color: Color(0xFF00BFFF), name: 'Ice Blue',      requiredLevel: 13),
    ColorReward(color: Color(0xFFFF6B35), name: 'Ember',         requiredLevel: 16),
    ColorReward(color: Color(0xFFE040FB), name: 'Plasma',        requiredLevel: 20),
    ColorReward(color: Color(0xFFFFFFFF), name: 'Arctic White',  requiredLevel: 25),
  ];

  // ── Avatars ──────────────────────────────────────────────────────────────────
  static const List<AvatarReward> avatars = [
    AvatarReward(id: 'default',     name: 'Pulse Dot',     icon: Icons.circle,           requiredLevel: 1),
    AvatarReward(id: 'profile',     name: 'Photo',         icon: Icons.account_circle,   requiredLevel: 2),
    AvatarReward(id: '🎯',          name: 'Target',        emoji: '🎯',                  requiredLevel: 3),
    AvatarReward(id: '⚔️',          name: 'Swords',        emoji: '⚔️',                  requiredLevel: 5),
    AvatarReward(id: '👑',          name: 'Crown',         emoji: '👑',                  requiredLevel: 7),
    AvatarReward(id: '💀',          name: 'Skull',         emoji: '💀',                  requiredLevel: 10),
    AvatarReward(id: '🚀',          name: 'Rocket',        emoji: '🚀',                  requiredLevel: 13),
    AvatarReward(id: '🌟',          name: 'Star',          emoji: '🌟',                  requiredLevel: 16),
    AvatarReward(id: '🔥',          name: 'Fire',          emoji: '🔥',                  requiredLevel: 20),
    AvatarReward(id: '🐉',          name: 'Dragon',        emoji: '🐉',                  requiredLevel: 25),
  ];

  /// Whether a reward is available at the given level.
  static bool isColorUnlocked(int index, int playerLevel) =>
      index >= 0 && index < colors.length && playerLevel >= colors[index].requiredLevel;

  static bool isAvatarUnlocked(int index, int playerLevel) =>
      index >= 0 && index < avatars.length && playerLevel >= avatars[index].requiredLevel;

  /// Find the index of a colour by its Flutter Color value.
  static int indexOfColor(Color color) =>
      colors.indexWhere((c) => c.color.value == color.value);

  /// Find the index of an avatar by its id string.
  static int indexOfAvatar(String id) =>
      avatars.indexWhere((a) => a.id == id);
}
