import 'package:flutter/widgets.dart';

/// A search field that Ctrl + F can jump to.
///
/// Implemented by `DesktopSearchField`'s state rather than exposing a
/// [FocusNode], so the field decides what "focus me" means — it also selects
/// what is already typed, so the next keystroke replaces the old query instead
/// of appending to it.
abstract class SearchFocusTarget {
  /// Take the keyboard. Returns false if this field is no longer on screen,
  /// which is how the registry notices stale entries.
  bool focusSearch();

  /// Whether this field currently owns the keyboard. Lets the shortcut layer
  /// tell "typing in the search box" (where Ctrl + F should still select the
  /// query) from "typing in a dialog" (where it must not steal focus).
  bool get hasSearchFocus;
}

/// Lets a search field anywhere in the subtree be focused from the window-level
/// shortcut layer above it.
///
/// Inherited widgets pass data *down*, and the shortcut sits *above* the
/// screens that own search fields — so the field registers itself on mount and
/// the shortcut asks for the most recently registered one. Last in wins: a
/// drill-down screen's field is the one on screen, not the list behind it.
class SearchFocusScope extends InheritedWidget {
  final void Function(SearchFocusTarget) register;
  final void Function(SearchFocusTarget) unregister;

  const SearchFocusScope({
    super.key,
    required this.register,
    required this.unregister,
    required super.child,
  });

  /// Looked up without creating a dependency — a field registering itself has
  /// no reason to rebuild when the scope changes, and this is called from
  /// `didChangeDependencies`, where a real dependency would be wasteful.
  static SearchFocusScope? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<SearchFocusScope>();

  @override
  bool updateShouldNotify(SearchFocusScope oldWidget) =>
      register != oldWidget.register || unregister != oldWidget.unregister;
}
