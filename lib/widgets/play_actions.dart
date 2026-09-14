import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/track.dart';
import '../screens/desktop/shell_navigation.dart';
import '../services/audio_player_service.dart';

/// Picking a song from a list does two things — start playback and show the
/// player — and every list screen used to spell both out for itself, in three
/// slightly different (and two subtly wrong) ways. The rule lives here now:
/// [playFromList] and [playAll] are the only verbs a screen needs.
///
/// The "show the player" half is [ShellNavigation]'s: the shell provides it,
/// and a test rendering a list on its own provides a recording one.

/// Play [track] as one of [tracks], then bring Now Playing forward. If [track]
/// is already the current track, playback is left untouched — tapping the song
/// that is already playing just reopens the player.
void playFromList(BuildContext context, Track track, List<Track> tracks) {
  final player = context.read<AudioPlayerService>();
  if (player.currentTrack?.id != track.id) {
    player.play(tracks, from: tracks.indexOf(track));
  }
  context.read<ShellNavigation>().openNowPlaying();
}

/// Play [tracks] from the top — or [shuffled] — then bring Now Playing
/// forward. Does nothing on an empty list.
void playAll(
  BuildContext context,
  List<Track> tracks, {
  bool shuffled = false,
}) {
  if (tracks.isEmpty) return;
  final player = context.read<AudioPlayerService>();
  if (shuffled) {
    player.playShuffled(tracks);
  } else {
    player.play(tracks);
  }
  context.read<ShellNavigation>().openNowPlaying();
}
