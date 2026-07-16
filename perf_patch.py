#!/usr/bin/env python3
"""
Performance patch for map_screen.dart:
- Replace setState-based marker animation with ValueNotifier (stops 60fps full-tree rebuilds)
- Add RepaintBoundary around PolygonLayer (caches expensive polygon repaints)
- Increase distanceFilter from 2→3 to match the 3m gate already in _onNewGpsPoint
"""
import re

with open('lib/map_screen.dart', 'r', encoding='utf-8') as f:
    src = f.read()

original_len = len(src)

# ── 1. Add ValueNotifier field after _displayLocation declaration ────────────
old_field = '  LatLng? _displayLocation; // interpolated position used for rendering\n  bool _followingUser = true; // whether the camera auto-follows the marker'
new_field  = '  // Performance: ValueNotifier so only the MarkerLayer rebuilds (not full tree)\n  final ValueNotifier<LatLng?> _displayLocationNotifier = ValueNotifier<LatLng?>(null);\n  LatLng? get _displayLocation => _displayLocationNotifier.value;\n  set _displayLocation(LatLng? v) => _displayLocationNotifier.value = v;\n  bool _followingUser = true; // whether the camera auto-follows the marker'
src = src.replace(old_field, new_field, 1)

# ── 2. In marker animation listener: replace setState with direct notifier update ──
# Current code:
#   setState(() { _displayLocation = pos; });
# We DON'T need to call setState at all — the ValueNotifier drives the rebuild.
# But we still need the camera follow.  Remove the setState wrapper.
old_anim_listener = '''    _markerAnimController!.addListener(() {
      if (!mounted) return;
      final lat = _animatedLat?.value;
      final lng = _animatedLng?.value;
      if (lat != null && lng != null) {
        final pos = LatLng(lat, lng);
        setState(() { _displayLocation = pos; });
        // Only move the camera if the user hasn't manually panned away'''
new_anim_listener = '''    _markerAnimController!.addListener(() {
      if (!mounted) return;
      final lat = _animatedLat?.value;
      final lng = _animatedLng?.value;
      if (lat != null && lng != null) {
        final pos = LatLng(lat, lng);
        // Update notifier directly — only the ValueListenableBuilder in the
        // MarkerLayer rebuilds, NOT the whole screen (was 60fps setState before)
        _displayLocationNotifier.value = pos;
        // Only move the camera if the user hasn't manually panned away'''
src = src.replace(old_anim_listener, new_anim_listener, 1)

# ── 3. Dispose the ValueNotifier in dispose() ────────────────────────────────
old_dispose = '  @override\n  void dispose() {\n    SettingsService().mapStyle.removeListener(_onMapStyleChanged);\n    _positionStream?.cancel();\n    _pulseController.dispose();\n    _markerAnimController?.dispose();\n    super.dispose();\n  }'
new_dispose = '  @override\n  void dispose() {\n    SettingsService().mapStyle.removeListener(_onMapStyleChanged);\n    _positionStream?.cancel();\n    _pulseController.dispose();\n    _markerAnimController?.dispose();\n    _displayLocationNotifier.dispose();\n    super.dispose();\n  }'
src = src.replace(old_dispose, new_dispose, 1)

# ── 4. Increase distanceFilter from 2 → 3 everywhere (matches the 3m gate) ──
# There are three places with distanceFilter: 2
src = src.replace('distanceFilter: 2,', 'distanceFilter: 3,')

# ── 5. Wrap user marker MarkerLayer in ValueListenableBuilder ─────────────────
# Find the user marker section and wrap it
old_user_marker = '''                if (_displayLocation != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _displayLocation!,'''
new_user_marker = '''                ValueListenableBuilder<LatLng?>(
                  valueListenable: _displayLocationNotifier,
                  builder: (_, displayLoc, __) {
                    if (displayLoc == null) return const SizedBox.shrink();
                    return MarkerLayer(
                      markers: [
                        Marker(
                          point: displayLoc,'''
src = src.replace(old_user_marker, new_user_marker, 1)

# The MarkerLayer closes with:
#                     ],
#                   ),
# We need to add an extra closing ) for the ValueListenableBuilder builder + closing )
# Find the end of the user marker block — it ends with:
#                     ],
#                   ),
#               ],  ← this is the end of FlutterMap children
# We look for the pattern that closes the user MarkerLayer just before ]),
old_marker_close = '''                        ),
                      ),
                    ],
                  ),
              ],
            ),'''
new_marker_close = '''                        ),
                      ),
                    ],
                  );
                  },
                ),
              ],
            ),'''
src = src.replace(old_marker_close, new_marker_close, 1)

# ── 6. Wrap the PolygonLayer (captured zones) in RepaintBoundary ──────────────
# Find "PolygonLayer(" for captured zones
old_polygon_layer = '''                PolygonLayer(
                  polygons: _events.map((event) {'''
new_polygon_layer = '''                RepaintBoundary(
                  child: PolygonLayer(
                  polygons: _events.map((event) {'''
src = src.replace(old_polygon_layer, new_polygon_layer, 1)

# Find the closing of that PolygonLayer — it ends with:
#                 ),
# followed by MarkerLayer (username labels)
old_polygon_close = '''                ),
                MarkerLayer(
                  markers: _events'''
new_polygon_close = '''                ),
                ),
                MarkerLayer(
                  markers: _events'''
src = src.replace(old_polygon_close, new_polygon_close, 1)

with open('lib/map_screen.dart', 'w', encoding='utf-8') as f:
    f.write(src)

new_len = len(src)
print(f"Done! {original_len} -> {new_len} bytes (+{new_len - original_len})")

# Verify key changes
checks = [
    ('ValueNotifier field', '_displayLocationNotifier = ValueNotifier<LatLng?>'),
    ('Notifier setter', 'set _displayLocation(LatLng? v) => _displayLocationNotifier.value = v;'),
    ('No 60fps setState', '_displayLocationNotifier.value = pos;'),
    ('Dispose notifier', '_displayLocationNotifier.dispose();'),
    ('distanceFilter 3', 'distanceFilter: 3,'),
    ('ValueListenableBuilder', 'ValueListenableBuilder<LatLng?>'),
    ('RepaintBoundary polygon', 'RepaintBoundary(\n                  child: PolygonLayer('),
]
for name, pattern in checks:
    found = pattern in src
    print(f"  {'✓' if found else '✗'} {name}")
