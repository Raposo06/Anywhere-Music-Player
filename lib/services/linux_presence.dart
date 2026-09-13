import 'dart:async';
import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';
import '../models/track.dart';
import 'now_playing_presence.dart';
import 'stream_url_resolver.dart';

/// Linux presence: MPRIS (Media Player Remote Interfacing Specification),
/// Linux's equivalent of Windows' SMTC — how hardware media keys,
/// desktop-shell media widgets and things like `playerctl` find and control
/// the app, over the `org.mpris.MediaPlayer2` D-Bus interface.
///
/// There is no ready-made package for this (the one MPRIS package on pub.dev
/// is a *client* for controlling other players, the wrong direction) and
/// neither audio_service nor media_kit's embedded libmpv provide it on Linux
/// — see docs/decisions.md. So the interface is implemented directly on the
/// `dbus` package, which is plain Dart and needs no native/platform code.
///
/// Construct only on Linux — `main()` picks the adapter by platform.
/// Best-effort throughout: a session bus can be unavailable (headless, CI),
/// and that must never take playback down with it.
class LinuxPresence implements NowPlayingPresence {
  LinuxPresence({required StreamUrlResolver resolver}) : _resolver = resolver;

  final StreamUrlResolver _resolver;

  PlaybackCommands? _commands;
  PlaybackSignals? _signals;
  StreamSubscription<bool>? _playingSubscription;
  bool _playing = false;

  DBusClient? _client;
  _MprisPlayerObject? _object;
  // Set at the first show(); once set, an init is in flight or done.
  Future<void>? _mprisInit;

  @override
  void bind(PlaybackCommands commands, PlaybackSignals signals) {
    _commands = commands;
    _signals = signals;
    // Remembered for the moment the bus registration resolves, so the first
    // status pushed is the real one rather than "Paused".
    _playingSubscription = signals.playing.listen((p) => _playing = p);
  }

  @override
  void show(Track track) {
    final artUrl = _resolver.resolveCoverUrl(track);
    // MPRIS init is deliberately lazy — the first show(), not bind() — so it
    // only ever happens if something actually plays, same as SMTC on
    // Windows. Chained, not awaited: show() is synchronous on the seam.
    _mprisInit ??= _initMpris();
    unawaited(
      _mprisInit!.then((_) {
        final object = _object;
        if (object == null) return;
        object.setTrack(track, artUrl: artUrl);
        object.setPlaying(_playing);
        unawaited(object.emitChanged(metadata: true, status: true));
      }),
    );
  }

  @override
  void setPlaying(bool playing) {
    final object = _object;
    if (object == null) return;
    object.setPlaying(playing);
    unawaited(object.emitChanged(status: true));
  }

  @override
  void clear() {
    final object = _object;
    if (object == null) return;
    object.clearTrack();
    unawaited(object.emitChanged(metadata: true, status: true));
  }

  /// Release the bus name and close the connection.
  @override
  void dispose() {
    _playingSubscription?.cancel();
    final client = _client;
    _client = null;
    _object = null;
    if (client != null) unawaited(client.close().catchError((Object _) {}));
  }

  /// Connects to the session bus, claims `org.mpris.MediaPlayer2.<name>`, and
  /// registers the player object at the (spec-fixed) `/org/mpris/MediaPlayer2`
  /// path.
  Future<void> _initMpris() async {
    final commands = _commands;
    final signals = _signals;
    if (commands == null || signals == null) return;
    DBusClient? client;
    try {
      client = DBusClient.session();
      final object = _MprisPlayerObject(commands, signals.position);
      await client.registerObject(object);

      final reply = await client.requestName(
        'org.mpris.MediaPlayer2.anywhere_music_player',
      );
      if (reply != DBusRequestNameReply.primaryOwner &&
          reply != DBusRequestNameReply.alreadyOwner) {
        // Another instance already owns the name — still registered on the
        // bus, just not the one media keys will reach. Not fatal.
        debugPrint('MPRIS: name request returned $reply (another instance?)');
      }
      _client = client;
      _object = object;
    } catch (e) {
      debugPrint('Failed to initialize MPRIS: $e');
      await client?.close();
    }
  }
}

/// The `/org/mpris/MediaPlayer2` object, implementing both
/// `org.mpris.MediaPlayer2` (app-level: identity, raise/quit) and
/// `org.mpris.MediaPlayer2.Player` (transport: play/pause/next/previous,
/// metadata, playback status) — the two interfaces the spec requires at that
/// one fixed path. See https://specifications.freedesktop.org/mpris-spec/.
///
/// Position is read on demand by property Get/GetAll — the spec explicitly
/// excludes it from PropertiesChanged — hence the getter rather than a value.
class _MprisPlayerObject extends DBusObject {
  _MprisPlayerObject(this._commands, this._position)
    : super(DBusObjectPath('/org/mpris/MediaPlayer2'));

  static const rootInterface = 'org.mpris.MediaPlayer2';
  static const playerInterface = 'org.mpris.MediaPlayer2.Player';

  final PlaybackCommands _commands;
  final Duration Function() _position;

  String _title = '';
  String _artist = '';
  String _album = '';
  String _artUrl = '';
  Duration? _length;
  String _trackId = '/org/mpris/MediaPlayer2/TrackList/NoTrack';
  String _playbackStatus = 'Stopped';

  void setTrack(Track track, {String? artUrl}) {
    _title = track.title;
    _artist = track.artist ?? '';
    _album = track.album ?? '';
    _artUrl = artUrl ?? '';
    _length = track.durationSeconds != null
        ? Duration(seconds: track.durationSeconds!)
        : null;
    // Object paths only allow [A-Za-z0-9_] between slashes — server-assigned
    // track ids are opaque and can contain hyphens (Navidrome's were UUIDs),
    // so sanitize rather than pass the id straight through.
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
    _playbackStatus = 'Stopped';
  }

  void setPlaying(bool playing) {
    _playbackStatus = playing ? 'Playing' : 'Paused';
  }

  /// Push what changed to anyone listening on the bus.
  Future<void> emitChanged({bool metadata = false, bool status = false}) =>
      emitPropertiesChanged(
        playerInterface,
        changedProperties: {
          if (status) 'PlaybackStatus': DBusString(_playbackStatus),
          if (metadata) 'Metadata': _metadata(),
        },
      );

  DBusValue _metadata() {
    final entries = <String, DBusValue>{
      'mpris:trackid': DBusObjectPath(_trackId),
      if (_title.isNotEmpty) 'xesam:title': DBusString(_title),
      if (_artist.isNotEmpty) 'xesam:artist': DBusArray.string([_artist]),
      if (_album.isNotEmpty) 'xesam:album': DBusString(_album),
      if (_artUrl.isNotEmpty) 'mpris:artUrl': DBusString(_artUrl),
      if (_length != null) 'mpris:length': DBusInt64(_length!.inMicroseconds),
    };
    return DBusDict.stringVariant(entries);
  }

  @override
  List<DBusIntrospectInterface> introspect() {
    DBusIntrospectMethod method(String name) => DBusIntrospectMethod(name);
    DBusIntrospectProperty prop(String name, String type) =>
        DBusIntrospectProperty(
          name,
          DBusSignature(type),
          access: DBusPropertyAccess.read,
        );

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
      case playerInterface:
        switch (methodCall.name) {
          case 'Play':
            _commands.play();
            return DBusMethodSuccessResponse();
          case 'Pause':
            _commands.pause();
            return DBusMethodSuccessResponse();
          case 'PlayPause':
            if (_playbackStatus == 'Playing') {
              _commands.pause();
            } else {
              _commands.play();
            }
            return DBusMethodSuccessResponse();
          case 'Stop':
            _commands.stop();
            return DBusMethodSuccessResponse();
          case 'Next':
            _commands.next();
            return DBusMethodSuccessResponse();
          case 'Previous':
            _commands.previous();
            return DBusMethodSuccessResponse();
        }
    }
    return DBusMethodErrorResponse.unknownMethod();
  }

  // The app-level properties never change, so Get and GetAll share them.
  static final _rootProperties = <String, DBusValue>{
    'CanQuit': const DBusBoolean(false),
    'CanRaise': const DBusBoolean(false),
    'HasTrackList': const DBusBoolean(false),
    'Identity': const DBusString('Anywhere Music Player'),
    // Matches packaging/arch's .desktop id — see docs/operations.md.
    'DesktopEntry': const DBusString('anywhere-music-player'),
    'SupportedUriSchemes': DBusArray.string(const []),
    'SupportedMimeTypes': DBusArray.string(const []),
  };

  // Capabilities are fixed: Next/Previous with nothing there simply stop,
  // and CanSeek is off because there is no Seek/SetPosition handler yet.
  Map<String, DBusValue> _playerProperties() => {
    'PlaybackStatus': DBusString(_playbackStatus),
    'Metadata': _metadata(),
    'Volume': const DBusDouble(1.0),
    'Position': DBusInt64(_position().inMicroseconds),
    'CanGoNext': const DBusBoolean(true),
    'CanGoPrevious': const DBusBoolean(true),
    'CanPlay': const DBusBoolean(true),
    'CanPause': const DBusBoolean(true),
    'CanSeek': const DBusBoolean(false),
    'CanControl': const DBusBoolean(true),
  };

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    final value = switch (interface) {
      rootInterface => _rootProperties[name],
      playerInterface => _playerProperties()[name],
      _ => null,
    };
    return value == null
        ? DBusMethodErrorResponse.unknownProperty()
        : DBusGetPropertyResponse(value);
  }

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async {
    return DBusGetAllPropertiesResponse(switch (interface) {
      rootInterface => _rootProperties,
      playerInterface => _playerProperties(),
      _ => const {},
    });
  }
}
