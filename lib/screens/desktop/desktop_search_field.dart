import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

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

class _DesktopSearchFieldState extends State<DesktopSearchField> {
  final _controller = TextEditingController();
  bool _hasText = false;

  @override
  void dispose() {
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
      child: TextField(
        controller: _controller,
        onChanged: _onChanged,
        style: const TextStyle(fontSize: 13, color: AppColors.text),
        cursorColor: AppColors.accent,
        decoration: InputDecoration(
          isDense: true,
          hintText: widget.hintText,
          contentPadding: const EdgeInsets.symmetric(vertical: 11),
          prefixIcon: const Icon(Icons.search, size: 16),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 38, minHeight: 20),
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
          suffixIconConstraints:
              const BoxConstraints(minWidth: 34, minHeight: 20),
        ),
      ),
    );
  }
}
