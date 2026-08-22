import 'package:flutter_test/flutter_test.dart';
import 'package:anywhere_music_player/services/audio_player_service.dart';
import 'package:anywhere_music_player/models/track.dart';
import '../support/fixtures.dart';

// Covers AudioPlayerService's hand-rolled sequencing (docs/decisions.md
// explains why it isn't ConcatenatingAudioSource): playlist advance/rewind,
// shuffle-order generation and wraparound, repeat modes, queue priority, and
// upcoming-list bookkeeping. Exercised entirely through the seedForTest /
// *ForTest seams — never through playTrack/playNext/etc., which construct a
// real AudioPlayer and need a live platform audio backend (see
// audio_player_service_replaygain_test.dart for the same pattern).
void main() {
  List<Track> playlist(int n) =>
      List.generate(n, (i) => sampleTrack(id: '$i', title: 'Track $i'));

  group('_nextPlaylistIndex (sequential)', () {
    test('advances by one', () {
      final service = AudioPlayerService()
        ..seedForTest(playlist: playlist(3), currentIndex: 0);
      expect(service.nextPlaylistIndexForTest(), 1);
    });

    test('returns null at the end when repeat is off', () {
      final service = AudioPlayerService()
        ..seedForTest(
          playlist: playlist(3),
          currentIndex: 2,
          repeatMode: RepeatMode.off,
        );
      expect(service.nextPlaylistIndexForTest(), isNull);
    });

    test('wraps to 0 at the end when repeat-all is on', () {
      final service = AudioPlayerService()
        ..seedForTest(
          playlist: playlist(3),
          currentIndex: 2,
          repeatMode: RepeatMode.all,
        );
      expect(service.nextPlaylistIndexForTest(), 0);
    });

    test('does not wrap at the end under repeat-one (only natural completion loops)', () {
      final service = AudioPlayerService()
        ..seedForTest(
          playlist: playlist(3),
          currentIndex: 2,
          repeatMode: RepeatMode.one,
        );
      expect(service.nextPlaylistIndexForTest(), isNull);
    });

    test('returns null on an empty playlist', () {
      final service = AudioPlayerService()..seedForTest(playlist: []);
      expect(service.nextPlaylistIndexForTest(), isNull);
    });
  });

  group('_prevPlaylistIndex (sequential)', () {
    test('steps back by one', () {
      final service = AudioPlayerService()
        ..seedForTest(playlist: playlist(3), currentIndex: 2);
      expect(service.prevPlaylistIndexForTest(), 1);
    });

    test('returns null before the start when repeat is off', () {
      final service = AudioPlayerService()
        ..seedForTest(
          playlist: playlist(3),
          currentIndex: 0,
          repeatMode: RepeatMode.off,
        );
      expect(service.prevPlaylistIndexForTest(), isNull);
    });

    test('wraps to the last index before the start when repeat-all is on', () {
      final service = AudioPlayerService()
        ..seedForTest(
          playlist: playlist(3),
          currentIndex: 0,
          repeatMode: RepeatMode.all,
        );
      expect(service.prevPlaylistIndexForTest(), 2);
    });
  });

  group('shuffle order generation', () {
    test('produces a permutation of every playlist index', () {
      final service = AudioPlayerService()..seedForTest(playlist: playlist(5));
      service.regenerateShuffleOrderForTest();
      expect(service.shuffleOrderForTest.toSet(), {0, 1, 2, 3, 4});
      expect(service.shuffleOrderForTest.length, 5);
    });

    test('resets shufflePos to 0', () {
      final service = AudioPlayerService()
        ..seedForTest(playlist: playlist(5), shufflePos: 3);
      service.regenerateShuffleOrderForTest();
      expect(service.shufflePosForTest, 0);
    });

    test('anchorAt places that playlist index first', () {
      final service = AudioPlayerService()..seedForTest(playlist: playlist(6));
      service.regenerateShuffleOrderForTest(anchorAt: 4);
      expect(service.shuffleOrderForTest.first, 4);
    });

    test('empty playlist produces an empty order', () {
      final service = AudioPlayerService()..seedForTest(playlist: []);
      service.regenerateShuffleOrderForTest();
      expect(service.shuffleOrderForTest, isEmpty);
    });
  });

  group('_nextPlaylistIndex / _prevPlaylistIndex (shuffle)', () {
    test('walks the shuffle order forward', () {
      final service = AudioPlayerService()
        ..seedForTest(
          playlist: playlist(4),
          isShuffleEnabled: true,
          shuffleOrder: [2, 0, 3, 1],
          shufflePos: 0,
        );
      expect(service.nextPlaylistIndexForTest(), 0); // shuffleOrder[1]
      expect(service.shufflePosForTest, 1);
    });

    test('returns null past the end of the shuffle order when repeat is off', () {
      final service = AudioPlayerService()
        ..seedForTest(
          playlist: playlist(4),
          isShuffleEnabled: true,
          shuffleOrder: [2, 0, 3, 1],
          shufflePos: 3, // already on the last entry
          repeatMode: RepeatMode.off,
        );
      expect(service.nextPlaylistIndexForTest(), isNull);
    });

    test('reshuffles and continues from the top when repeat-all runs out', () {
      final service = AudioPlayerService()
        ..seedForTest(
          playlist: playlist(4),
          currentIndex: 1,
          isShuffleEnabled: true,
          shuffleOrder: [2, 0, 3, 1],
          shufflePos: 3,
          repeatMode: RepeatMode.all,
        );
      final next = service.nextPlaylistIndexForTest();
      // A fresh shuffle order was generated (still a full permutation) and we
      // landed on its first entry, anchored at the still-playing track.
      expect(service.shuffleOrderForTest.toSet(), {0, 1, 2, 3});
      expect(service.shufflePosForTest, 0);
      expect(next, service.shuffleOrderForTest[0]);
      expect(next, 1); // anchorAt: currentIndex
    });

    test('walks the shuffle order backward', () {
      final service = AudioPlayerService()
        ..seedForTest(
          playlist: playlist(4),
          isShuffleEnabled: true,
          shuffleOrder: [2, 0, 3, 1],
          shufflePos: 2,
        );
      expect(service.prevPlaylistIndexForTest(), 0); // shuffleOrder[1]
      expect(service.shufflePosForTest, 1);
    });

    test('returns null before the start of the shuffle order when repeat is off', () {
      final service = AudioPlayerService()
        ..seedForTest(
          playlist: playlist(4),
          isShuffleEnabled: true,
          shuffleOrder: [2, 0, 3, 1],
          shufflePos: 0,
          repeatMode: RepeatMode.off,
        );
      expect(service.prevPlaylistIndexForTest(), isNull);
    });

    test('wraps to the last shuffle-order entry when repeat-all is on', () {
      final service = AudioPlayerService()
        ..seedForTest(
          playlist: playlist(4),
          isShuffleEnabled: true,
          shuffleOrder: [2, 0, 3, 1],
          shufflePos: 0,
          repeatMode: RepeatMode.all,
        );
      expect(service.prevPlaylistIndexForTest(), 1); // shuffleOrder.last
      expect(service.shufflePosForTest, 3);
    });

    test('falls back to sequential order when shuffleOrder is stale (wrong length)', () {
      // e.g. the playlist changed since the order was generated.
      final service = AudioPlayerService()
        ..seedForTest(
          playlist: playlist(4),
          currentIndex: 0,
          isShuffleEnabled: true,
          shuffleOrder: [1, 0], // stale: length 2 for a 4-track playlist
        );
      expect(service.nextPlaylistIndexForTest(), 1); // sequential, not shuffleOrder[1]
    });
  });

  group('peekNextTrack', () {
    test('queue takes priority over the playlist, shuffle or not', () {
      final tracks = playlist(3);
      final queued = sampleTrack(id: 'q', title: 'Queued');
      final service = AudioPlayerService()
        ..seedForTest(
          playlist: tracks,
          currentIndex: 0,
          queue: [queued],
          isShuffleEnabled: true,
          shuffleOrder: [2, 1, 0],
          shufflePos: 0,
        );
      expect(service.peekNextTrack()?.id, 'q');
    });

    test('sequential: returns the next playlist track', () {
      final tracks = playlist(3);
      final service = AudioPlayerService()
        ..seedForTest(playlist: tracks, currentIndex: 0);
      expect(service.peekNextTrack()?.id, tracks[1].id);
    });

    test('sequential: null past the end with repeat off', () {
      final tracks = playlist(3);
      final service = AudioPlayerService()
        ..seedForTest(
          playlist: tracks,
          currentIndex: 2,
          repeatMode: RepeatMode.off,
        );
      expect(service.peekNextTrack(), isNull);
    });

    test('sequential: wraps to the first track with repeat-all', () {
      final tracks = playlist(3);
      final service = AudioPlayerService()
        ..seedForTest(
          playlist: tracks,
          currentIndex: 2,
          repeatMode: RepeatMode.all,
        );
      expect(service.peekNextTrack()?.id, tracks[0].id);
    });

    test('shuffle-aware and side-effect free (does not advance shufflePos)', () {
      final tracks = playlist(4);
      final service = AudioPlayerService()
        ..seedForTest(
          playlist: tracks,
          isShuffleEnabled: true,
          shuffleOrder: [2, 0, 3, 1],
          shufflePos: 0,
        );
      expect(service.peekNextTrack()?.id, tracks[0].id); // shuffleOrder[1]
      expect(service.peekNextTrack()?.id, tracks[0].id); // stable on repeat call
      expect(service.shufflePosForTest, 0); // unchanged — peek, not consume
    });
  });

  group('upcomingFromContext', () {
    test('sequential: the tail of the playlist after currentIndex', () {
      final tracks = playlist(4);
      final service = AudioPlayerService()
        ..seedForTest(playlist: tracks, currentIndex: 1);
      expect(
        service.upcomingFromContext.map((t) => t.id),
        [tracks[2].id, tracks[3].id],
      );
    });

    test('shuffle: the tail of the shuffle order after shufflePos', () {
      final tracks = playlist(4);
      final service = AudioPlayerService()
        ..seedForTest(
          playlist: tracks,
          isShuffleEnabled: true,
          shuffleOrder: [2, 0, 3, 1],
          shufflePos: 1,
        );
      expect(
        service.upcomingFromContext.map((t) => t.id),
        [tracks[3].id, tracks[1].id],
      );
    });

    test('empty playlist yields an empty list', () {
      final service = AudioPlayerService()..seedForTest(playlist: []);
      expect(service.upcomingFromContext, isEmpty);
    });
  });

  group('toggleShuffle', () {
    test('enabling regenerates the shuffle order anchored at the current track', () {
      final service = AudioPlayerService()
        ..seedForTest(playlist: playlist(5), currentIndex: 3);
      expect(service.isShuffleEnabled, isFalse);

      service.toggleShuffle();

      expect(service.isShuffleEnabled, isTrue);
      expect(service.shuffleOrderForTest.length, 5);
      expect(service.shuffleOrderForTest.first, 3);
    });

    test('disabling just flips the flag', () {
      final service = AudioPlayerService()
        ..seedForTest(playlist: playlist(5), isShuffleEnabled: true);
      service.toggleShuffle();
      expect(service.isShuffleEnabled, isFalse);
    });
  });

  group('toggleRepeatMode', () {
    test('cycles off -> all -> one -> off', () {
      final service = AudioPlayerService();
      expect(service.repeatMode, RepeatMode.all); // documented default

      service.toggleRepeatMode();
      expect(service.repeatMode, RepeatMode.one);
      service.toggleRepeatMode();
      expect(service.repeatMode, RepeatMode.off);
      service.toggleRepeatMode();
      expect(service.repeatMode, RepeatMode.all);
    });
  });

  group('queue mutation API', () {
    test('addToQueue appends without disturbing the playlist', () {
      final tracks = playlist(2);
      final service = AudioPlayerService()
        ..seedForTest(playlist: tracks, currentIndex: 0, currentTrack: tracks[0]);
      final queued = sampleTrack(id: 'q1', title: 'Queued 1');

      service.addToQueue(queued);

      expect(service.queue.map((t) => t.id), ['q1']);
      expect(service.playlist, tracks);
    });

    test('removeFromQueue drops the entry at that index', () {
      final q = [sampleTrack(id: 'a'), sampleTrack(id: 'b'), sampleTrack(id: 'c')];
      final service = AudioPlayerService()
        ..seedForTest(currentTrack: sampleTrack(id: 'now'), queue: q);

      service.removeFromQueue(1);

      expect(service.queue.map((t) => t.id), ['a', 'c']);
    });

    test('removeFromQueue ignores an out-of-range index', () {
      final q = [sampleTrack(id: 'a')];
      final service = AudioPlayerService()
        ..seedForTest(currentTrack: sampleTrack(id: 'now'), queue: q);

      service.removeFromQueue(5);

      expect(service.queue.map((t) => t.id), ['a']);
    });

    test('moveInQueue reorders', () {
      final q = [sampleTrack(id: 'a'), sampleTrack(id: 'b'), sampleTrack(id: 'c')];
      final service = AudioPlayerService()
        ..seedForTest(currentTrack: sampleTrack(id: 'now'), queue: q);

      service.moveInQueue(0, 2);

      expect(service.queue.map((t) => t.id), ['b', 'c', 'a']);
    });
  });

  group('reorderUpcoming', () {
    test('sequential: reorders the playlist tail after currentIndex', () {
      final tracks = playlist(4);
      final service = AudioPlayerService()
        ..seedForTest(playlist: tracks, currentIndex: 0);

      // Move the last upcoming track (auto index 2, i.e. playlist[3]) to the
      // front of the upcoming section (auto index 0, i.e. playlist[1]).
      service.reorderUpcoming(2, 0);

      expect(
        service.playlist.map((t) => t.id),
        [tracks[0].id, tracks[3].id, tracks[1].id, tracks[2].id],
      );
    });

    test('shuffle: reorders the shuffle-order tail after shufflePos', () {
      final tracks = playlist(4);
      final service = AudioPlayerService()
        ..seedForTest(
          playlist: tracks,
          isShuffleEnabled: true,
          shuffleOrder: [2, 0, 3, 1],
          shufflePos: 0,
        );

      // Upcoming (shuffleOrder[1:]) is [0, 3, 1]; move auto index 2 (value 1)
      // to auto index 0.
      service.reorderUpcoming(2, 0);

      expect(service.shuffleOrderForTest, [2, 1, 0, 3]);
      expect(service.playlist, tracks); // shuffle reorder never touches playlist
    });

    test('no-op when the target is out of the upcoming range', () {
      final tracks = playlist(3);
      final service = AudioPlayerService()
        ..seedForTest(playlist: tracks, currentIndex: 1); // upcoming = [2] only

      service.reorderUpcoming(0, 5);

      expect(service.playlist.map((t) => t.id), tracks.map((t) => t.id));
    });
  });
}
