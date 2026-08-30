import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../widgets/desktop/search_focus_scope.dart';

/// The 250px pill search field in the top-right of a content header.
///
/// Owns its own controller so callers only supply [onChanged] — every desktop
/// screen that searches does the same thing with it, and none of them need
/// the text back except through the callback.
class DesktopSearchField extends StatefulWidget {
  final ValueChanged<String> onChanged;
  final String hintText;
  final double width;

  const DesktopSearchField({
    super.key,
    required this.onChanged,
    this.hintText = 'Search...',
    this.width = 250,
  });

  @override
  State<DesktopSearchField> createState() => _DesktopSearchFieldState();
}

class _DesktopSearchFieldState extends State<DesktopSearchField>
    implements SearchFocusTarget {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _hasText = false;

  /// Held from didChangeDependencies so dispose can deregister without a
  /// context lookup, which is not safe once the element is defunct.
  SearchFocusScope? _scope;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = SearchFocusScope.maybeOf(context);
    if (scope == _scope) return;
    _scope?.unregister(this);
    _scope = scope;
    scope?.register(this);
  }

  /// Ctrl + F lands here. Selecting the existing query means the next
  /// keystroke replaces it — the same thing a browser's find bar does, and
  /// what you want when re-searching rather than extending a search.
  @override
  bool get hasSearchFocus => mounted && _focusNode.hasFocus;

  /// Whether this field could actually take focus right now.
  ///
  /// The desktop shell keeps every destination mounted in an `IndexedStack`,
  /// which wraps the ones that are not showing in `ExcludeFocus` — so the
  /// Library's search box is still registered while Playlists is on screen.
  /// Asking the ancestors settles it: requesting focus on an excluded node is
  /// a silent no-op, which would look like the shortcut being broken.
  bool get _isFocusable {
    if (!mounted || !_focusNode.canRequestFocus) return false;
    return _focusNode.ancestors.every((n) => n.descendantsAreFocusable);
  }

  @override
  bool focusSearch() {
    if (!_isFocusable) return false;
    _focusNode.requestFocus();
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
    return true;
  }

  @override
  void dispose() {
    _scope?.unregister(this);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    final hasText = value.isNotEmpty;
    if (hasText != _hasText) setState(() => _hasText = hasText);
    widget.onChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      // Matches the transport controls' "Action (Ctrl+X)" convention — an
      // unadvertised shortcut is one nobody finds.
      child: Tooltip(
        message: 'Search (Ctrl+F)',
        child: TextField(
          controller: _controller,
          focusNode: _focusNode,
          onChanged: _onChanged,
          style: const TextStyle(fontSize: 13, color: AppColors.text),
          cursorColor: AppColors.accent,
          decoration: InputDecoration(
            isDense: true,
            hintText: widget.hintText,
            contentPadding: const EdgeInsets.symmetric(vertical: 11),
            prefixIcon: const Icon(Icons.search, size: 16),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 38,
              minHeight: 20,
            ),
            suffixIcon: _hasText
                ? IconButton(
                    icon: const Icon(Icons.close, size: 15),
                    splashRadius: 14,
                    tooltip: 'Clear',
                    onPressed: () {
                      _controller.clear();
                      _onChanged('');
                    },
                  )
                : null,
            suffixIconConstraints: const BoxConstraints(
              minWidth: 34,
              minHeight: 20,
            ),
          ),
        ),
      ),
    );
  }
}
