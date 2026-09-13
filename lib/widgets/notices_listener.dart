import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/notices.dart';

/// Shows every pending [Notices] message as a SnackBar, once.
///
/// Lives in the shell, so the SnackBar goes to the app-level
/// [ScaffoldMessenger] and is visible on every screen, the Now Playing route
/// included. The one place any module's one-shot failure reaches the user —
/// see [Notices] for what qualifies.
///
/// Renders nothing — it is a listener that happens to be in the tree.
class NoticesListener extends StatelessWidget {
  const NoticesListener({super.key});

  static const duration = Duration(seconds: 4);

  @override
  Widget build(BuildContext context) {
    final notices = context.watch<Notices>();
    if (notices.pending.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        // Drained here rather than in build, so a rebuild between the frame
        // and the callback can't show the same message twice. Newest wins
        // the screen: hiding the current one first means a burst of failures
        // reads as the last, not as a queue the user has to wait through.
        for (final message in notices.take()) {
          messenger
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(content: Text(message), duration: duration),
            );
        }
      });
    }
    return const SizedBox.shrink();
  }
}
