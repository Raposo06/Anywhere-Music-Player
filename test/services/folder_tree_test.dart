import 'package:flutter_test/flutter_test.dart';
import 'package:anywhere_music_player/models/track.dart';
import 'package:anywhere_music_player/services/folder_tree.dart';

Track _track(String path, {String? id, String? coverArtId}) => Track(
  id: id ?? path,
  title: path.split('/').last,
  path: path,
  folderPath: path.contains('/')
      ? path.substring(0, path.lastIndexOf('/'))
      : '',
  coverArtId: coverArtId,
  createdAt: DateTime(2026),
);

void main() {
  test('empty tree answers every query without throwing', () {
    const none = <String>[];
    expect(FolderTree.empty.topLevelFolders(), isEmpty);
    expect(FolderTree.empty.rootTracks(), isEmpty);
    expect(FolderTree.empty.allTracksUnder('Anime'), isEmpty);
    expect(FolderTree.empty.searchFolders('x'), isEmpty);
    expect(FolderTree.empty.isFlattenedRoot(''), isFalse);
    expect(FolderTree.empty.trackById('1'), isNull);
    expect(none, isEmpty);
  });

  test('files each track under its own path', () {
    final tree = FolderTree.from([
      _track('Anime/Naruto/01.mp3'),
      _track('Anime/Bleach/02.mp3'),
      _track('Rock/03.mp3'),
    ]);

    expect(
      tree.topLevelFolders().map((f) => f.folderPath),
      ['Anime', 'Rock'],
    );
    expect(
      tree.contentsOf('Anime').folders.map((f) => f.folderPath),
      ['Anime/Bleach', 'Anime/Naruto'],
    );
    expect(tree.allTracksUnder('Anime').length, 2);
  });

  test('a loose track lands in rootTracks, not a folder', () {
    final tree = FolderTree.from([
      _track('loose.mp3'),
      _track('Anime/01.mp3'),
    ]);

    expect(tree.rootTracks().map((t) => t.path), ['loose.mp3']);
    expect(tree.topLevelFolders().map((f) => f.folderPath), ['Anime']);
  });

  group('the flatten rule', () {
    test('a single top-level folder with children is flattened away', () {
      final tree = FolderTree.from([
        _track('music/Anime/01.mp3'),
        _track('music/Rock/02.mp3'),
      ]);

      expect(
        tree.topLevelFolders().map((f) => f.folderPath),
        ['music/Anime', 'music/Rock'],
      );
      expect(tree.isFlattenedRoot('music'), isTrue);
    });

    test('two top-level folders are not flattened', () {
      final tree = FolderTree.from([
        _track('Anime/01.mp3'),
        _track('Rock/02.mp3'),
      ]);

      expect(tree.isFlattenedRoot('Anime'), isFalse);
      expect(tree.topLevelFolders().length, 2);
    });

    test('a single top-level folder with no subfolders is not flattened', () {
      final tree = FolderTree.from([_track('music/01.mp3')]);

      expect(tree.isFlattenedRoot('music'), isFalse);
      expect(tree.topLevelFolders().map((f) => f.folderPath), ['music']);
    });

    test('the flattened folder\'s own loose tracks surface as root tracks', () {
      final tree = FolderTree.from([
        _track('music/loose.mp3'),
        _track('music/Anime/01.mp3'),
      ]);

      expect(tree.isFlattenedRoot('music'), isTrue);
      expect(tree.rootTracks().map((t) => t.path), ['music/loose.mp3']);
    });
  });

  test('searchFolders matches leaf names only, shallowest first', () {
    final tree = FolderTree.from([
      _track('Anime/01.mp3'),
      _track('Anime/Naruto/02.mp3'),
      _track('Rock/Animals/03.mp3'),
    ]);

    expect(
      tree.searchFolders('ani').map((f) => f.folderPath),
      ['Anime', 'Rock/Animals'],
    );
    // 'Anime/Naruto' is a child of a match but does not match itself.
    expect(tree.searchFolders('naruto').map((f) => f.folderPath),
        ['Anime/Naruto']);
    expect(tree.searchFolders('   '), isEmpty);
  });

  test('a folder inherits the first cover art it can find', () {
    final tree = FolderTree.from([
      _track('Anime/Naruto/01.mp3'),
      _track('Anime/Naruto/02.mp3', coverArtId: 'cover-2'),
    ]);

    expect(tree.contentsOf('Anime').folders.single.coverArtId, 'cover-2');
  });
}
