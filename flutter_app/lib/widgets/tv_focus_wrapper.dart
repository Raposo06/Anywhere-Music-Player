import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Wrapper widget that handles Android TV D-Pad navigation
///
/// This widget automatically handles:
/// - D-Pad center/select button presses
/// - Enter key presses
/// - Visual focus indication for TV interfaces
class TvFocusWrapper extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final FocusNode? focusNode;
  final bool autofocus;

  const TvFocusWrapper({
    super.key,
    required this.child,
    this.onPressed,
    this.focusNode,
    this.autofocus = false,
  });

  @override
  State<TvFocusWrapper> createState() => _TvFocusWrapperState();
}

class _TvFocusWrapperState extends State<TvFocusWrapper> {
  late FocusNode _focusNode;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  void _onFocusChange() {
    setState(() {
      _isFocused = _focusNode.hasFocus;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      onKeyEvent: (node, event) {
        if (widget.onPressed == null) {
          return KeyEventResult.ignored;
        }

        // Handle D-Pad center button and Enter key
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.space) {
            widget.onPressed!();
            return KeyEventResult.handled;
          }
        }

        return KeyEventResult.ignored;
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          border: _isFocused
              ? Border.all(
                  color: Theme.of(context).primaryColor,
                  width: 3,
                )
              : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: widget.child,
      ),
    );
  }
}
