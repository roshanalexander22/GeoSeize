"""
Patch map_screen.dart:
  1. Fix satellite crash — remove dynamic maxZoom from MapOptions, enforce via addPostFrameCallback
  2. Add _showHeatMap state variable
  3. Import heat_map_layer.dart
  4. Add HeatMapLayer inside FlutterMap children
  5. Add heat-map toggle button to the expandable sidebar
  6. Add HeatMapLegend Positioned widget when active
"""

with open('lib/map_screen.dart', 'r', encoding='utf-8') as f:
    src = f.read()

# ── 1. Add heat_map import ────────────────────────────────────────────────────
src = src.replace(
    "import 'services/auth_service.dart';",
    "import 'services/auth_service.dart';\nimport 'layers/heat_map_layer.dart';",
    1
)

# ── 2. Add _showHeatMap state variable after _sidebarExpanded ─────────────────
src = src.replace(
    '  bool _sidebarExpanded = false; // whether the collapsible action buttons are shown',
    '  bool _sidebarExpanded = false; // whether the collapsible action buttons are shown\n  bool _showHeatMap    = false; // overlay heat map of captured zones',
    1
)

# ── 3. Fix satellite crash: remove dynamic maxZoom, keep it null always ───────
src = src.replace(
    '                maxZoom: mapStyle == SettingsService.mapStyleSatellite ? _satelliteMaxZoom() : null,',
    '                // maxZoom enforced programmatically in onPositionChanged\n                // (dynamic maxZoom in MapOptions crashes flutter_map during panning)\n                maxZoom: null,',
    1
)

# ── 4. In onPositionChanged, enforce satellite zoom programmatically ──────────
old_pos = '''                onPositionChanged: (camera, hasGesture) {
                  final newZoom = camera.zoom;
                  final newLat  = camera.center.latitude;
                  final panGesture = hasGesture && _followingUser;
                  if (panGesture || newZoom != _mapZoom || (newLat - _mapLat).abs() > 0.0001) {
                    setState(() {
                      _mapZoom = newZoom;
                      _mapLat  = newLat;
                      if (panGesture) _followingUser = false;
                    });
                  }
                },'''

new_pos = '''                onPositionChanged: (camera, hasGesture) {
                  final newZoom = camera.zoom;
                  final newLat  = camera.center.latitude;
                  final panGesture = hasGesture && _followingUser;

                  // ── Satellite zoom guard (no more dynamic maxZoom crash) ───
                  if (mapStyle == SettingsService.mapStyleSatellite) {
                    final maxZ = _satelliteMaxZoom();
                    if (newZoom > maxZ) {
                      // Clamp AFTER the current frame so it doesn't conflict
                      // with an ongoing gesture recognizer.
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) _mapController.move(camera.center, maxZ);
                      });
                    }
                  }

                  if (panGesture || newZoom != _mapZoom || (newLat - _mapLat).abs() > 0.0001) {
                    setState(() {
                      _mapZoom = newZoom;
                      _mapLat  = newLat;
                      if (panGesture) _followingUser = false;
                    });
                  }
                },'''

src = src.replace(old_pos, new_pos, 1)

# ── 5. Add HeatMapLayer inside FlutterMap children after RepaintBoundary ──────
old_polygon = '''                RepaintBoundary(
                  child: PolygonLayer(
                    polygons: _events.map((event) => Polygon(
                      points: event.polygon,
                      color: playerColor.withValues(alpha: 0.25),
                      borderColor: playerColor,
                      borderStrokeWidth: 3,
                    )).toList(),
                  ),
                ),'''

new_polygon = '''                RepaintBoundary(
                  child: PolygonLayer(
                    polygons: _events.map((event) => Polygon(
                      points: event.polygon,
                      color: playerColor.withValues(alpha: 0.25),
                      borderColor: playerColor,
                      borderStrokeWidth: 3,
                    )).toList(),
                  ),
                ),
                // ── Heat Map overlay ─────────────────────────────────────────
                if (_showHeatMap)
                  HeatMapLayer(
                    points: _events.map((e) => GeoCalculator.getVisualCenter(e.polygon)).toList(),
                    radius: (40.0 + _mapZoom * 2.5).clamp(40.0, 120.0),
                  ),'''

src = src.replace(old_polygon, new_polygon, 1)

# ── 6. Add heat-map toggle button to expandable sidebar ───────────────────────
old_recon_btn = '''                            // Recon / Planning mode
                            _buildSidebarBtn(
                              icon: Icons.explore,
                              color: _isPlanningMode
                                  ? recColor.withValues(alpha: 0.2)
                                  : Colors.black.withValues(alpha: 0.3),
                              iconColor: _isPlanningMode ? recColor : Colors.white70,
                              border: Border.all(
                                color: _isPlanningMode ? recColor : Colors.white.withValues(alpha: 0.1),
                              ),
                              onPressed: _togglePlanningMode,
                              tooltip: 'Recon Mode',
                            ),'''

new_recon_btn = '''                            // Recon / Planning mode
                            _buildSidebarBtn(
                              icon: Icons.explore,
                              color: _isPlanningMode
                                  ? recColor.withValues(alpha: 0.2)
                                  : Colors.black.withValues(alpha: 0.3),
                              iconColor: _isPlanningMode ? recColor : Colors.white70,
                              border: Border.all(
                                color: _isPlanningMode ? recColor : Colors.white.withValues(alpha: 0.1),
                              ),
                              onPressed: _togglePlanningMode,
                              tooltip: 'Recon Mode',
                            ),
                            const SizedBox(height: 12),
                            // Heat Map toggle
                            _buildSidebarBtn(
                              icon: Icons.local_fire_department,
                              color: _showHeatMap
                                  ? Colors.deepOrange.withValues(alpha: 0.25)
                                  : Colors.black.withValues(alpha: 0.3),
                              iconColor: _showHeatMap ? Colors.deepOrangeAccent : Colors.white70,
                              border: Border.all(
                                color: _showHeatMap
                                    ? Colors.deepOrangeAccent.withValues(alpha: 0.7)
                                    : Colors.white.withValues(alpha: 0.1),
                              ),
                              onPressed: () => setState(() => _showHeatMap = !_showHeatMap),
                              tooltip: 'Heat Map',
                            ),'''

src = src.replace(old_recon_btn, new_recon_btn, 1)

# ── 7. Add HeatMapLegend positioned widget near the scale bar ─────────────────
old_scale_positioned = '''          // Map scale indicator — bottom-left, Google Maps style
          if (settings.showMapScale.value)
            Positioned(
              bottom: 16,
              left: 16,
              child: _buildMapScaleWidget(settings.useMetric.value),
            ),'''

new_scale_positioned = '''          // Map scale indicator — bottom-left, Google Maps style
          if (settings.showMapScale.value)
            Positioned(
              bottom: 16,
              left: 16,
              child: _buildMapScaleWidget(settings.useMetric.value),
            ),

          // Heat map legend (shown when heat map is active)
          if (_showHeatMap)
            Positioned(
              bottom: settings.showMapScale.value ? 60 : 16,
              left: 16,
              child: const HeatMapLegend(),
            ),'''

src = src.replace(old_scale_positioned, new_scale_positioned, 1)

with open('lib/map_screen.dart', 'w', encoding='utf-8') as f:
    f.write(src)

# ── Verify all patches ────────────────────────────────────────────────────────
checks = [
    ('heat_map import', "import 'layers/heat_map_layer.dart';"),
    ('_showHeatMap state', '_showHeatMap    = false;'),
    ('maxZoom null', 'maxZoom: null,'),
    ('No dynamic satellite maxZoom', 'mapStyle == SettingsService.mapStyleSatellite ? _satelliteMaxZoom() : null' not in src),
    ('postFrameCallback fix', '_mapController.move(camera.center, maxZ);'),
    ('HeatMapLayer in FlutterMap', 'HeatMapLayer('),
    ('Heat map radius scaling', '_mapZoom * 2.5').clamp(40.0, 120.0'),
    ('Sidebar heat button', "Icons.local_fire_department,"),
    ('HeatMapLegend positioned', 'HeatMapLegend()'),
]

all_ok = True
for name, check in checks:
    if isinstance(check, bool):
        ok = check
    else:
        ok = check in src
    status = 'OK' if ok else 'MISSING'
    if not ok:
        all_ok = False
    print(f'  [{status}] {name}')

print()
print('All checks passed!' if all_ok else 'SOME CHECKS FAILED — see above')
print(f'File size: {len(src)} bytes, {src.count(chr(10))} lines')
