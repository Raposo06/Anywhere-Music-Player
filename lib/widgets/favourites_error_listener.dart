import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/favourites_service.dart';

/// Surfaces a failed star/unstar as a SnackBar, once each.
///
/// [FavouritesService] applies a toggle locally and rolls it back if the
/// server refuses (see its `toggle`), and a heart quietly reverting is
/// otherwise indistinguishable from a mis-click. Lives in the shell because
/// hearts appear in several places; the SnackBar goes to the app-level
/// [ScaffoldMessenger], so it is still visible over the Now Playing route.
///
/// Renders nothing — it is a listener that happens to be in the tree.
class FavouritesErrorListener extends StatelessWidget {
  const FavouritesErrorListener({super.key});

  @override
  Widget build(BuildContext context) {
    final error = context.select<FavouritesService, String?>((f) => f.error);
    if (error != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(error),
              duration: const Duration(seconds: 4),
            ),
          );
        // Cleared as soon as it's shown, so the same failure can't re-fire on
        // an unrelated rebuild.
        context.read<FavouritesService>().clearError();
      });
    }
    return const SizedBox.shrink();
  }
}
