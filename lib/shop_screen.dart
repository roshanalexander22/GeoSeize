import 'dart:ui';
import 'package:flutter/material.dart';
import 'models/shop_item.dart';
import 'services/progression_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ShopScreen — full screen coin-based item shop
// ─────────────────────────────────────────────────────────────────────────────
class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> with TickerProviderStateMixin {
  late TabController _tabController;
  final ProgressionService _prog = ProgressionService.instance;

  int _coins = 0;
  List<String> _owned = [];
  Map<String, String?> _equipped = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final coins   = await _prog.getCoins();
    final owned   = await _prog.getPurchasedItems();
    final equipped = await _prog.getEquipped();
    if (!mounted) return;
    setState(() {
      _coins    = coins;
      _owned    = owned;
      _equipped = equipped;
      _isLoading = false;
    });
  }

  Future<void> _handleBuy(ShopItem item) async {
    if (_owned.contains(item.id)) {
      // Already owned → equip
      await _equip(item);
      return;
    }
    if (_coins < item.price) {
      _showToast('Not enough coins!', isError: true);
      return;
    }
    // Confirm purchase dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _BuyConfirmDialog(item: item, coins: _coins),
    );
    if (confirmed != true) return;

    final success = await _prog.purchaseItem(item);
    if (success) {
      await _loadData();
      _showToast('Purchased ${item.name}!');
      await _equip(item);
    } else {
      await _loadData();
      _showToast('Purchase failed.', isError: true);
    }
  }

  Future<void> _equip(ShopItem item) async {
    final slot = item.category.name;
    final currentEquipped = _equipped[slot];
    if (currentEquipped == item.id) {
      // Already equipped → unequip
      await _prog.equipItem(slot, null);
    } else {
      await _prog.equipItem(slot, item.id);
    }
    await _loadData();
    _showToast('Equipped ${item.name}!');
  }

  void _showToast(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: isError ? Colors.redAccent : const Color(0xFF00E5FF),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final secColor = Theme.of(context).colorScheme.secondary;
    final priColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: const Color(0xFF080810),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E0E1A),
        elevation: 0,
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.storefront_outlined, size: 20),
              SizedBox(width: 8),
              Text('GEAR SHOP', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2)),
            ],
          ),
        ),
        centerTitle: true,
        actions: [
          // Coin balance display
          Container(
            margin: const EdgeInsets.only(right: 16, top: 10, bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                Colors.amber.withValues(alpha: 0.2),
                Colors.amber.withValues(alpha: 0.05),
              ]),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🪙', style: TextStyle(fontSize: 14)),
                const SizedBox(width: 4),
                _isLoading
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.amber))
                    : Text(
                        '$_coins',
                        style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
              ],
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: secColor,
          labelColor: secColor,
          unselectedLabelColor: Colors.white30,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 10, letterSpacing: 1.0),
          tabs: const [
            Tab(icon: Icon(Icons.palette_outlined, size: 18), text: 'COLORS'),
            Tab(icon: Icon(Icons.location_on_outlined, size: 18), text: 'MARKERS'),
            Tab(icon: Icon(Icons.circle_outlined, size: 18), text: 'FRAMES'),
            Tab(icon: Icon(Icons.view_stream_outlined, size: 18), text: 'TITLEBARS'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildGrid(ShopCatalogue.colors, secColor, priColor),
                _buildGrid(ShopCatalogue.markers, secColor, priColor),
                _buildFrameGrid(ShopCatalogue.frames, secColor, priColor),
                _buildTitlebarGrid(ShopCatalogue.titlebars, secColor, priColor),
              ],
            ),
    );
  }

  // ── Color / Marker grid ──────────────────────────────────────────────────────
  Widget _buildGrid(List<ShopItem> items, Color sec, Color pri) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.85,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) => _ShopCard(
        item: items[i],
        isOwned: _owned.contains(items[i].id),
        isEquipped: _equipped[items[i].category.name] == items[i].id,
        coins: _coins,
        onTap: () => _handleBuy(items[i]),
        secColor: sec,
      ),
    );
  }

  // ── Frame grid ───────────────────────────────────────────────────────────────
  Widget _buildFrameGrid(List<ShopItem> items, Color sec, Color pri) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.85,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) => _FrameCard(
        item: items[i],
        isOwned: _owned.contains(items[i].id),
        isEquipped: _equipped['frame'] == items[i].id,
        coins: _coins,
        onTap: () => _handleBuy(items[i]),
        secColor: sec,
      ),
    );
  }

  // ── Titlebar grid ────────────────────────────────────────────────────────────
  Widget _buildTitlebarGrid(List<ShopItem> items, Color sec, Color pri) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) => _TitlebarCard(
        item: items[i],
        isOwned: _owned.contains(items[i].id),
        isEquipped: _equipped['titlebar'] == items[i].id,
        coins: _coins,
        onTap: () => _handleBuy(items[i]),
        secColor: sec,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Generic shop card (colors + markers)
// ─────────────────────────────────────────────────────────────────────────────
class _ShopCard extends StatelessWidget {
  final ShopItem item;
  final bool isOwned;
  final bool isEquipped;
  final int coins;
  final VoidCallback onTap;
  final Color secColor;

  const _ShopCard({
    required this.item,
    required this.isOwned,
    required this.isEquipped,
    required this.coins,
    required this.onTap,
    required this.secColor,
  });

  @override
  Widget build(BuildContext context) {
    final canAfford = coins >= item.price;
    final borderColor = isEquipped
        ? secColor
        : item.isPremium
            ? Colors.amber.withValues(alpha: 0.6)
            : Colors.white12;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isEquipped
              ? secColor.withValues(alpha: 0.08)
              : const Color(0xFF0E0E1A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: isEquipped ? 2 : 1),
          boxShadow: item.isPremium
              ? [BoxShadow(color: Colors.amber.withValues(alpha: 0.08), blurRadius: 12)]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Premium badge
            if (item.isPremium)
              Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                ),
                child: const Text('PREMIUM', style: TextStyle(color: Colors.amber, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 1)),
              ),
            const SizedBox(height: 4),
            // Preview
            if (item.previewColor != null)
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  color: item.previewColor,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: item.previewColor!.withValues(alpha: 0.5), blurRadius: 16)],
                ),
              )
            else if (item.previewEmoji != null)
              Text(item.previewEmoji!, style: const TextStyle(fontSize: 40))
            else if (item.previewIcon != null)
              Icon(item.previewIcon, size: 40, color: secColor),
            const SizedBox(height: 10),
            Text(item.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13), textAlign: TextAlign.center),
            const SizedBox(height: 4),
            // Price / Status
            if (isOwned)
              _StatusChip(label: isEquipped ? 'EQUIPPED ✓' : 'EQUIP', color: isEquipped ? secColor : Colors.white54)
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('🪙', style: TextStyle(fontSize: 12)),
                  const SizedBox(width: 3),
                  Text(
                    '${item.price}',
                    style: TextStyle(
                      color: canAfford ? Colors.amber : Colors.redAccent,
                      fontWeight: FontWeight.bold, fontSize: 14,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Frame card
// ─────────────────────────────────────────────────────────────────────────────
class _FrameCard extends StatelessWidget {
  final ShopItem item;
  final bool isOwned;
  final bool isEquipped;
  final int coins;
  final VoidCallback onTap;
  final Color secColor;

  const _FrameCard({
    required this.item, required this.isOwned, required this.isEquipped,
    required this.coins, required this.onTap, required this.secColor,
  });

  @override
  Widget build(BuildContext context) {
    final colors = item.frameColors ?? [Colors.white24, Colors.white10];
    final canAfford = coins >= item.price;
    final borderColor = isEquipped ? secColor : item.isPremium ? Colors.amber.withValues(alpha: 0.6) : Colors.white12;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: const Color(0xFF0E0E1A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: isEquipped ? 2 : 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (item.isPremium)
              Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                ),
                child: const Text('PREMIUM', style: TextStyle(color: Colors.amber, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 1)),
              ),
            const SizedBox(height: 4),
            // Frame preview — ring with gradient
            Container(
              width: 60, height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(colors: [...colors, colors.first]),
                boxShadow: [BoxShadow(color: colors.first.withValues(alpha: 0.5), blurRadius: 16)],
              ),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Container(
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF0E0E1A)),
                  child: const Icon(Icons.person, color: Colors.white38, size: 28),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(item.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13), textAlign: TextAlign.center),
            const SizedBox(height: 4),
            if (isOwned)
              _StatusChip(label: isEquipped ? 'EQUIPPED ✓' : 'EQUIP', color: isEquipped ? secColor : Colors.white54)
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('🪙', style: TextStyle(fontSize: 12)),
                  const SizedBox(width: 3),
                  Text('${item.price}', style: TextStyle(color: canAfford ? Colors.amber : Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 14)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Titlebar card (list style)
// ─────────────────────────────────────────────────────────────────────────────
class _TitlebarCard extends StatelessWidget {
  final ShopItem item;
  final bool isOwned;
  final bool isEquipped;
  final int coins;
  final VoidCallback onTap;
  final Color secColor;

  const _TitlebarCard({
    required this.item, required this.isOwned, required this.isEquipped,
    required this.coins, required this.onTap, required this.secColor,
  });

  @override
  Widget build(BuildContext context) {
    final bgColors = item.frameColors ?? [const Color(0xFF1A1A2E), const Color(0xFF0D0D1A)];
    final canAfford = coins >= item.price;
    final borderColor = isEquipped ? secColor : item.isPremium ? Colors.amber.withValues(alpha: 0.6) : Colors.white12;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: isEquipped ? 2 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Titlebar preview
            Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: bgColors),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
              ),
              child: Text(
                item.titlebarLabel ?? item.name,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 1.5),
              ),
            ),
            // Info row
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF0E0E1A),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(15)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(item.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                            if (item.isPremium) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.amber.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                                ),
                                child: const Text('PREMIUM', style: TextStyle(color: Colors.amber, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 1)),
                              ),
                            ],
                          ],
                        ),
                        if (item.description != null)
                          Text(item.description!, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (isOwned)
                    _StatusChip(label: isEquipped ? 'EQUIPPED ✓' : 'EQUIP', color: isEquipped ? secColor : Colors.white54)
                  else
                    Row(
                      children: [
                        const Text('🪙', style: TextStyle(fontSize: 14)),
                        const SizedBox(width: 4),
                        Text('${item.price}', style: TextStyle(color: canAfford ? Colors.amber : Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Status chip (EQUIPPED / EQUIP)
// ─────────────────────────────────────────────────────────────────────────────
class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Purchase confirm dialog
// ─────────────────────────────────────────────────────────────────────────────
class _BuyConfirmDialog extends StatelessWidget {
  final ShopItem item;
  final int coins;
  const _BuyConfirmDialog({required this.item, required this.coins});

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
      child: Dialog(
        backgroundColor: const Color(0xFF0E0E1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: Colors.white12)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('CONFIRM PURCHASE', style: TextStyle(color: Colors.white54, fontSize: 11, letterSpacing: 2, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Text(item.name, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
              if (item.description != null) ...[
                const SizedBox(height: 8),
                Text(item.description!, style: const TextStyle(color: Colors.white38, fontSize: 12), textAlign: TextAlign.center),
              ],
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('🪙', style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 6),
                  Text('${item.price} coins', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 18)),
                ],
              ),
              const SizedBox(height: 4),
              Text('Balance after: ${coins - item.price} 🪙', style: const TextStyle(color: Colors.white38, fontSize: 12)),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('CANCEL', style: TextStyle(color: Colors.white38)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('BUY NOW', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
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
