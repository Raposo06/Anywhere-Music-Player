import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anywhere_music_player/widgets/centred_message.dart';

// CentredMessage is the phone's shared empty/error state — promoted out of two
// byte-identical private copies (favourites + playlists) so the third screen
// (home) and any future one get the same thing, including the scroll-wrap that
// keeps a RefreshIndicator pullable on an empty list.
void main() {
  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
        MaterialApp(home: Scaffold(body: child)),
      );

  testWidgets('renders the icon and title', (tester) async {
    await pump(
      tester,
      const CentredMessage(icon: Icons.favorite_border, title: 'Nothing here'),
    );

    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    expect(find.text('Nothing here'), findsOneWidget);
  });

  testWidgets('shows the subtitle and action only when given', (tester) async {
    await pump(
      tester,
      const CentredMessage(icon: Icons.error_outline, title: 'Just a title'),
    );
    expect(find.byType(FilledButton), findsNothing);

    await pump(
      tester,
      CentredMessage(
        icon: Icons.error_outline,
        title: 'Failed',
        subtitle: 'Try again in a moment',
        action: FilledButton(onPressed: () {}, child: const Text('Retry')),
      ),
    );
    expect(find.text('Try again in a moment'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);
  });

  testWidgets('stays scrollable so a RefreshIndicator can still be pulled', (
    tester,
  ) async {
    await pump(
      tester,
      const CentredMessage(icon: Icons.inbox, title: 'Empty'),
    );

    final scrollable = tester.widget<Scrollable>(find.byType(Scrollable));
    expect(scrollable.physics, isA<AlwaysScrollableScrollPhysics>());
  });
}
