import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/playlist.dart';
import '../models/track.dart';
import '../services/library_scanner.dart';
import '../services/playlists_service.dart';
import '../utils/platform_detector.dart';

/// Searches the library and files songs into [playlist], without leaving it.
///
/// The counterpart to `AddToPlaylist`, which starts from a track and asks
/// which playlist. This starts from the playlist and asks which tracks — the
/// direction you want when a playlist is new and empty, where the other flow
/// would mean leaving, hunting down each song, and coming back.
///
/// Adds land one at a time and are **kept**: the sheet stays open, the row
/// flips to a tick, and closing is an explicit "Done". Batching them until
/// close would make a mid-way dismissal silently lose the work.
///
/// Searching filters [LibraryScanner]'s cached tracks rather than calling
/// `search3`, so results are instant and keystroke-by-keystroke — no debounce,
/// no spinner, no failure path. The cost is that it can only find what the
/// last scan saw, which is the same set the rest of the app browses.
class AddSongsToPlaylist {
  const AddSongsToPlaylist._();

  /// Shows the picker. Returns the number of tracks added.
  static Future<int> show(BuildContext context, Playlist playlist) async {
    final body = _AddSongsBody(playlist: playlist);
    final added = PlatformDetector.isDesktop
        ? await showDialog<int>(
            context: context,
            builder: (_) => Dialog(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 560,
                  maxHeight: 640,
                ),
                child: body,
              ),
            ),
          )
        : await showModalBottomSheet<int>(
            context: context,
            isScrollControlled: true,
            showDragHandle: true,
            builder: (_) => SafeArea(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.85,
                ),
                child: body,
              ),
            ),
          );
    return added ?? 0;
  }
}

class _AddSongsBody extends StatefulWidget {
  final Playlist playlist;

  const _AddSongsBody({required this.playlist});

  @override
  State<_AddSongsBody> createState() => _AddSongsBodyState();
}

class _AddSongsBodyState extends State<_AddSongsBody> {
  final _controller = TextEditingController();
  String _query = '';

  /// Ids added during this session, so a row can show it is already filed
  /// without re-reading the playlist after every tap.
  final Set<String> _added = {};

  /// The id currently being written, so only that row shows a spinner.
  String? _pending;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Case-insensitive match on title, artist or album — the three things
  /// someone types when hunting for a song they can half-remember.
  List<Track> _matches(List<Track> all) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final out = <Track>[];
    for (final track in all) {
      if (track.title.toLowerCase().contains(q) ||
          (track.artist?.toLowerCase().contains(q) ?? false) ||
          (track.album?.toLowerCase().contains(q) ?? false)) {
        out.add(track);
        // Long libraries make an unbounded list pointless to scroll and slow
        // to lay out; refining the query is the better answer.
        if (out.length >= 100) break;
      }
    }
    return out;
  }

  Future<void> _add(Track track) async {
    setState(() => _pending = track.id);
    final ok = await context.read<PlaylistsService>().addTracks(
      widget.playlist.id,
      [track],
    );
    if (!mounted) return;
    setState(() {
      _pending = null;
      if (ok) _added.add(track.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final all = context.watch<LibraryScanner>().allTracks;
    final matches = _matches(all);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          title: Text('Add to ${widget.playlist.name}'),
          subtitle: _added.isEmpty
              ? null
              : Text(_added.length == 1 ? '1 added' : '${_added.length} added'),
          trailing: TextButton(
            onPressed: () => Navigator.of(context).pop(_added.length),
            child: const Text('Done'),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: TextField(
            controller: _controller,
            autofocus: true,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search your library',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
        const Divider(height: 1),
        Flexible(child: _buildResults(all, matches)),
      ],
    );
  }

  Widget _buildResults(List<Track> all, List<Track> matches) {
    if (all.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Your library has not been scanned yet.',
          textAlign: TextAlign.center,
        ),
      );
    }
    if (_query.trim().isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Type to search for songs to add.',
          textAlign: TextAlign.center,
        ),
      );
    }
    if (matches.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Nothing matches "${_query.trim()}".',
          textAlign: TextAlign.center,
        ),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      itemCount: matches.length,
      itemBuilder: (context, i) {
        final track = matches[i];
        final isAdded = _added.contains(track.id);
        final isPending = _pending == track.id;
        return ListTile(
          title: Text(
            track.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            track.artist ?? 'Unknown artist',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: isPending
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  isAdded ? Icons.check : Icons.add,
                  // Added rows stay tappable — a playlist may legitimately
                  // hold the same song twice — so the tick is a record of
                  // what happened, not a disabled state.
                  semanticLabel: isAdded ? 'Added' : 'Add',
                ),
          onTap: _pending == null ? () => _add(track) : null,
        );
      },
    );
  }
}
