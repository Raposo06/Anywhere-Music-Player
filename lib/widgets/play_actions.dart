import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/track.dart';
import '../screens/player_screen.dart';
import '../screens/tv_player_screen.dart';
import '../services/audio_player_service.dart';
import '../utils/platform_detector.dart';

/// Picking a song from a list does two things — start playback and show the
/// player — and every list screen used to spell both out for itself, in three
/// slightly different (and two subtly wrong) ways. The rule lives here now:
/// [playFromList] and [playAll] are the only verbs a screen needs.
///
/// The "show the player" half is the one part that genuinely differs by shell.
/// The desktop shell pushes Now Playing on the *root* navigator and takes a
/// folder back when it closes (see `FolderRequest`), so it owns that push and
/// hands the action down as a [NowPlayingOpener]. Phone and TV have no such
/// round-trip and just push their own route — which is exactly what
/// [openNowPlaying] falls back to when no opener is installed.
class NowPlayingOpener extends InheritedWidget {
  final VoidCallback open;

  const NowPlayingOpener({super.key, required this.open, required super.child});

  @override
  bool updateShouldNotify(NowPlayingOpener oldWidget) => open != oldWidget.open;
}

/// Bring Now Playing to the foreground: the shell's [NowPlayingOpener] when one
/// is installed (desktop), otherwise a plain push of the platform's player
/// route (phone, TV, and widget tests).
void openNowPlaying(BuildContext context) {
  final opener = context.getInheritedWidgetOfExactType<NowPlayingOpener>()?.open;
  if (opener != null) {
    opener();
    return;
  }
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => PlatformDetector.isAndroidTV
          ? const TvPlayerScreen()
          : const PlayerScreen(),
    ),
  );
}

/// Play [track] as one of [tracks], then bring Now Playing forward. If [track]
/// is already the current track, playback is left untouched — tapping the song
/// that is already playing just reopens the player.
void playFromList(BuildContext context, Track track, List<Track> tracks) {
  final player = context.read<AudioPlayerService>();
  if (player.currentTrack?.id != track.id) {
    player.play(tracks, from: tracks.indexOf(track));
  }
  openNowPlaying(context);
}

/// Play [tracks] from the top — or [shuffled] — then bring Now Playing
/// forward. Does nothing on an empty list.
void playAll(BuildContext context, List<Track> tracks, {bool shuffled = false}) {
  if (tracks.isEmpty) return;
  final player = context.read<AudioPlayerService>();
  if (shuffled) {
    player.playShuffled(tracks);
  } else {
    player.play(tracks);
  }
  openNowPlaying(context);
}
