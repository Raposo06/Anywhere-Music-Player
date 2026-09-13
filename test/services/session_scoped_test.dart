import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:anywhere_music_player/main.dart';
import 'package:anywhere_music_player/services/auth_service.dart';
import 'package:anywhere_music_player/services/notices.dart';
import 'package:anywhere_music_player/services/session_scoped.dart';
import 'package:anywhere_music_player/services/subsonic_api_service.dart';

// The rebind guard used to exist three times, once per session-scoped
// module, and was tested none of those times — testing it meant testing it
// three times. It exists once now, so these are the tests for all three.

SubsonicApiService _client(String user) => SubsonicApiService(
  serverUrl: 'https://gonic.example.com',
  username: user,
  password: 'secret',
);

/// An [AuthService] whose session can be swapped without a login round trip.
class _FakeAuth extends AuthService {
  SubsonicApiService? _api;

  @override
  SubsonicApiService? get apiService => _api;

  void bind(SubsonicApiService? api) {
    _api = api;
    notifyListeners();
  }
}

class _Probe extends SessionScoped {
  _Probe(super.api, {super.notices});
}

class _Loader extends SessionScoped with LoadStatus {
  _Loader(super.api, this._body);

  final Future<void> Function() _body;
  int bodyRuns = 0;
  int notifications = 0;

  Future<void> load() => runLoad('things', (_) async {
    bodyRuns++;
    await _body();
  });

  @override
  void notifyListeners() {
    notifications++;
    super.notifyListeners();
  }
}

void main() {
  group('sessionScoped', () {
    late _FakeAuth auth;
    late List<_Probe> seen;

    Future<void> pumpTree(WidgetTester tester) => tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<Notices>(create: (_) => Notices()),
          ChangeNotifierProvider<AuthService>.value(value: auth),
          sessionScoped<_Probe>((api, notices) => _Probe(api, notices: notices)),
        ],
        child: Builder(
          builder: (context) {
            final probe = context.watch<_Probe>();
            if (seen.isEmpty || !identical(seen.last, probe)) seen.add(probe);
            return const SizedBox();
          },
        ),
      ),
    );

    setUp(() {
      auth = _FakeAuth();
      seen = [];
    });

    testWidgets('builds against a null client before login', (tester) async {
      await pumpTree(tester);

      expect(seen.single.api, isNull);
    });

    testWidgets('hands every instance the tree’s one Notices', (tester) async {
      await pumpTree(tester);
      final treeNotices = tester
          .element(find.byType(SizedBox))
          .read<Notices>();
      expect(seen.single.notices, same(treeNotices));

      // A rebuilt instance after login shares it too — the shell drains one
      // sink, so a module writing to a private one would fail silently.
      auth.bind(_client('alice'));
      await tester.pump();
      expect(seen, hasLength(2));
      expect(seen.last.notices, same(treeNotices));
    });

    testWidgets('keeps the instance while the client is the same', (
      tester,
    ) async {
      final api = _client('alice');
      auth.bind(api);
      await pumpTree(tester);

      // A notification that doesn't change the session — any other auth state
      // change — must not throw the module away and its loaded data with it.
      auth.bind(api);
      await tester.pump();

      expect(seen, hasLength(1));
      expect(seen.single.api, same(api));
    });

    testWidgets('rebinds on login, re-login and logout', (tester) async {
      await pumpTree(tester);

      auth.bind(_client('alice'));
      await tester.pump();

      // Logout disposes the client, so an instance that kept hold of it would
      // answer the next request with "Client is already closed".
      auth.bind(null);
      await tester.pump();

      final second = _client('bob');
      auth.bind(second);
      await tester.pump();

      expect(seen, hasLength(4));
      expect(seen.map((p) => p.api?.username), [null, 'alice', null, 'bob']);
      expect(seen.last.api, same(second));
    });
  });

  group('LoadStatus.runLoad', () {
    test('does nothing at all without a client', () async {
      final loader = _Loader(null, () async {});

      await loader.load();

      expect(loader.bodyRuns, 0);
      expect(loader.isLoading, isFalse);
      expect(loader.isLoaded, isFalse);
      expect(loader.notifications, 0);
    });

    test('owns the flags around the fetch, and notifies on both edges', () async {
      late bool loadingDuringFetch;
      final loader = _Loader(_client('alice'), () async {
        loadingDuringFetch = true;
      });
      expect(loader.isLoading, isFalse);

      await loader.load();

      expect(loadingDuringFetch, isTrue);
      expect(loader.isLoading, isFalse);
      expect(loader.isLoaded, isTrue);
      expect(loader.error, isNull);
      expect(loader.notifications, 2);
    });

    test('a failure leaves isLoaded false, so empty stays distinguishable', () async {
      final loader = _Loader(_client('alice'), () async {
        throw StateError('server said no');
      });

      await loader.load();

      expect(loader.isLoaded, isFalse);
      expect(loader.isLoading, isFalse);
      expect(loader.error, contains('Could not load things'));
      expect(loader.error, contains('server said no'));
    });

    test('concurrent calls collapse into the first', () async {
      final gate = Completer<void>();
      final loader = _Loader(_client('alice'), () => gate.future);

      final first = loader.load();
      await loader.load(); // returns immediately — the first is in flight
      expect(loader.bodyRuns, 1);

      gate.complete();
      await first;
      expect(loader.bodyRuns, 1);
      expect(loader.isLoaded, isTrue);

      // Once it has settled, loading again is allowed: this collapses
      // concurrent calls, it does not cache.
      await loader.load();
      expect(loader.bodyRuns, 2);
    });

    test('a fresh load clears the previous error before it starts', () async {
      var fail = true;
      final loader = _Loader(_client('alice'), () async {
        if (fail) throw StateError('nope');
      });

      await loader.load();
      expect(loader.error, isNotNull);

      fail = false;
      await loader.load();
      expect(loader.error, isNull);
      expect(loader.isLoaded, isTrue);
    });
  });
}
