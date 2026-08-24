import 'package:anywhere_music_player/models/track.dart';

/// A minimal, valid [Track] for widget tests. No cover art by default, so
/// rendering never depends on a real network image fetch. streamUrl/cover
/// URLs aren't fields any more — see StreamUrlResolver, resolved at the
/// point of use — so there's nothing to fake here beyond [coverArtId].
Track sampleTrack({
  String id = '1',
  String title = 'Sample Track',
  String? artist,
  int? durationSeconds = 180,
  double? replayGainDb,
  String? coverArtId,
}) => Track(
  id: id,
  title: title,
  path: '$title.mp3',
  coverArtId: coverArtId,
  folderPath: '',
  createdAt: DateTime(2024),
  artist: artist,
  durationSeconds: durationSeconds,
  replayGainDb: replayGainDb,
);
