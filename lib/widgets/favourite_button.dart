import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/track.dart';
import '../services/favourites_service.dart';
import '../theme/app_colors.dart';

/// The heart that stars [track], filled when it is a favourite.
///
/// Selects on this one track's starred state, so starring something else
/// doesn't rebuild every row on screen.
///
/// [visible] draws an unstarred heart at zero opacity rather than omitting it
/// — the row keeps its width whether or not the pointer is over it, so hearts
/// stay in a column and nothing shifts on hover. A *starred* heart ignores
/// [visible] and always shows; it is state, not an affordance.
///
/// Shared by both layouts. Only desktop passes [visible] (rows hide the heart
/// until hovered); phone leaves it at the default, since there is no hover to
/// reveal it with. The accent tint is the same either way —
/// `colorScheme.primary` *is* [AppColors.accent], see app_theme.dart.
class FavouriteButton extends StatelessWidget {
  final Track track;
  final double size;

  /// Whether an unstarred heart should be shown. Rows pass their hover state.
  final bool visible;

  const FavouriteButton({
    super.key,
    required this.track,
    this.size = 16,
    this.visible = true,
  });

  @override
  Widget build(BuildContext context) {
    return Selector<FavouritesService, bool>(
      selector: (_, favourites) => favourites.isStarred(track.id),
      builder: (context, isStarred, _) {
        final shown = isStarred || visible;
        return IgnorePointer(
          ignoring: !shown,
          child: AnimatedOpacity(
            opacity: shown ? 1 : 0,
            duration: AppMetrics.stateTransition,
            child: IconButton(
              icon: Icon(isStarred ? Icons.favorite : Icons.favorite_border),
              iconSize: size,
              color: isStarred ? AppColors.accent : AppColors.faint,
              hoverColor: AppColors.surface2,
              padding: EdgeInsets.zero,
              constraints: BoxConstraints.tightFor(
                width: size + 14,
                height: size + 14,
              ),
              tooltip: isStarred
                  ? 'Remove from favourites'
                  : 'Add to favourites',
              onPressed: () => context.read<FavouritesService>().toggle(track),
            ),
          ),
        );
      },
    );
  }
}
