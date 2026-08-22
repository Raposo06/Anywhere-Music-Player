import 'package:anywhere_music_player/models/track.dart';

/// A minimal, valid [Track] for widget tests. No cover art by default, so
/// rendering never depends on a real network image fetch.
Track sampleTrack({
  String id = '1',
  String title = 'Sample Track',
  String? artist,
  int? durationSeconds = 180,
  double? replayGainDb,
}) => Track(
  id: id,
  title: title,
  filename: '$title.mp3',
  streamUrl: 'https://navidrome.example.com/rest/stream?id=$id',
  folderPath: '',
  createdAt: DateTime(2024),
  artist: artist,
  durationSeconds: durationSeconds,
  replayGainDb: replayGainDb,
);
