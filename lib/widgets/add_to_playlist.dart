import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/track.dart';
import '../services/auth_service.dart';
import '../services/playlists_service.dart';
import '../utils/platform_detector.dart';

/// Picks a playlist to add [tracks] to, or creates one for them.
///
/// One widget, shown two ways: a dialog on desktop, a bottom sheet on phone.
/// The list itself is identical, so the layouts share it rather than
/// diverging the way the full screens do.
///
/// Playlists the user cannot edit are listed but disabled — Subsonic only
/// lets the owner modify a playlist, and offering a row that always fails
/// would be worse than showing why it can't be picked.
class AddToPlaylist {
  const AddToPlaylist._();

  /// Shows the picker. Returns the name added to, or null if dismissed.
  static Future<String?> show(BuildContext context, List<Track> tracks) {
    if (tracks.isEmpty) return Future.value(null);
    // Loaded here rather than by the caller: this is the one place that needs
    // the list, and it may be opened before the Playlists tab ever was.
    context.read<PlaylistsService>().load();

    final body = _AddToPlaylistBody(tracks: tracks);
    if (PlatformDetector.isDesktop) {
      return showDialog<String>(
        context: context,
        builder: (_) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420, maxHeight: 520),
            child: body,
          ),
        ),
      );
    }
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.7,
          ),
          child: body,
        ),
      ),
    );
  }
}

class _AddToPlaylistBody extends StatefulWidget {
  final List<Track> tracks;

  const _AddToPlaylistBody({required this.tracks});

  @override
  State<_AddToPlaylistBody> createState() => _AddToPlaylistBodyState();
}

class _AddToPlaylistBodyState extends State<_AddToPlaylistBody> {
  /// True while a create or add is in flight, so the sheet can't be
  /// double-submitted — these are not optimistic, so there is a real wait.
  bool _busy = false;

  Future<void> _addTo(String playlistId, String name) async {
    setState(() => _busy = true);
    final service = context.read<PlaylistsService>();
    final navigator = Navigator.of(context);
    final ok = await service.addTracks(playlistId, widget.tracks);
    if (!mounted) return;
    setState(() => _busy = false);
    // On failure the service holds the reason; the shell's listener shows it.
    navigator.pop(ok ? name : null);
  }

  Future<void> _createAndAdd() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const PlaylistNameDialog(),
    );
    if (name == null || !mounted) return;

    setState(() => _busy = true);
    final service = context.read<PlaylistsService>();
    final navigator = Navigator.of(context);
    final ok = await service.create(name, tracks: widget.tracks);
    if (!mounted) return;
    setState(() => _busy = false);
    navigator.pop(ok ? name : null);
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<PlaylistsService>();
    final username = context.read<AuthService>().currentUser?.username;
    final count = widget.tracks.length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          title: Text(count == 1 ? 'Add to playlist' : 'Add $count tracks to'),
          subtitle: count == 1 ? Text(widget.tracks.single.title) : null,
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.add),
          title: const Text('New playlist…'),
          enabled: !_busy,
          onTap: _createAndAdd,
        ),
        const Divider(height: 1),
        Flexible(child: _buildList(service, username)),
        if (_busy) const LinearProgressIndicator(minHeight: 2),
      ],
    );
  }

  Widget _buildList(PlaylistsService service, String? username) {
    if (service.isLoading && !service.isLoaded) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (service.playlists.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text('No playlists yet — create one above.'),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      itemCount: service.playlists.length,
      itemBuilder: (context, i) {
        final playlist = service.playlists[i];
        final editable = playlist.isEditableBy(username);
        return ListTile(
          leading: const Icon(Icons.queue_music),
          title: Text(playlist.name),
          subtitle: Text(
            editable ? playlist.summary : '${playlist.summary} · read-only',
          ),
          enabled: editable && !_busy,
          onTap: () => _addTo(playlist.id, playlist.name),
        );
      },
    );
  }
}

/// Asks for a playlist name.
///
/// Stateful, and owns its controller, deliberately: a caller that created the
/// controller itself would have to dispose it *after* the dialog's exit
/// animation finishes, and disposing it as soon as `showDialog` returns
/// throws "A TextEditingController was used after being disposed".
class PlaylistNameDialog extends StatefulWidget {
  /// Pre-filled name — set when renaming, empty when creating.
  final String initialName;
  final String title;
  final String actionLabel;

  const PlaylistNameDialog({
    super.key,
    this.initialName = '',
    this.title = 'New playlist',
    this.actionLabel = 'Create',
  });

  @override
  State<PlaylistNameDialog> createState() => _PlaylistNameDialogState();
}

class _PlaylistNameDialogState extends State<PlaylistNameDialog> {
  late final _controller = TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'Playlist name'),
        // Enter submits, which is what a one-field dialog should do.
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.actionLabel)),
      ],
    );
  }
}

/// Asks for a name and creates a playlist holding [tracks].
///
/// Used by "save the queue as a playlist" and by the playlists screens' own
/// create buttons. Returns the name created, or null.
Future<String?> createPlaylistWithPrompt(
  BuildContext context, {
  List<Track> tracks = const [],
}) async {
  final name = await showDialog<String>(
    context: context,
    builder: (_) => const PlaylistNameDialog(),
  );
  if (name == null || !context.mounted) return null;
  final ok = await context.read<PlaylistsService>().create(
    name,
    tracks: tracks,
  );
  return ok ? name : null;
}
