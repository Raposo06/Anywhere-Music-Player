import 'package:meta/meta.dart';
import '../models/track.dart';

enum RepeatMode { off, all, one }

/// Owns every "what plays next" decision: playlist order, the manual queue,
/// shuffle order and repeat mode. Pure Dart — no Flutter, no just_audio — so
/// it can be tested without a live platform audio backend and reasoned about
/// without pulling in the player.
///
/// [AudioPlayerService] is the only caller. It asks "what's next" via
/// [advance]/[rewind]/[jumpToQueued]/[jumpToUpcoming], gets a [Track] or null
/// back, and is responsible for actually loading and playing it — this class
/// never touches audio. See docs/decisions.md for why sequencing is
/// hand-rolled here instead of ConcatenatingAudioSource (buggy under
/// just_audio_media_kit on Windows/Linux); giving that decision its own
/// module is the point of this class.
class PlaybackCursor {
  // Active playlist (the folder/album the user is browsing).
  List<Track> _playlist = [];
  // Position in _playlist that will be resumed when the queue empties.
  int _currentIndex = -1;
  // Explicit FIFO queue. Independent of shuffle.
  final List<Track> _queue = [];
  // True iff the track currently playing came from _queue (so _currentIndex
  // points at the playlist track we'll return to once the queue is done).
  bool _playingFromQueue = false;

  // Shuffle plumbing: a permutation of playlist indices and where we are in it.
  List<int> _shuffleOrder = [];
  int _shufflePos = 0;
  bool _isShuffleEnabled = false;

  RepeatMode _repeatMode = RepeatMode.all;

  List<Track> get playlist => List.unmodifiable(_playlist);
  int get currentIndex => _currentIndex;
  List<Track> get queue => List.unmodifiable(_queue);
  int get queueLength => _queue.length;
  bool get isShuffleEnabled => _isShuffleEnabled;
  RepeatMode get repeatMode => _repeatMode;

  bool get _shuffleActive =>
      _isShuffleEnabled && _shuffleOrder.length == _playlist.length;

  /// The upcoming tracks from the browsing context (playlist), in play order
  /// and shuffle-aware, starting after the current playback position. Does
  /// not wrap around on repeat-all. Independent of the manual [queue].
  List<Track> get upcoming {
    if (_playlist.isEmpty) return const [];
    final result = <Track>[];
    if (_shuffleActive) {
      for (var p = _shufflePos + 1; p < _shuffleOrder.length; p++) {
        result.add(_playlist[_shuffleOrder[p]]);
      }
    } else {
      for (var i = _currentIndex + 1; i < _playlist.length; i++) {
        result.add(_playlist[i]);
      }
    }
    return List.unmodifiable(result);
  }

  /// Start playing [tracks] from [at]. Regenerates the shuffle order anchored
  /// at [at] if shuffle is enabled. Never touches the manual queue — the
  /// user-built queue survives switching what's being browsed.
  Track start(List<Track> tracks, {required int at}) {
    _playlist = List.of(tracks);
    _currentIndex = at;
    _playingFromQueue = false;
    if (_isShuffleEnabled) _regenerateShuffleOrder(anchorAt: at);
    return _playlist[at];
  }

  /// Advance to the next track. The manual queue takes priority over the
  /// playlist, regardless of shuffle. Returns null when playback should stop
  /// (empty playlist, or end reached with repeat off).
  Track? advance() {
    if (_queue.isNotEmpty) {
      final next = _queue.removeAt(0);
      _playingFromQueue = true;
      return next;
    }
    if (_playlist.isEmpty) return null;
    final next = _nextPlaylistIndex();
    if (next == null) return null;
    _currentIndex = next;
    _playingFromQueue = false;
    return _playlist[_currentIndex];
  }

  /// Step back. From a queue track, returns to the playlist track that was
  /// interrupted, without moving the playlist cursor. From a playlist track,
  /// steps back one (or through the shuffle order). Returns null when
  /// there's nowhere to go (start of playlist with repeat off, or an empty
  /// playlist).
  Track? rewind() {
    if (_playingFromQueue &&
        _currentIndex >= 0 &&
        _currentIndex < _playlist.length) {
      _playingFromQueue = false;
      return _playlist[_currentIndex];
    }
    if (_playlist.isEmpty) return null;
    final prev = _prevPlaylistIndex();
    if (prev == null) return null;
    _currentIndex = prev;
    _playingFromQueue = false;
    return _playlist[_currentIndex];
  }

  /// What [advance] would return right now, without mutating any state. Used
  /// by the player screen to precache the next track's cover art. Built on
  /// the same index arithmetic [advance] commits, so the two can't disagree
  /// about what's next.
  Track? peekNext() {
    if (_queue.isNotEmpty) return _queue.first;
    final idx = _peekNextIndex();
    return idx == null ? null : _playlist[idx];
  }

  /// Play the manual-queue track at [queueIndex] now, discarding the queued
  /// tracks ahead of it (the ones that would have played first).
  Track? jumpToQueued(int queueIndex) {
    if (queueIndex < 0 || queueIndex >= _queue.length) return null;
    final track = _queue[queueIndex];
    _queue.removeRange(0, queueIndex + 1);
    _playingFromQueue = true;
    return track;
  }

  /// Jump forward to the [autoIndex]-th track of [upcoming]. The cursor
  /// simply moves; skipped tracks are not removed and remain reachable via
  /// [rewind].
  Track? jumpToUpcoming(int autoIndex) {
    if (autoIndex < 0 || _playlist.isEmpty) return null;
    if (_shuffleActive) {
      final pos = _shufflePos + 1 + autoIndex;
      if (pos >= _shuffleOrder.length) return null;
      _shufflePos = pos;
      _currentIndex = _shuffleOrder[pos];
    } else {
      final idx = _currentIndex + 1 + autoIndex;
      if (idx >= _playlist.length) return null;
      _currentIndex = idx;
    }
    _playingFromQueue = false;
    return _playlist[_currentIndex];
  }

  /// Reorder a track within the auto-upcoming section (see [upcoming]). In
  /// shuffle mode this reorders the upcoming shuffle sequence (until the next
  /// reshuffle); in sequential mode it reorders the playlist tail. Indices
  /// are relative to [upcoming]. Returns whether the reorder happened.
  bool reorderUpcoming(int oldAuto, int newAuto) {
    if (oldAuto == newAuto) return false;
    final shuffle = _shuffleActive;
    final base = shuffle ? _shufflePos + 1 : _currentIndex + 1;
    final list = shuffle ? _shuffleOrder : _playlist;
    final oldPos = base + oldAuto;
    final newPos = base + newAuto;
    if (oldPos < base || oldPos >= list.length) return false;
    if (newPos < base || newPos >= list.length) return false;
    if (shuffle) {
      final v = _shuffleOrder.removeAt(oldPos);
      _shuffleOrder.insert(newPos, v);
    } else {
      final v = _playlist.removeAt(oldPos);
      _playlist.insert(newPos, v);
    }
    return true;
  }

  // -------- Queue mutation --------

  void enqueue(Track track) => _queue.add(track);

  /// Returns whether [index] was in range and the track was removed.
  bool dequeueAt(int index) {
    if (index < 0 || index >= _queue.length) return false;
    _queue.removeAt(index);
    return true;
  }

  /// Returns whether both indices were in range and the move happened.
  bool moveInQueue(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return false;
    if (oldIndex < 0 || oldIndex >= _queue.length) return false;
    if (newIndex < 0 || newIndex >= _queue.length) return false;
    final t = _queue.removeAt(oldIndex);
    _queue.insert(newIndex, t);
    return true;
  }

  /// Clear the manual queue and forget that we were playing from it. Leaves
  /// the playlist and shuffle position intact.
  void clearQueue() {
    _queue.clear();
    _playingFromQueue = false;
  }

  // -------- Modes --------

  void toggleShuffle() {
    _isShuffleEnabled = !_isShuffleEnabled;
    if (_isShuffleEnabled && _playlist.length > 1) {
      _regenerateShuffleOrder(anchorAt: _currentIndex);
    }
  }

  /// Set shuffle to a known state, rather than flipping it — for callers
  /// that want "shuffle on" as an outcome, not a toggle.
  void setShuffle(bool enabled) {
    if (enabled != _isShuffleEnabled) toggleShuffle();
  }

  /// Set repeat to a known mode, rather than cycling it — for callers that
  /// want a specific mode as an outcome (restoring the saved one at startup).
  void setRepeatMode(RepeatMode mode) {
    _repeatMode = mode;
  }

  void toggleRepeatMode() {
    switch (_repeatMode) {
      case RepeatMode.off:
        _repeatMode = RepeatMode.all;
        break;
      case RepeatMode.all:
        _repeatMode = RepeatMode.one;
        break;
      case RepeatMode.one:
        _repeatMode = RepeatMode.off;
        break;
    }
  }

  // -------- Index arithmetic --------

  void _regenerateShuffleOrder({int anchorAt = -1}) {
    if (_playlist.isEmpty) {
      _shuffleOrder = [];
      _shufflePos = 0;
      return;
    }
    _shuffleOrder = List.generate(_playlist.length, (i) => i)..shuffle();
    if (anchorAt >= 0 && anchorAt < _playlist.length) {
      final pos = _shuffleOrder.indexOf(anchorAt);
      if (pos > 0) {
        _shuffleOrder.removeAt(pos);
        _shuffleOrder.insert(0, anchorAt);
      }
    }
    _shufflePos = 0;
  }

  /// The playlist index that landing on "next" resolves to, without mutating
  /// any state. When the shuffle order is exhausted and repeat-all is on, the
  /// real next order is random — but the *landing index* is always the
  /// anchor ([_currentIndex], since [advance] regenerates anchored there),
  /// which lets this stay pure instead of needing to perform the shuffle.
  int? _peekNextIndex() {
    if (_playlist.isEmpty) return null;
    if (_shuffleActive) {
      final next = _shufflePos + 1;
      if (next >= _shuffleOrder.length) {
        return _repeatMode == RepeatMode.all ? _currentIndex : null;
      }
      return _shuffleOrder[next];
    }
    final next = _currentIndex + 1;
    if (next >= _playlist.length) {
      return _repeatMode == RepeatMode.all ? 0 : null;
    }
    return next;
  }

  /// Next playlist index respecting shuffle and loop, committing shuffle
  /// cursor state (regenerating the order if it just ran out). Returns null
  /// when playback should stop.
  int? _nextPlaylistIndex() {
    final idx = _peekNextIndex();
    if (idx == null) return null;
    if (_shuffleActive) {
      if (_shufflePos + 1 >= _shuffleOrder.length) {
        _regenerateShuffleOrder(anchorAt: _currentIndex);
        _shufflePos = 0;
      } else {
        _shufflePos += 1;
      }
    }
    return idx;
  }

  int? _prevPlaylistIndex() {
    if (_playlist.isEmpty) return null;
    if (_shuffleActive) {
      var prev = _shufflePos - 1;
      if (prev < 0) {
        if (_repeatMode == RepeatMode.all) {
          prev = _shuffleOrder.length - 1;
        } else {
          return null;
        }
      }
      _shufflePos = prev;
      return _shuffleOrder[prev];
    }
    var prev = _currentIndex - 1;
    if (prev < 0) {
      if (_repeatMode == RepeatMode.all) {
        prev = _playlist.length - 1;
      } else {
        return null;
      }
    }
    return prev;
  }

  // -------- Test-only seam --------

  /// Seeds state directly instead of going through [start]/[advance], which
  /// is how widget tests render UI driven by [AudioPlayerService] without a
  /// live audio backend, and how sequencing tests set up scenarios (a stale
  /// shuffle order, an arbitrary shufflePos) that no production entry point
  /// produces on its own. Only overwrites the fields passed.
  @visibleForTesting
  void seed({
    List<Track>? playlist,
    int? currentIndex,
    List<Track>? queue,
    bool? isShuffleEnabled,
    RepeatMode? repeatMode,
    List<int>? shuffleOrder,
    int? shufflePos,
  }) {
    if (playlist != null) _playlist = List.of(playlist);
    if (currentIndex != null) _currentIndex = currentIndex;
    if (queue != null) {
      _queue
        ..clear()
        ..addAll(queue);
    }
    if (isShuffleEnabled != null) _isShuffleEnabled = isShuffleEnabled;
    if (repeatMode != null) _repeatMode = repeatMode;
    if (shuffleOrder != null) _shuffleOrder = shuffleOrder;
    if (shufflePos != null) _shufflePos = shufflePos;
  }
}
