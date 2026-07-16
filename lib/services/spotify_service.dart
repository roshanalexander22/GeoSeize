import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotify/spotify.dart' as spotify_api;
import 'package:audioplayers/audioplayers.dart';

class SpotifyTrack {
  final String id;
  final String name;
  final String artist;
  final String album;
  final String? albumArtUrl;
  final Duration duration;
  final String? previewUrl;

  const SpotifyTrack({
    required this.id,
    required this.name,
    required this.artist,
    required this.album,
    this.albumArtUrl,
    required this.duration,
    this.previewUrl,
  });
}

class SpotifyPlaylist {
  final String id;
  final String name;
  final String? imageUrl;
  final int trackCount;

  const SpotifyPlaylist({
    required this.id,
    required this.name,
    this.imageUrl,
    required this.trackCount,
  });
}

class SpotifyService {
  static final SpotifyService _instance = SpotifyService._internal();
  factory SpotifyService() => _instance;
  SpotifyService._internal() {
    _loadSavedCredentials();
    _initAudioPlayer();
  }

  void _initAudioPlayer() {
    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (state == PlayerState.completed) {
        nextTrack();
      }
    });
  }

  // ValueNotifiers for audio controller state (synchronized across map player & dashboard)
  final ValueNotifier<SpotifyTrack?> currentTrack = ValueNotifier<SpotifyTrack?>(null);
  final ValueNotifier<bool> isPlaying = ValueNotifier<bool>(false);
  final ValueNotifier<List<SpotifyTrack>> queue = ValueNotifier<List<SpotifyTrack>>([]);
  int _queueIndex = 0;
  final AudioPlayer _audioPlayer = AudioPlayer();

  String? _clientId;
  String? _clientSecret;
  spotify_api.SpotifyApi? _spotifyApi;

  // Curated fallback demo tracks (energetic workout tracks with actual streaming audio urls)
  static const List<SpotifyTrack> _demoTracks = [
    SpotifyTrack(
      id: 'demo1',
      name: 'Lose Yourself',
      artist: 'Eminem',
      album: '8 Mile Soundtrack',
      albumArtUrl: 'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?w=300',
      duration: Duration(minutes: 5, seconds: 26),
      previewUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3',
    ),
    SpotifyTrack(
      id: 'demo2',
      name: 'Blinding Lights',
      artist: 'The Weeknd',
      album: 'After Hours',
      albumArtUrl: 'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?w=300',
      duration: Duration(minutes: 3, seconds: 20),
      previewUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3',
    ),
    SpotifyTrack(
      id: 'demo3',
      name: 'Eye of the Tiger',
      artist: 'Survivor',
      album: 'Rocky III',
      albumArtUrl: 'https://images.unsplash.com/photo-1508700115892-45ecd05ae2ad?w=300',
      duration: Duration(minutes: 4, seconds: 4),
      previewUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-3.mp3',
    ),
    SpotifyTrack(
      id: 'demo4',
      name: 'Till I Collapse',
      artist: 'Eminem',
      album: 'The Eminem Show',
      albumArtUrl: 'https://images.unsplash.com/photo-1517838277536-f5f99be501cd?w=300',
      duration: Duration(minutes: 4, seconds: 57),
      previewUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-4.mp3',
    ),
    SpotifyTrack(
      id: 'demo5',
      name: 'Stronger',
      artist: 'Kanye West',
      album: 'Graduation',
      albumArtUrl: 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=300',
      duration: Duration(minutes: 5, seconds: 11),
      previewUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-5.mp3',
    ),
    SpotifyTrack(
      id: 'demo6',
      name: 'Pump It',
      artist: 'Black Eyed Peas',
      album: 'Monkey Business',
      albumArtUrl: 'https://images.unsplash.com/photo-1487180142328-0c4e37023af5?w=300',
      duration: Duration(minutes: 3, seconds: 35),
      previewUrl: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-6.mp3',
    ),
  ];

  static const List<SpotifyPlaylist> _demoPlaylists = [
    SpotifyPlaylist(id: 'run_beast', name: '🏃 Running Beast Mode', imageUrl: 'https://images.unsplash.com/photo-1476480862126-209bfaa8edc8?w=300', trackCount: 45),
    SpotifyPlaylist(id: 'workout_edm', name: '⚡ Cardio High-Tempo EDM', imageUrl: 'https://images.unsplash.com/photo-1517838277536-f5f99be501cd?w=300', trackCount: 60),
    SpotifyPlaylist(id: 'pop_pacing', name: '🎧 Pop Pacing (160 BPM)', imageUrl: 'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?w=300', trackCount: 38),
  ];

  bool get isConfigured => _clientId != null && _clientSecret != null;

  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    _clientId = prefs.getString('spotify_client_id');
    _clientSecret = prefs.getString('spotify_client_secret');
    if (_clientId != null && _clientSecret != null) {
      _spotifyApi = spotify_api.SpotifyApi(
        spotify_api.SpotifyApiCredentials(_clientId!, _clientSecret!),
      );
    }
  }

  Future<void> saveCredentials(String clientId, String clientSecret) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('spotify_client_id', clientId);
    await prefs.setString('spotify_client_secret', clientSecret);
    _clientId = clientId;
    _clientSecret = clientSecret;
    _spotifyApi = spotify_api.SpotifyApi(
      spotify_api.SpotifyApiCredentials(clientId, clientSecret),
    );
  }

  Future<void> clearCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('spotify_client_id');
    await prefs.remove('spotify_client_secret');
    _clientId = null;
    _clientSecret = null;
    _spotifyApi = null;
  }

  // ── Track & Playlist Operations ──────────────────────────────────────────
  Future<List<SpotifyPlaylist>> getFeaturedPlaylists() async {
    if (!isConfigured || _spotifyApi == null) {
      return _demoPlaylists;
    }

    try {
      final playlistsPage = await _spotifyApi!.playlists.featured.first(12);
      final items = playlistsPage.items ?? [];
      return items.map((p) => SpotifyPlaylist(
        id: p.id ?? '',
        name: p.name ?? 'Untitled Playlist',
        imageUrl: p.images != null && p.images!.isNotEmpty ? p.images!.first.url : null,
        trackCount: p.tracksLink?.total ?? 0,
      )).toList();
    } catch (e) {
      print('Spotify API Error fetching playlists: $e');
      return _demoPlaylists;
    }
  }

  Future<List<SpotifyTrack>> getPlaylistTracks(String playlistId) async {
    if (!isConfigured || _spotifyApi == null || playlistId.startsWith('run_') || playlistId.startsWith('workout_') || playlistId.startsWith('pop_')) {
      return _demoTracks;
    }

    try {
      final tracks = await _spotifyApi!.playlists.getPlaylistTracks(playlistId).first(25);
      final items = tracks.items ?? [];
      return items.where((t) => t.track != null).map((t) {
        final track = t.track!;
        return SpotifyTrack(
          id: track.id ?? '',
          name: track.name ?? 'Untitled',
          artist: track.artists != null && track.artists!.isNotEmpty ? track.artists!.first.name ?? 'Unknown' : 'Unknown',
          album: track.album?.name ?? 'Single',
          albumArtUrl: track.album?.images != null && track.album!.images!.isNotEmpty ? track.album!.images!.first.url : null,
          duration: track.durationMs != null ? Duration(milliseconds: track.durationMs!) : const Duration(minutes: 3),
          previewUrl: track.previewUrl,
        );
      }).toList();
    } catch (e) {
      print('Spotify API Error fetching playlist tracks: $e');
      return _demoTracks;
    }
  }

  Future<List<SpotifyTrack>> searchTracks(String query) async {
    if (query.isEmpty) return _demoTracks;

    if (!isConfigured || _spotifyApi == null) {
      // Simulate search locally
      return _demoTracks
          .where((t) => t.name.toLowerCase().contains(query.toLowerCase()) || t.artist.toLowerCase().contains(query.toLowerCase()))
          .toList();
    }

    try {
      final searchPage = await _spotifyApi!.search.get(query, types: [spotify_api.SearchType.track]).first(15);
      
      final tracksList = <SpotifyTrack>[];
      for (final page in searchPage) {
        if (page.items != null) {
          for (final item in page.items!) {
            if (item is spotify_api.Track) {
              tracksList.add(SpotifyTrack(
                id: item.id ?? '',
                name: item.name ?? 'Untitled',
                artist: item.artists != null && item.artists!.isNotEmpty ? item.artists!.first.name ?? 'Unknown' : 'Unknown',
                album: item.album?.name ?? 'Single',
                albumArtUrl: item.album?.images != null && item.album!.images!.isNotEmpty ? item.album!.images!.first.url : null,
                duration: item.durationMs != null ? Duration(milliseconds: item.durationMs!) : const Duration(minutes: 3),
                previewUrl: item.previewUrl,
              ));
            }
          }
        }
      }
      return tracksList;
    } catch (e) {
      print('Spotify API Error searching tracks: $e');
      return _demoTracks;
    }
  }

  // ── Playback Control ─────────────────────────────────────────────
  Future<void> playTrack(SpotifyTrack track, [List<SpotifyTrack>? playlistQueue]) async {
    currentTrack.value = track;
    isPlaying.value = true;
    if (playlistQueue != null) {
      queue.value = playlistQueue;
      _queueIndex = playlistQueue.indexWhere((t) => t.id == track.id);
      if (_queueIndex == -1) _queueIndex = 0;
    } else {
      queue.value = [track];
      _queueIndex = 0;
    }

    try {
      final url = track.previewUrl ?? 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3';
      await _audioPlayer.play(UrlSource(url));
    } catch (e) {
      print('AudioPlayer error: $e');
    }
  }

  Future<void> togglePlay() async {
    if (currentTrack.value == null && queue.value.isNotEmpty) {
      await playTrack(queue.value.first);
      return;
    }
    if (currentTrack.value != null) {
      if (isPlaying.value) {
        await _audioPlayer.pause();
        isPlaying.value = false;
      } else {
        final url = currentTrack.value!.previewUrl ?? 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3';
        await _audioPlayer.play(UrlSource(url));
        isPlaying.value = true;
      }
    }
  }

  Future<void> stop() async {
    await _audioPlayer.stop();
    isPlaying.value = false;
    currentTrack.value = null;
  }

  Future<void> nextTrack() async {
    if (queue.value.isEmpty) return;
    _queueIndex = (_queueIndex + 1) % queue.value.length;
    final track = queue.value[_queueIndex];
    await playTrack(track, queue.value);
  }

  Future<void> prevTrack() async {
    if (queue.value.isEmpty) return;
    _queueIndex = (_queueIndex - 1 + queue.value.length) % queue.value.length;
    final track = queue.value[_queueIndex];
    await playTrack(track, queue.value);
  }
}
