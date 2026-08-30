import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';
import 'desktop_primitives.dart';

/// The two top-level destinations the sidebar switches between. Desktop
/// replaces the phone's bottom tab bar with this; the destinations themselves
/// are unchanged.
enum SidebarDestination { library, allTracks, favourites }

/// The fixed 224px navigation rail: who you are on top, where you can go
/// below.
class Sidebar extends StatelessWidget {
  final SidebarDestination selected;
  final ValueChanged<SidebarDestination> onSelect;
  final VoidCallback onSignOut;

  const Sidebar({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    final username = context.select<AuthService, String>(
      (auth) => auth.currentUser?.username ?? 'User',
    );
    final initial = username.isEmpty ? '?' : username[0].toUpperCase();

    return Container(
      width: AppMetrics.sidebarWidth,
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.accentSoft,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: AppColors.accentText,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  username,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
              ),
              // The mock's glyph here is a sign-out arrow, and sign-out is
              // what the old app bar put in this position — so that is what
              // it does, rather than opening a settings screen the app
              // doesn't have.
              _SidebarIconButton(
                icon: Icons.logout,
                tooltip: 'Sign out',
                onPressed: onSignOut,
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 20),
          _NavItem(
            icon: Icons.folder_outlined,
            label: 'Library',
            active: selected == SidebarDestination.library,
            onTap: () => onSelect(SidebarDestination.library),
          ),
          const SizedBox(height: 4),
          _NavItem(
            icon: Icons.library_music_outlined,
            label: 'All Tracks',
            active: selected == SidebarDestination.allTracks,
            onTap: () => onSelect(SidebarDestination.allTracks),
          ),
          const SizedBox(height: 4),
          _NavItem(
            icon: Icons.favorite_border,
            label: 'Favourites',
            active: selected == SidebarDestination.favourites,
            onTap: () => onSelect(SidebarDestination.favourites),
          ),
        ],
      ),
    );
  }
}

/// One nav row. Active gets the accent-soft pill plus an accent icon and
/// full-weight label; inactive stays muted.
class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return HoverRow(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      background: active ? AppColors.accentSoft : null,
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: active ? AppColors.accent : AppColors.muted,
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: active ? FontWeight.w600 : FontWeight.w500,
              color: active ? AppColors.text : AppColors.muted,
            ),
          ),
        ],
      ),
    );
  }
}

/// The 28px square icon affordance in the sidebar header.
class _SidebarIconButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _SidebarIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  State<_SidebarIconButton> createState() => _SidebarIconButtonState();
}

class _SidebarIconButtonState extends State<_SidebarIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: AppMetrics.stateTransition,
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _hovered ? AppColors.surface2 : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              widget.icon,
              size: 15,
              color: _hovered ? AppColors.text : AppColors.faint,
            ),
          ),
        ),
      ),
    );
  }
}
