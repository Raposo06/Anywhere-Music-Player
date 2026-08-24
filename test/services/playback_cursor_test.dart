import 'package:flutter_test/flutter_test.dart';
import 'package:anywhere_music_player/services/playback_cursor.dart';
import 'package:anywhere_music_player/models/track.dart';
import '../support/fixtures.dart';

// Covers PlaybackCursor's hand-rolled sequencing (docs/decisions.md explains
// why it isn't ConcatenatingAudioSource): playlist advance/rewind, shuffle-
// order generation and wraparound, repeat modes, queue priority, and
// upcoming-list bookkeeping. Exercised entirely through PlaybackCursor's own
// public methods — advance/rewind/peekNext/jumpTo*/reorderUpcoming/
// toggleShuffle/toggleRepeatMode — plus the seed() seam for setting up
// scenarios (a stale shuffle order, an arbitrary shufflePos) that no
// production entry point produces on its own. Formerly
// audio_player_service_sequencing_test.dart, reached through seven
// *ForTest seams drilled through AudioPlayerService; see
// docs/reviews/2026-08-22-architecture-review.html Candidate 01.
void main() {
  List<Track> playlist(int n) =>
      List.generate(n, (i) => sampleTrack(id: '$i', title: 'Track $i'));

  group('advance (sequential)', () {
    test('advances by one', () {
      final cursor = PlaybackCursor()..seed(playlist: playlist(3), currentIndex: 0);
      final track = cursor.advance();
      expect(track?.id, '1');
      expect(cursor.currentIndex, 1);
    });

    test('returns null at the end when repeat is off', () {
      final cursor = PlaybackCursor()
        ..seed(playlist: playlist(3), currentIndex: 2, repeatMode: RepeatMode.off);
      expect(cursor.advance(), isNull);
      expect(cursor.currentIndex, 2); // unchanged
    });

    test('wraps to the first track when repeat-all is on', () {
      final cursor = PlaybackCursor()
        ..seed(playlist: playlist(3), currentIndex: 2, repeatMode: RepeatMode.all);
      final track = cursor.advance();
      expect(track?.id, '0');
      expect(cursor.currentIndex, 0);
    });

    test('does not wrap at the end under repeat-one (only natural completion loops)', () {
      final cursor = PlaybackCursor()
        ..seed(playlist: playlist(3), currentIndex: 2, repeatMode: RepeatMode.one);
      expect(cursor.advance(), isNull);
      expect(cursor.currentIndex, 2);
    });

    test('returns null on an empty playlist', () {
      final cursor = PlaybackCursor()..seed(playlist: []);
      expect(cursor.advance(), isNull);
    });
  });

  group('rewind (sequential)', () {
    test('steps back by one', () {
      final cursor = PlaybackCursor()..seed(playlist: playlist(3), currentIndex: 2);
      final track = cursor.rewind();
      expect(track?.id, '1');
      expect(cursor.currentIndex, 1);
    });

    test('returns null before the start when repeat is off', () {
      final cursor = PlaybackCursor()
        ..seed(playlist: playlist(3), currentIndex: 0, repeatMode: RepeatMode.off);
      expect(cursor.rewind(), isNull);
      expect(cursor.currentIndex, 0);
    });

    test('wraps to the last index before the start when repeat-all is on', () {
      final cursor = PlaybackCursor()
        ..seed(playlist: playlist(3), currentIndex: 0, repeatMode: RepeatMode.all);
      final track = cursor.rewind();
      expect(track?.id, '2');
      expect(cursor.currentIndex, 2);
    });
  });

  group('advance / rewind (shuffle)', () {
    test('walks the shuffle order forward', () {
      final cursor = PlaybackCursor()
        ..seed(
          playlist: playlist(4),
          isShuffleEnabled: true,
          shuffleOrder: [2, 0, 3, 1],
          shufflePos: 0,
        );
      expect(cursor.advance()?.id, '0'); // shuffleOrder[1]
      expect(cursor.advance()?.id, '3'); // shuffleOrder[2] — proves shufflePos moved
    });

    test('returns null past the end of the shuffle order when repeat is off', () {
      final cursor = PlaybackCursor()
        ..seed(
          playlist: playlist(4),
          isShuffleEnabled: true,
          shuffleOrder: [2, 0, 3, 1],
          shufflePos: 3, // already on the last entry
          repeatMode: RepeatMode.off,
        );
      expect(cursor.advance(), isNull);
    });

    test('reshuffles and walks a fresh permutation when repeat-all runs out', () {
      final tracks = playlist(4);
      final cursor = PlaybackCursor()
        ..seed(
          playlist: tracks,
          currentIndex: 1,
          isShuffleEnabled: true,
          shuffleOrder: [2, 0, 3, 1],
          shufflePos: 3,
          repeatMode: RepeatMode.all,
        );

      // The exhausted pass lands back on the still-playing track (a fresh
      // order is anchored there) before walking on.
      expect(cursor.advance()?.id, tracks[1].id);

      // The rest of the fresh order is a permutation of the other 3 tracks —
      // random order, but always exactly these three, each once.
      final visited = [cursor.advance()?.id, cursor.advance()?.id, cursor.advance()?.id];
      expect(visited.toSet(), {tracks[0].id, tracks[2].id, tracks[3].id});
    });

    test('walks the shuffle order backward', () {
      final cursor = PlaybackCursor()
        ..seed(
          playlist: playlist(4),
          isShuffleEnabled: true,
          shuffleOrder: [2, 0, 3, 1],
          shufflePos: 2,
        );
      expect(cursor.rewind()?.id, '0'); // shuffleOrder[1]
      expect(cursor.rewind()?.id, '2'); // shuffleOrder[0] — proves shufflePos moved
    });

    test('returns null before the start of the shuffle order when repeat is off', () {
      final cursor = PlaybackCursor()
        ..seed(
          playlist: playlist(4),
          isShuffleEnabled: true,
          shuffleOrder: [2, 0, 3, 1],
          shufflePos: 0,
          repeatMode: RepeatMode.off,
        );
      expect(cursor.rewind(), isNull);
    });

    test('wraps to the last shuffle-order entry when repeat-all is on', () {
      final cursor = PlaybackCursor()
        ..seed(
          playlist: playlist(4),
          isShuffleEnabled: true,
          shuffleOrder: [2, 0, 3, 1],
          shufflePos: 0,
          repeatMode: RepeatMode.all,
        );
      expect(cursor.rewind()?.id, '1'); // shuffleOrder.last
      expect(cursor.rewind()?.id, '3'); // shuffleOrder[2] — proves shufflePos moved
    });

    test('falls back to sequential order when shuffleOrder is stale (wrong length)', () {
      // e.g. the playlist changed since the order was generated.
      final cursor = PlaybackCursor()
        ..seed(
          playlist: playlist(4),
          currentIndex: 0,
          isShuffleEnabled: true,
          shuffleOrder: [1, 0], // stale: length 2 for a 4-track playlist
        );
      expect(cursor.advance()?.id, '1'); // sequential, not shuffleOrder[1]
    });
  });

  group('peekNext', () {
    test('queue takes priority over the playlist, shuffle or not', () {
      final tracks = playlist(3);
      final queued = sampleTrack(id: 'q', title: 'Queued');
      final cursor = PlaybackCursor()
        ..seed(
          playlist: tracks,
          currentIndex: 0,
          queue: [queued],
          isShuffleEnabled: true,
          shuffleOrder: [2, 1, 0],
          shufflePos: 0,
        );
      expect(cursor.peekNext()?.id, 'q');
    });

    test('sequential: returns the next playlist track', () {
      final tracks = playlist(3);
      final cursor = PlaybackCursor()..seed(playlist: tracks, currentIndex: 0);
      expect(cursor.peekNext()?.id, tracks[1].id);
    });

    test('sequential: null past the end with repeat off', () {
      final cursor = PlaybackCursor()
        ..seed(playlist: playlist(3), currentIndex: 2, repeatMode: RepeatMode.off);
      expect(cursor.peekNext(), isNull);
    });

    test('sequential: wraps to the first track with repeat-all', () {
      final tracks = playlist(3);
      final cursor = PlaybackCursor()
        ..seed(playlist: tracks, currentIndex: 2, repeatMode: RepeatMode.all);
      expect(cursor.peekNext()?.id, tracks[0].id);
    });

    test('shuffle-aware and side-effect free (does not consume the shuffle position)', () {
      final tracks = playlist(4);
      final cursor = PlaybackCursor()
        ..seed(
          playlist: tracks,
          isShuffleEnabled: true,
          shuffleOrder: [2, 0, 3, 1],
          shufflePos: 0,
        );
      expect(cursor.peekNext()?.id, tracks[0].id); // shuffleOrder[1]
      expect(cursor.peekNext()?.id, tracks[0].id); // stable on repeat call
      // If peek had silently consumed the position, advance() would now
      // skip ahead to shuffleOrder[2] instead of landing where peek predicted.
      expect(cursor.advance()?.id, tracks[0].id);
    });

    test('predicts the same track advance() lands on when a shuffle pass '
        'is exhausted and repeat-all regenerates', () {
      // Regression case: peekNext used to read the stale order's [0] here,
      // while advance() regenerates anchored at the current track — the two
      // disagreed, which showed up as the wrong cover prefetched on the last
      // track of every shuffled pass.
      final tracks = playlist(4);
      final cursor = PlaybackCursor()
        ..seed(
          playlist: tracks,
          currentIndex: 1,
          isShuffleEnabled: true,
          shuffleOrder: [2, 0, 3, 1],
          shufflePos: 3, // exhausted
          repeatMode: RepeatMode.all,
        );
      final peeked = cursor.peekNext();
      final advanced = cursor.advance();
      expect(peeked?.id, advanced?.id);
      expect(peeked?.id, tracks[1].id); // anchored at the still-playing track
    });
  });

  group('upcoming', () {
    test('sequential: the tail of the playlist after currentIndex', () {
      final tracks = playlist(4);
      final cursor = PlaybackCursor()..seed(playlist: tracks, currentIndex: 1);
      expect(cursor.upcoming.map((t) => t.id), [tracks[2].id, tracks[3].id]);
    });

    test('shuffle: the tail of the shuffle order after shufflePos', () {
      final tracks = playlist(4);
      final cursor = PlaybackCursor()
        ..seed(
          playlist: tracks,
          isShuffleEnabled: true,
          shuffleOrder: [2, 0, 3, 1],
          shufflePos: 1,
        );
      expect(cursor.upcoming.map((t) => t.id), [tracks[3].id, tracks[1].id]);
    });

    test('empty playlist yields an empty list', () {
      final cursor = PlaybackCursor()..seed(playlist: []);
      expect(cursor.upcoming, isEmpty);
    });
  });

  group('toggleShuffle', () {
    test('enabling anchors the shuffle order at the current track (excluded from upcoming)', () {
      final tracks = playlist(5);
      final cursor = PlaybackCursor()..seed(playlist: tracks, currentIndex: 3);

      cursor.toggleShuffle();

      expect(cursor.isShuffleEnabled, isTrue);
      expect(cursor.upcoming.length, 4);
      expect(cursor.upcoming.any((t) => t.id == tracks[3].id), isFalse);
      expect(
        cursor.upcoming.map((t) => t.id).toSet(),
        {tracks[0].id, tracks[1].id, tracks[2].id, tracks[4].id},
      );
    });

    test('disabling just flips the flag', () {
      final cursor = PlaybackCursor()..seed(playlist: playlist(5), isShuffleEnabled: true);
      cursor.toggleShuffle();
      expect(cursor.isShuffleEnabled, isFalse);
    });

    test('walking a full shuffle pass visits every other track exactly once', () {
      final tracks = playlist(5);
      final cursor = PlaybackCursor()..seed(playlist: tracks, currentIndex: 0);
      cursor.toggleShuffle(); // enables, anchors at the current track (index 0)

      final visited = List.generate(4, (_) => cursor.advance()?.id);

      expect(visited.toSet().length, 4); // no repeats
      expect(visited.toSet(), {tracks[1].id, tracks[2].id, tracks[3].id, tracks[4].id});
      // The pass is exhausted; repeat-all (the default) keeps it going.
      expect(cursor.advance(), isNotNull);
    });

    test('toggling shuffle on an empty playlist does not crash', () {
      final cursor = PlaybackCursor()..seed(playlist: []);
      cursor.toggleShuffle();
      expect(cursor.isShuffleEnabled, isTrue);
    });
  });

  group('setShuffle', () {
    test('turning on anchors the shuffle order at the current track, same as toggleShuffle', () {
      final tracks = playlist(5);
      final cursor = PlaybackCursor()..seed(playlist: tracks, currentIndex: 3);

      cursor.setShuffle(true);

      expect(cursor.isShuffleEnabled, isTrue);
      expect(cursor.upcoming.any((t) => t.id == tracks[3].id), isFalse);
    });

    test('is idempotent — setting the same state twice does not reshuffle', () {
      final tracks = playlist(5);
      final cursor = PlaybackCursor()..seed(playlist: tracks, currentIndex: 0);
      cursor.setShuffle(true);
      final firstPass = cursor.upcoming.map((t) => t.id).toList();

      cursor.setShuffle(true); // already on — must not re-anchor/reshuffle

      expect(cursor.upcoming.map((t) => t.id).toList(), firstPass);
    });

    test('turning off just flips the flag', () {
      final cursor = PlaybackCursor()..seed(playlist: playlist(3), isShuffleEnabled: true);
      cursor.setShuffle(false);
      expect(cursor.isShuffleEnabled, isFalse);
    });
  });

  group('toggleRepeatMode', () {
    test('cycles off -> all -> one -> off', () {
      final cursor = PlaybackCursor();
      expect(cursor.repeatMode, RepeatMode.all); // documented default

      cursor.toggleRepeatMode();
      expect(cursor.repeatMode, RepeatMode.one);
      cursor.toggleRepeatMode();
      expect(cursor.repeatMode, RepeatMode.off);
      cursor.toggleRepeatMode();
      expect(cursor.repeatMode, RepeatMode.all);
    });
  });

  group('queue mutation', () {
    test('enqueue appends without disturbing the playlist', () {
      final tracks = playlist(2);
      final cursor = PlaybackCursor()..seed(playlist: tracks, currentIndex: 0);
      final queued = sampleTrack(id: 'q1', title: 'Queued 1');

      cursor.enqueue(queued);

      expect(cursor.queue.map((t) => t.id), ['q1']);
      expect(cursor.playlist.map((t) => t.id), tracks.map((t) => t.id));
    });

    test('dequeueAt drops the entry at that index and reports success', () {
      final q = [sampleTrack(id: 'a'), sampleTrack(id: 'b'), sampleTrack(id: 'c')];
      final cursor = PlaybackCursor()..seed(queue: q);

      expect(cursor.dequeueAt(1), isTrue);

      expect(cursor.queue.map((t) => t.id), ['a', 'c']);
    });

    test('dequeueAt ignores an out-of-range index and reports failure', () {
      final cursor = PlaybackCursor()..seed(queue: [sampleTrack(id: 'a')]);

      expect(cursor.dequeueAt(5), isFalse);

      expect(cursor.queue.map((t) => t.id), ['a']);
    });

    test('moveInQueue reorders and reports success', () {
      final q = [sampleTrack(id: 'a'), sampleTrack(id: 'b'), sampleTrack(id: 'c')];
      final cursor = PlaybackCursor()..seed(queue: q);

      expect(cursor.moveInQueue(0, 2), isTrue);

      expect(cursor.queue.map((t) => t.id), ['b', 'c', 'a']);
    });

    test('clearQueue empties the queue and forgets playingFromQueue', () {
      final tracks = playlist(2);
      final cursor = PlaybackCursor()
        ..seed(
          playlist: tracks,
          currentIndex: 1,
          queue: [sampleTrack(id: 'q')],
          repeatMode: RepeatMode.off,
        );
      cursor.jumpToQueued(0); // now playing from the queue, currentIndex frozen at 1

      cursor.clearQueue();

      expect(cursor.queue, isEmpty);
      // playingFromQueue forgotten: rewind steps back in the playlist (to
      // track 0) instead of returning to the now-irrelevant interrupted
      // track (which would have replayed track 1).
      expect(cursor.rewind()?.id, tracks[0].id);
    });
  });

  group('jumpToQueued', () {
    test('plays the target and discards the queued tracks ahead of it', () {
      final q = [sampleTrack(id: 'a'), sampleTrack(id: 'b'), sampleTrack(id: 'c')];
      final cursor = PlaybackCursor()..seed(playlist: playlist(2), currentIndex: 0, queue: q);

      final track = cursor.jumpToQueued(1);

      expect(track?.id, 'b');
      expect(cursor.queue.map((t) => t.id), ['c']);
    });

    test('returns null on an out-of-range index and leaves the queue untouched', () {
      final cursor = PlaybackCursor()..seed(queue: [sampleTrack(id: 'a')]);
      expect(cursor.jumpToQueued(5), isNull);
      expect(cursor.queue.map((t) => t.id), ['a']);
    });

    test('rewind afterwards returns to the interrupted playlist track', () {
      final tracks = playlist(2);
      final cursor = PlaybackCursor()
        ..seed(playlist: tracks, currentIndex: 0, queue: [sampleTrack(id: 'q')]);
      cursor.jumpToQueued(0);

      final back = cursor.rewind();

      expect(back?.id, tracks[0].id);
      expect(cursor.currentIndex, 0); // the playlist cursor never moved
    });
  });

  group('jumpToUpcoming', () {
    test('sequential: jumps forward without removing the skipped tracks', () {
      final tracks = playlist(4);
      final cursor = PlaybackCursor()..seed(playlist: tracks, currentIndex: 0);

      final track = cursor.jumpToUpcoming(1); // upcoming[1] == tracks[2]

      expect(track?.id, tracks[2].id);
      expect(cursor.currentIndex, 2);
      // The skipped track is still reachable via rewind.
      expect(cursor.rewind()?.id, tracks[1].id);
    });

    test('returns null past the end of the upcoming list', () {
      final cursor = PlaybackCursor()..seed(playlist: playlist(2), currentIndex: 0);
      expect(cursor.jumpToUpcoming(5), isNull);
      expect(cursor.currentIndex, 0);
    });
  });

  group('reorderUpcoming', () {
    test('sequential: reorders the playlist tail after currentIndex', () {
      final tracks = playlist(4);
      final cursor = PlaybackCursor()..seed(playlist: tracks, currentIndex: 0);

      // Move the last upcoming track (auto index 2, i.e. playlist[3]) to the
      // front of the upcoming section (auto index 0, i.e. playlist[1]).
      expect(cursor.reorderUpcoming(2, 0), isTrue);

      expect(
        cursor.playlist.map((t) => t.id),
        [tracks[0].id, tracks[3].id, tracks[1].id, tracks[2].id],
      );
    });

    test('shuffle: reorders the shuffle-order tail after shufflePos, never touching the playlist', () {
      final tracks = playlist(4);
      final cursor = PlaybackCursor()
        ..seed(
          playlist: tracks,
          isShuffleEnabled: true,
          shuffleOrder: [2, 0, 3, 1],
          shufflePos: 0,
        );

      // Upcoming (shuffleOrder[1:]) is [0, 3, 1]; move auto index 2 (value 1)
      // to auto index 0.
      expect(cursor.reorderUpcoming(2, 0), isTrue);

      expect(cursor.upcoming.map((t) => t.id), [tracks[1].id, tracks[0].id, tracks[3].id]);
      expect(cursor.playlist.map((t) => t.id), tracks.map((t) => t.id)); // untouched
    });

    test('no-op when the target is out of the upcoming range', () {
      final tracks = playlist(3);
      final cursor = PlaybackCursor()..seed(playlist: tracks, currentIndex: 1); // upcoming = [2] only

      expect(cursor.reorderUpcoming(0, 5), isFalse);

      expect(cursor.playlist.map((t) => t.id), tracks.map((t) => t.id));
    });
  });
}
