import 'dart:async';
import 'package:just_audio/just_audio.dart';
import '../models/track.dart';
import 'audio_handler.dart';
import 'now_playing_presence.dart';

/// Android (and iOS) presence: the audio_service notification, lock screen
/// and car-head-unit (Bluetooth AVRCP) integration, via [MusicAudioHandler].
///
/// Play/pause/stop aren't wired through [PlaybackCommands] here — the OS
/// calls [MusicAudioHandler]'s own overridden `play()`/`pause()`/`stop()`
/// methods directly (it *is* the audio_service handler), which is why
/// [bind] hands it the live player. Only next/previous need routing back
/// into the cursor-aware navigation [MusicAudioHandler] doesn't have.
class AndroidPresence implements NowPlayingPresence {
  AndroidPresence(this._handler);

  final MusicAudioHandler _handler;

  @override
  void bind(AudioPlayer player, PlaybackCommands commands) {
    _handler.attachPlayer(
      player: player,
      onNextCallback: commands.next,
      onPreviousCallback: commands.previous,
    );
  }

  @override
  void show(Track track) {
    unawaited(_handler.updateTrackInfo(track));
  }

  // audio_service already reflects play/pause by listening to the player's
  // own streams (wired in bind/attachPlayer) — nothing to push here.
  @override
  void setPlaying(bool playing) {}

  // No equivalent today: AudioPlayerService.stop() doesn't clear the
  // Android notification (only the SMTC/Windows side has ever done this).
  // Preserved as-is rather than added as a side effect of this seam.
  @override
  void clear() {}

  @override
  void dispose() {}
}
