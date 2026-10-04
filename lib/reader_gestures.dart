import 'dart:async';

import 'package:flutter/material.dart';

/// A selectable paragraph owns Flutter's tap recognizer. Observe brief pointer
/// taps without taking its long-press and drag selection gestures away.
class ReaderTapSurface extends StatefulWidget {
  final Widget child;
  final bool Function() canTurn;
  final ValueChanged<Offset> onTap;
  final VoidCallback onDoubleTap;
  final GestureDragEndCallback onHorizontalDragEnd;
  const ReaderTapSurface({
    super.key,
    required this.child,
    required this.canTurn,
    required this.onTap,
    required this.onDoubleTap,
    required this.onHorizontalDragEnd,
  });
  @override
  State<ReaderTapSurface> createState() => _ReaderTapSurfaceState();
}

class _ReaderTapSurfaceState extends State<ReaderTapSurface> {
  Offset? down;
  Timer? hold;
  int? pointer;
  bool allowed = false;
  Timer? pending;
  Offset? previous;
  @override
  void dispose() {
    pending?.cancel();
    hold?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onHorizontalDragEnd: widget.onHorizontalDragEnd,
    child: Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) {
        if (pointer != null) {
          down = null;
          return;
        }
        pointer = e.pointer;
        down = e.localPosition;
        hold?.cancel();
        hold = Timer(const Duration(milliseconds: 250), () => down = null);
        allowed = widget.canTurn();
      },
      onPointerMove: (e) {
        if (down != null && (e.localPosition - down!).distance > 12) {
          down = null;
        }
      },
      onPointerCancel: (_) {
        hold?.cancel();
        pointer = null;
        down = null;
      },
      onPointerUp: (e) {
        if (e.pointer != pointer) return;
        pointer = null;
        hold?.cancel();
        final isTap = down != null;
        down = null;
        if (!isTap) return;
        if (pending?.isActive == true &&
            previous != null &&
            (e.localPosition - previous!).distance < 32) {
          pending!.cancel();
          widget.onDoubleTap();
          return;
        }
        pending?.cancel();
        previous = e.localPosition;
        final location = e.localPosition;
        final permit = allowed;
        pending = Timer(const Duration(milliseconds: 280), () {
          if (mounted && permit && widget.canTurn()) widget.onTap(location);
        });
      },
      child: widget.child,
    ),
  );
}
