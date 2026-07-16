import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Shop item categories
// ─────────────────────────────────────────────────────────────────────────────
enum ShopCategory { color, marker, frame, titlebar }

// ─────────────────────────────────────────────────────────────────────────────
// ShopItem model
// ─────────────────────────────────────────────────────────────────────────────
class ShopItem {
  final String id;
  final String name;
  final ShopCategory category;
  final int price; // in coins
  final String? description;
  final bool isPremium; // shows special gold border in the shop

  // Visual preview data
  final Color? previewColor;   // for color items
  final String? previewEmoji;  // for marker items
  final IconData? previewIcon; // for marker items without emoji
  final List<Color>? frameColors; // gradient colours for frames
  final String? titlebarLabel;    // text shown in titlebar preview

  const ShopItem({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    this.description,
    this.isPremium = false,
    this.previewColor,
    this.previewEmoji,
    this.previewIcon,
    this.frameColors,
    this.titlebarLabel,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Shop catalogue — single source of truth
// ─────────────────────────────────────────────────────────────────────────────
class ShopCatalogue {
  ShopCatalogue._();

  // ── Zone Colors ──────────────────────────────────────────────────────────────
  static const List<ShopItem> colors = [
    ShopItem(
      id: 'col_violet',
      name: 'Deep Violet',
      category: ShopCategory.color,
      price: 150,
      description: 'A rich violet for your captured zones.',
      previewColor: Color(0xFF7B2FBE),
    ),
    ShopItem(
      id: 'col_teal',
      name: 'Teal Ops',
      category: ShopCategory.color,
      price: 150,
      description: 'Tactical teal zone color.',
      previewColor: Color(0xFF00B4A2),
    ),
    ShopItem(
      id: 'col_coral',
      name: 'Coral Strike',
      category: ShopCategory.color,
      price: 200,
      description: 'Warm coral that stands out on any map.',
      previewColor: Color(0xFFFF6B6B),
    ),
    ShopItem(
      id: 'col_lime',
      name: 'Toxic Lime',
      category: ShopCategory.color,
      price: 200,
      description: 'Radioactive lime green zone fill.',
      previewColor: Color(0xFFB5FF00),
    ),
    ShopItem(
      id: 'col_crimson',
      name: 'Blood Crimson',
      category: ShopCategory.color,
      price: 350,
      isPremium: true,
      description: 'Command respect with deep crimson territory.',
      previewColor: Color(0xFFCC0033),
    ),
    ShopItem(
      id: 'col_chrome',
      name: 'Chrome Silver',
      category: ShopCategory.color,
      price: 450,
      isPremium: true,
      description: 'Metallic chrome finish on all your zones.',
      previewColor: Color(0xFFC0C0C0),
    ),
    ShopItem(
      id: 'col_obsidian',
      name: 'Obsidian Dark',
      category: ShopCategory.color,
      price: 600,
      isPremium: true,
      description: 'The darkest zone on the map. Pure dominance.',
      previewColor: Color(0xFF1A1A2E),
    ),
    ShopItem(
      id: 'col_solar',
      name: 'Solar Flare',
      category: ShopCategory.color,
      price: 750,
      isPremium: true,
      description: 'Blazing yellow-orange. Impossible to ignore.',
      previewColor: Color(0xFFFF9500),
    ),
  ];

  // ── Markers ──────────────────────────────────────────────────────────────────
  static const List<ShopItem> markers = [
    ShopItem(
      id: 'mrk_flag',
      name: 'War Flag',
      category: ShopCategory.marker,
      price: 200,
      description: 'Plant your flag on every zone.',
      previewEmoji: '🚩',
    ),
    ShopItem(
      id: 'mrk_skull2',
      name: 'Toxic Skull',
      category: ShopCategory.marker,
      price: 200,
      description: 'Emit danger on the map.',
      previewEmoji: '☠️',
    ),
    ShopItem(
      id: 'mrk_thunder',
      name: 'Thunder Bolt',
      category: ShopCategory.marker,
      price: 250,
      description: 'Strike fear with every capture.',
      previewEmoji: '⚡',
    ),
    ShopItem(
      id: 'mrk_gem',
      name: 'Gem Stone',
      category: ShopCategory.marker,
      price: 300,
      description: 'Rare and valuable — just like your territory.',
      previewEmoji: '💎',
    ),
    ShopItem(
      id: 'mrk_alien',
      name: 'Alien Invader',
      category: ShopCategory.marker,
      price: 400,
      isPremium: true,
      description: 'Not from around here. Captures zones across galaxies.',
      previewEmoji: '👾',
    ),
    ShopItem(
      id: 'mrk_phantom',
      name: 'Phantom',
      category: ShopCategory.marker,
      price: 500,
      isPremium: true,
      description: 'Ghost your enemies. Invisible dominance.',
      previewEmoji: '👻',
    ),
    ShopItem(
      id: 'mrk_god',
      name: 'God Mode',
      category: ShopCategory.marker,
      price: 800,
      isPremium: true,
      description: 'The rarest marker. Flex your elite status.',
      previewEmoji: '⚜️',
    ),
  ];

  // ── Profile Frames ───────────────────────────────────────────────────────────
  static const List<ShopItem> frames = [
    ShopItem(
      id: 'frm_blue',
      name: 'Azure Pulse',
      category: ShopCategory.frame,
      price: 300,
      description: 'Glowing blue ring around your avatar.',
      frameColors: [Color(0xFF00E5FF), Color(0xFF0066FF)],
    ),
    ShopItem(
      id: 'frm_green',
      name: 'Matrix Code',
      category: ShopCategory.frame,
      price: 300,
      description: 'Neon green hacker aesthetic frame.',
      frameColors: [Color(0xFF00FF88), Color(0xFF00AA44)],
    ),
    ShopItem(
      id: 'frm_purple',
      name: 'Nebula Ring',
      category: ShopCategory.frame,
      price: 400,
      description: 'Deep space purple galaxy frame.',
      frameColors: [Color(0xFF6C63FF), Color(0xFFE040FB)],
    ),
    ShopItem(
      id: 'frm_fire',
      name: 'Inferno',
      category: ShopCategory.frame,
      price: 500,
      isPremium: true,
      description: 'Burning fire gradient that blazes on screen.',
      frameColors: [Color(0xFFFF4500), Color(0xFFFFD700)],
    ),
    ShopItem(
      id: 'frm_gold',
      name: 'Champion Gold',
      category: ShopCategory.frame,
      price: 650,
      isPremium: true,
      description: 'Only for champions. Pure gold frame.',
      frameColors: [Color(0xFFFFD700), Color(0xFFB8860B)],
    ),
    ShopItem(
      id: 'frm_diamond',
      name: 'Diamond Aura',
      category: ShopCategory.frame,
      price: 800,
      isPremium: true,
      description: 'Shimmering diamond — the rarest frame in GeoSeize.',
      frameColors: [Color(0xFFE0F7FA), Color(0xFF80DEEA), Color(0xFF4DD0E1)],
    ),
  ];

  // ── Titlebars ────────────────────────────────────────────────────────────────
  static const List<ShopItem> titlebars = [
    ShopItem(
      id: 'ttl_scout',
      name: 'Scout Tag',
      category: ShopCategory.titlebar,
      price: 250,
      description: 'Minimalist scout title displayed on your stats.',
      titlebarLabel: '— SCOUT —',
      frameColors: [Color(0xFF2A2A4A), Color(0xFF1A1A2E)],
    ),
    ShopItem(
      id: 'ttl_tactical',
      name: 'Tactical Ops',
      category: ShopCategory.titlebar,
      price: 300,
      description: 'Military-style ops banner above your callsign.',
      titlebarLabel: '⚡ TACTICAL OPS ⚡',
      frameColors: [Color(0xFF1A2A1A), Color(0xFF0D1A0D)],
    ),
    ShopItem(
      id: 'ttl_phantom',
      name: 'Phantom Elite',
      category: ShopCategory.titlebar,
      price: 450,
      isPremium: true,
      description: 'Ghost-tier title. You can\'t be stopped.',
      titlebarLabel: '👻 PHANTOM ELITE 👻',
      frameColors: [Color(0xFF1A0D2E), Color(0xFF0D0714)],
    ),
    ShopItem(
      id: 'ttl_warlord',
      name: 'Warlord',
      category: ShopCategory.titlebar,
      price: 550,
      isPremium: true,
      description: 'Command all zones. Warlord status.',
      titlebarLabel: '⚔️ WARLORD ⚔️',
      frameColors: [Color(0xFF2A0A0A), Color(0xFF1A0505)],
    ),
    ShopItem(
      id: 'ttl_emperor',
      name: 'Emperor\'s Crown',
      category: ShopCategory.titlebar,
      price: 750,
      isPremium: true,
      description: 'The highest honor. Reserved for legends.',
      titlebarLabel: '👑 EMPEROR 👑',
      frameColors: [Color(0xFF2A2000), Color(0xFF1A1500)],
    ),
    ShopItem(
      id: 'ttl_god',
      name: 'GeoGod',
      category: ShopCategory.titlebar,
      price: 1000,
      isPremium: true,
      description: 'Rarest title in GeoSeize. Flex to the world.',
      titlebarLabel: '⚜️  G E O G O D  ⚜️',
      frameColors: [Color(0xFF1A0A2E), Color(0xFF2A0A4E)],
    ),
  ];

  static List<ShopItem> get all => [...colors, ...markers, ...frames, ...titlebars];
}
