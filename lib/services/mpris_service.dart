import 'dart:async';
import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';
import '../models/track.dart';

/// Service to handle Linux MPRIS (Media Player Remote Interfacing Specification)
/// integration. This is Linux's equivalent of Windows' SMTC — it's how hardware
/// media keys, desktop-shell media widgets, and things like `playerctl` find
/// and control the app, over the `org.mpris.MediaPlayer2` D-Bus interface.
///
/// There's no ready-made package for this (the one MPRIS package on pub.dev is
/// a *client* for controlling other players, the wrong direction) and neither
/// audio_service nor media_kit's embedded libmpv provide it on Linux — see
/// docs/decisions.md. So this implements the interface directly on the
/// `dbus` package, which is plain Dart and needs no native/platform code.
class MprisMediaService {
  static MprisMediaService? _instance;
  DBusClient? _client;
  _MprisPlayerObject? _object;
  bool _isInitialized = false;

  // Callbacks for transport commands arriving over D-Bus.
  VoidCallback? onPlay;
  VoidCallback? onPause;
  VoidCallback? onNext;
  VoidCallback? onPrevious;
  VoidCallback? onStop;

  // Live playback state, read on demand by property Get/GetAll — MPRIS
  // Position in particular is meant to be polled, not pushed (the spec
  // explicitly excludes it from PropertiesChanged).
  Duration Function()? positionProvider;

  MprisMediaService._();

  static MprisMediaService get instance {
    _instance ??= MprisMediaService._();
    return _instance!;
  }

  bool get isSupported => !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;

  /// Connects to the session bus, claims `org.mpris.MediaPlayer2.<name>`, and
  /// registers the player object at the (spec-fixed) `/org/mpris/MediaPlayer2`
  /// path. Best-effort: a session bus can be unavailable (headless/CI), and
  /// that must never take playback down with it.
  Future<void> initialize({
    VoidCallback? onPlay,
    VoidCallback? onPause,
    VoidCallback? onNext,
    VoidCallback? onPrevious,
    VoidCallback? onStop,
    Duration Function()? positionProvider,
  }) async {
    if (!isSupported || _isInitialized) return;

    this.onPlay = onPlay;
    this.onPause = onPause;
    this.onNext = onNext;
    this.onPrevious = onPrevious;
    this.onStop = onStop;
    this.positionProvider = positionProvider;

    try {
      final client = DBusClient.session();
      _client = client;
      _object = _MprisPlayerObject(this);
      await client.registerObject(_object!);

      final reply = await client.requestName(
        'org.mpris.MediaPlayer2.anywhere_music_player',
      );
      if (reply != DBusRequestNameReply.primaryOwner &&
          reply != DBusRequestNameReply.alreadyOwner) {
        // Another instance already owns the name — still registered on the
        // bus, just not the one media keys will reach. Not fatal.
        debugPrint('MPRIS: name request returned $reply (another instance?)');
      }

      _isInitialized = true;
    } catch (e) {
      debugPrint('Failed to initialize MPRIS: $e');
      await _client?.close();
      _client = null;
      _object = null;
    }
  }

  /// Update the metadata shown for the current track. [artUrl] is already
  /// resolved by the caller (see StreamUrlResolver) — this service doesn't
  /// mint URLs itself.
  Future<void> updateMetadata(Track track, {String? artUrl}) async {
    if (!isSupported || !_isInitialized || _object == null) return;
    _object!.setTrack(track, artUrl: artUrl);
    await _object!.emitPropertiesChanged(
      _MprisPlayerObject.playerInterface,
      changedProperties: {'Metadata': _object!.metadata()},
    );
  }

  /// Update playback status (play/pause/stop state).
  Future<void> updatePlaybackStatus({required bool isPlaying}) async {
    if (!isSupported || !_isInitialized || _object == null) return;
    _object!.setPlaying(isPlaying);
    await _object!.emitPropertiesChanged(
      _MprisPlayerObject.playerInterface,
      changedProperties: {
        'PlaybackStatus': DBusString(_object!.playbackStatus),
      },
    );
  }

  /// Nothing playing anymore.
  Future<void> clear() async {
    if (!isSupported || !_isInitialized || _object == null) return;
    _object!.clearTrack();
    await _object!.emitPropertiesChanged(
      _MprisPlayerObject.playerInterface,
      changedProperties: {
        'PlaybackStatus': DBusString(_object!.playbackStatus),
        'Metadata': _object!.metadata(),
      },
    );
  }

  /// Release the bus name and close the connection.
  Future<void> dispose() async {
    onPlay = null;
    onPause = null;
    onNext = null;
    onPrevious = null;
    onStop = null;
    positionProvider = null;
    try {
      await _client?.close();
    } catch (_) {}
    _client = null;
    _object = null;
    _isInitialized = false;
  }
}

/// The `/org/mpris/MediaPlayer2` object, implementing both
/// `org.mpris.MediaPlayer2` (app-level: identity, raise/quit) and
/// `org.mpris.MediaPlayer2.Player` (transport: play/pause/next/previous,
/// metadata, playback status) — the two interfaces the spec requires at that
/// one fixed path. See https://specifications.freedesktop.org/mpris-spec/.
class _MprisPlayerObject extends DBusObject {
  _MprisPlayerObject(this._service)
      : super(DBusObjectPath('/org/mpris/MediaPlayer2'));

  static const rootInterface = 'org.mpris.MediaPlayer2';
  static const playerInterface = 'org.mpris.MediaPlayer2.Player';

  final MprisMediaService _service;

  String _title = '';
  String _artist = '';
  String _album = '';
  String _artUrl = '';
  Duration? _length;
  String _trackId = '/org/mpris/MediaPlayer2/TrackList/NoTrack';
  String playbackStatus = 'Stopped';

  void setTrack(Track track, {String? artUrl}) {
    _title = track.title;
    _artist = track.artist ?? '';
    _album = track.album ?? '';
    _artUrl = artUrl ?? '';
    _length = track.durationSeconds != null
        ? Duration(seconds: track.durationSeconds!)
        : null;
    // Object paths only allow [A-Za-z0-9_] between slashes — track ids
    // (Navidrome UUIDs) can contain hyphens, so sanitize rather than pass
    // the id straight through.
    final safeId = track.id.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
    _trackId = '/org/mpris/MediaPlayer2/Track/$safeId';
  }

  void clearTrack() {
    _title = '';
    _artist = '';
    _album = '';
    _artUrl = '';
    _length = null;
    _trackId = '/org/mpris/MediaPlayer2/TrackList/NoTrack';
    playbackStatus = 'Stopped';
  }

  void setPlaying(bool playing) {
    playbackStatus = playing ? 'Playing' : 'Paused';
  }

  DBusValue metadata() {
    final entries = <String, DBusValue>{
      'mpris:trackid': DBusObjectPath(_trackId),
      if (_title.isNotEmpty) 'xesam:title': DBusString(_title),
      if (_artist.isNotEmpty)
        'xesam:artist': DBusArray.string([_artist]),
      if (_album.isNotEmpty) 'xesam:album': DBusString(_album),
      if (_artUrl.isNotEmpty) 'mpris:artUrl': DBusString(_artUrl),
      if (_length != null)
        'mpris:length': DBusInt64(_length!.inMicroseconds),
    };
    return DBusDict.stringVariant(entries);
  }

  @override
  List<DBusIntrospectInterface> introspect() {
    DBusIntrospectMethod method(String name) => DBusIntrospectMethod(name);
    DBusIntrospectProperty prop(String name, String type) =>
        DBusIntrospectProperty(name, DBusSignature(type),
            access: DBusPropertyAccess.read);

    return [
      DBusIntrospectInterface(
        rootInterface,
        methods: [method('Raise'), method('Quit')],
        properties: [
          prop('CanQuit', 'b'),
          prop('CanRaise', 'b'),
          prop('HasTrackList', 'b'),
          prop('Identity', 's'),
          prop('DesktopEntry', 's'),
          prop('SupportedUriSchemes', 'as'),
          prop('SupportedMimeTypes', 'as'),
        ],
      ),
      DBusIntrospectInterface(
        playerInterface,
        methods: [
          method('Next'),
          method('Previous'),
          method('Pause'),
          method('PlayPause'),
          method('Stop'),
          method('Play'),
        ],
        properties: [
          prop('PlaybackStatus', 's'),
          prop('Metadata', 'a{sv}'),
          prop('Volume', 'd'),
          prop('Position', 'x'),
          prop('CanGoNext', 'b'),
          prop('CanGoPrevious', 'b'),
          prop('CanPlay', 'b'),
          prop('CanPause', 'b'),
          prop('CanSeek', 'b'),
          prop('CanControl', 'b'),
        ],
      ),
    ];
  }

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    switch (methodCall.interface) {
      case rootInterface:
        switch (methodCall.name) {
          case 'Raise':
          case 'Quit':
            // Not supported — CanRaise/CanQuit both report false.
            return DBusMethodErrorResponse.notSupported();
        }
        break;
      case playerInterface:
        switch (methodCall.name) {
          case 'Play':
            _service.onPlay?.call();
            return DBusMethodSuccessResponse();
          case 'Pause':
            _service.onPause?.call();
            return DBusMethodSuccessResponse();
          case 'PlayPause':
            if (playbackStatus == 'Playing') {
              _service.onPause?.call();
            } else {
              _service.onPlay?.call();
            }
            return DBusMethodSuccessResponse();
          case 'Stop':
            _service.onStop?.call();
            return DBusMethodSuccessResponse();
          case 'Next':
            _service.onNext?.call();
            return DBusMethodSuccessResponse();
          case 'Previous':
            _service.onPrevious?.call();
            return DBusMethodSuccessResponse();
        }
        break;
    }
    return DBusMethodErrorResponse.unknownMethod();
  }

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    switch (interface) {
      case rootInterface:
        switch (name) {
          case 'CanQuit':
            return DBusGetPropertyResponse(const DBusBoolean(false));
          case 'CanRaise':
            return DBusGetPropertyResponse(const DBusBoolean(false));
          case 'HasTrackList':
            return DBusGetPropertyResponse(const DBusBoolean(false));
          case 'Identity':
            return DBusGetPropertyResponse(
                const DBusString('Anywhere Music Player'));
          case 'DesktopEntry':
            // Matches packaging/arch's .desktop id — see docs/operations.md.
            return DBusGetPropertyResponse(
                const DBusString('anywhere-music-player'));
          case 'SupportedUriSchemes':
            return DBusGetPropertyResponse(DBusArray.string(const []));
          case 'SupportedMimeTypes':
            return DBusGetPropertyResponse(DBusArray.string(const []));
        }
        break;
      case playerInterface:
        switch (name) {
          case 'PlaybackStatus':
            return DBusGetPropertyResponse(DBusString(playbackStatus));
          case 'Metadata':
            return DBusGetPropertyResponse(metadata());
          case 'Volume':
            return DBusGetPropertyResponse(const DBusDouble(1.0));
          case 'Position':
            final position = _service.positionProvider?.call() ?? Duration.zero;
            return DBusGetPropertyResponse(
                DBusInt64(position.inMicroseconds));
          case 'CanGoNext':
          case 'CanGoPrevious':
          case 'CanPlay':
          case 'CanPause':
          case 'CanControl':
            return DBusGetPropertyResponse(const DBusBoolean(true));
          case 'CanSeek':
            return DBusGetPropertyResponse(const DBusBoolean(false));
        }
        break;
    }
    return DBusMethodErrorResponse.unknownProperty();
  }

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async {
    switch (interface) {
      case rootInterface:
        return DBusGetAllPropertiesResponse({
          'CanQuit': const DBusBoolean(false),
          'CanRaise': const DBusBoolean(false),
          'HasTrackList': const DBusBoolean(false),
          'Identity': const DBusString('Anywhere Music Player'),
          'DesktopEntry': const DBusString('anywhere-music-player'),
          'SupportedUriSchemes': DBusArray.string(const []),
          'SupportedMimeTypes': DBusArray.string(const []),
        });
      case playerInterface:
        final position = _service.positionProvider?.call() ?? Duration.zero;
        return DBusGetAllPropertiesResponse({
          'PlaybackStatus': DBusString(playbackStatus),
          'Metadata': metadata(),
          'Volume': const DBusDouble(1.0),
          'Position': DBusInt64(position.inMicroseconds),
          'CanGoNext': const DBusBoolean(true),
          'CanGoPrevious': const DBusBoolean(true),
          'CanPlay': const DBusBoolean(true),
          'CanPause': const DBusBoolean(true),
          'CanSeek': const DBusBoolean(false),
          'CanControl': const DBusBoolean(true),
        });
    }
    return DBusGetAllPropertiesResponse(const {});
  }
}
