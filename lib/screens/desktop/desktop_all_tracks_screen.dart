import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../models/track.dart';
import '../../services/audio_player_service.dart';
import '../../services/library_scanner.dart';
import '../../theme/app_colors.dart';
import '../../widgets/desktop/desktop_primitives.dart';
import '../../widgets/desktop/desktop_track_row.dart';
import 'desktop_search_field.dart';
import 'desktop_shell.dart';

/// Every track in the library, alphabetical, with search.
///
/// The desktop counterpart to [AllTracksScreen]; same two-list arrangement
/// (the full library backs playback, a filtered view backs what you see) so
/// playing a search result keeps going past the tracks the search excluded.
class DesktopAllTracksScreen extends StatefulWidget {
  const DesktopAllTracksScreen({super.key});

  @override
  State<DesktopAllTracksScreen> createState() => _DesktopAllTracksScreenState();
}

class _DesktopAllTracksScreenState extends State<DesktopAllTracksScreen> {
  /// Full sorted library — always the source for playback, so the queue keeps
  /// playing beyond the search results.
  List<Track> _allTracks = [];

  /// What the user currently sees (either [_allTracks] or a filtered subset).
  List<Track> _tracks = [];

  bool _isLoading = false;
  String _query = '';
  Timer? _debounce;

  // Drives "follow the playing track": scroll the list to the current song.
  final ItemScrollController _itemScrollController = ItemScrollController();
  // Last track id we scrolled to, so we only follow on an actual change.
  String? _followedTrackId;

  AudioPlayerService? _playerForListener;
  LibraryScanner? _scannerForListener;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _playerForListener = context.read<AudioPlayerService>()
        ..addListener(_followCurrentTrack);
      _scannerForListener = context.read<LibraryScanner>()
        ..addListener(_onScannerUpdate);
      _load();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _playerForListener?.removeListener(_followCurrentTrack);
    _scannerForListener?.removeListener(_onScannerUpdate);
    super.dispose();
  }

  void _onScannerUpdate() {
    if (!mounted) return;
    if (!context.read<LibraryScanner>().isScanning) _load();
  }

  void _load() {
    if (!mounted) return;
    final scanner = context.read<LibraryScanner>();
    if (!scanner.hasInitialData) {
      setState(() => _isLoading = true);
      return;
    }

    final tracks = List<Track>.from(scanner.allTracks)
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

    setState(() {
      _allTracks = tracks;
      _tracks = _query.isEmpty ? tracks : _filter(tracks, _query);
      _isLoading = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _followCurrentTrack());
  }

  static List<Track> _filter(List<Track> source, String query) {
    final needle = query.toLowerCase();
    return source.where((t) => t.title.toLowerCase().contains(needle)).toList();
  }

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    setState(() => _query = query);
    if (query.isEmpty) {
      setState(() => _tracks = _allTracks);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() => _tracks = _filter(_allTracks, query));
    });
  }

  /// Scroll the list so the currently-playing track is visible. Only acts when
  /// the playing track id changes (and on open), so manual scrolling between
  /// songs is never interrupted. No-op if the track isn't in the current list.
  void _followCurrentTrack() {
    if (!mounted) return;
    final id = context.read<AudioPlayerService>().currentTrack?.id;
    if (id == null) {
      _followedTrackId = null;
      return;
    }
    if (id == _followedTrackId) return;
    final index = _tracks.indexWhere((t) => t.id == id);
    if (index < 0) return; // not in this list — leave _followedTrackId unset
    if (!_itemScrollController.isAttached) return; // retried on next change
    _followedTrackId = id;
    _itemScrollController.scrollTo(
      index: index,
      alignment: 0.3,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  void _playTrack(Track track) {
    final player = context.read<AudioPlayerService>();
    // Already the current track — don't restart it.
    if (player.currentTrack?.id == track.id) return;
    // Always play from the full library so playback continues past tracks
    // that didn't match the current search.
    player.play(_allTracks, from: _allTracks.indexOf(track));
  }

  void _playAll({required bool shuffled}) {
    if (_tracks.isEmpty) return;
    final player = context.read<AudioPlayerService>();
    if (shuffled) {
      player.playShuffled(_tracks);
    } else {
      player.play(_tracks);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.win,
      child: Padding(
        padding: contentPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'All Tracks',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _query.isEmpty
                            ? '${_tracks.length} tracks'
                            : '${_tracks.length} result(s)',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                DesktopSearchField(
                  onChanged: _onQueryChanged,
                  hintText: 'Search tracks...',
                  width: 220,
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _tracks.isEmpty
                      ? null
                      : () => _playAll(shuffled: false),
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: const Text('Play All'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed:
                      _tracks.isEmpty ? null : () => _playAll(shuffled: true),
                  icon: const Icon(Icons.shuffle, size: 16),
                  label: const Text('Shuffle'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const SectionLabel('Tracks'),
            const SizedBox(height: 6),
            Expanded(child: _buildList()),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_tracks.isEmpty) {
      return Center(
        child: Text(
          _query.isEmpty ? 'No tracks found' : 'No results for "$_query"',
          style: const TextStyle(fontSize: 15, color: AppColors.muted),
        ),
      );
    }

    return ScrollablePositionedList.builder(
      itemScrollController: _itemScrollController,
      itemCount: _tracks.length,
      itemBuilder: (context, index) {
        final track = _tracks[index];
        return DesktopTrackRow(
          track: track,
          number: index + 1,
          onTap: () => _playTrack(track),
        );
      },
    );
  }
}
