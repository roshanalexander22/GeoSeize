import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/spotify_service.dart';

class FloatingMusicPlayer extends StatefulWidget {
  final VoidCallback onDismissed;

  const FloatingMusicPlayer({
    super.key,
    required this.onDismissed,
  });

  @override
  State<FloatingMusicPlayer> createState() => _FloatingMusicPlayerState();
}

class _FloatingMusicPlayerState extends State<FloatingMusicPlayer> with SingleTickerProviderStateMixin {
  final SpotifyService _spotifyService = SpotifyService();
  
  // Track positioning coordinates
  double? _x;
  double? _y;
  bool _isDragging = false;
  
  // Size constraints
  final double _cardWidth = 260.0;
  final double _cardHeight = 72.0;

  // Rotation animation for the album art spin
  late AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    );

    // Sync rotation controller to music playing status
    _spotifyService.isPlaying.addListener(_handlePlayStateChanged);
    if (_spotifyService.isPlaying.value) {
      _rotationController.repeat();
    }
  }

  @override
  void dispose() {
    _spotifyService.isPlaying.removeListener(_handlePlayStateChanged);
    _rotationController.dispose();
    super.dispose();
  }

  void _handlePlayStateChanged() {
    if (!mounted) return;
    if (_spotifyService.isPlaying.value) {
      _rotationController.repeat();
    } else {
      _rotationController.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final screenHeight = mediaQuery.size.height;

    // Initialize position at bottom-center (above Begin Capture button) on first build
    if (_x == null || _y == null) {
      _x = (screenWidth - _cardWidth) / 2;
      _y = screenHeight - 200.0;
    }

    return ValueListenableBuilder<SpotifyTrack?>(
      valueListenable: _spotifyService.currentTrack,
      builder: (context, track, _) {
        if (track == null) return const SizedBox.shrink();

        return AnimatedPositioned(
          duration: _isDragging ? Duration.zero : const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          left: _x,
          top: _y,
          width: _cardWidth,
          height: _cardHeight,
          child: GestureDetector(
            onPanStart: (_) {
              setState(() {
                _isDragging = true;
              });
            },
            onPanUpdate: (details) {
              setState(() {
                _x = (_x ?? 0.0) + details.delta.dx;
                _y = (_y ?? 0.0) + details.delta.dy;
              });
            },
            onPanEnd: (details) {
              setState(() {
                _isDragging = false;
              });
              _checkDismissal(screenWidth, screenHeight);
            },
            child: _buildPlayerCard(track, Theme.of(context).colorScheme.secondary),
          ),
        );
      },
    );
  }

  void _checkDismissal(double screenWidth, double screenHeight) {
    final double leftLimit = -80.0;
    final double rightLimit = screenWidth - _cardWidth + 80.0;
    final double bottomLimit = screenHeight - _cardHeight + 40.0;
    final double topLimit = -20.0;

    final double curX = _x ?? 0.0;
    final double curY = _y ?? 0.0;

    // If dragged off-screen, trigger complete dismiss and stop music
    if (curX < leftLimit || curX > rightLimit || curY > bottomLimit || curY < topLimit) {
      // Animate off-screen completely
      setState(() {
        if (curX < leftLimit) _x = -_cardWidth - 20.0;
        else if (curX > rightLimit) _x = screenWidth + 20.0;
        else if (curY > bottomLimit) _y = screenHeight + 20.0;
        else if (curY < topLimit) _y = -_cardHeight - 20.0;
      });

      // Stop music and notify parent
      Future.delayed(const Duration(milliseconds: 250), () {
        _spotifyService.stop();
        widget.onDismissed();
      });
    } else {
      // Clamp position within safe boundaries of the screen
      final double safeX = curX.clamp(16.0, screenWidth - _cardWidth - 16.0);
      final double safeY = curY.clamp(80.0, screenHeight - _cardHeight - 100.0);
      setState(() {
        _x = safeX;
        _y = safeY;
      });
    }
  }

  Widget _buildPlayerCard(SpotifyTrack track, Color accent) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.15),
            blurRadius: 15,
            spreadRadius: 2,
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Row(
          children: [
            const SizedBox(width: 10),
            // Draggable drag handle icon
            const Icon(Icons.drag_indicator, color: Colors.white30, size: 20),
            const SizedBox(width: 4),

            // Spinning Album Art
            RotationTransition(
              turns: _rotationController,
              child: Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: accent.withValues(alpha: 0.5), width: 1.0),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: Image.network(
                    track.albumArtUrl ?? 'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?w=50',
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: Colors.white10,
                      child: const Icon(Icons.music_note, color: Colors.white30, size: 20),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),

            // Track details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    track.name,
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    track.artist,
                    style: const TextStyle(color: Colors.white30, fontSize: 10),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // Playback controls
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(Icons.skip_previous, color: Colors.white70, size: 22),
                  onPressed: _spotifyService.prevTrack,
                ),
                const SizedBox(width: 6),
                ValueListenableBuilder<bool>(
                  valueListenable: _spotifyService.isPlaying,
                  builder: (context, playing, _) {
                    return IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: Icon(
                        playing ? Icons.pause_circle_filled : Icons.play_circle_fill,
                        color: accent,
                        size: 32,
                      ),
                      onPressed: _spotifyService.togglePlay,
                    );
                  },
                ),
                const SizedBox(width: 6),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(Icons.skip_next, color: Colors.white70, size: 22),
                  onPressed: _spotifyService.nextTrack,
                ),
                const SizedBox(width: 10),
              ],
            )
          ],
        ),
      ),
    );
  }
}
