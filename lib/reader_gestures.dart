import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// A selectable paragraph owns Flutter's tap recognizer. Observe brief pointer
/// taps without taking its long-press and drag selection gestures away.
class ReaderTapSurface extends StatefulWidget {
  final Widget child;
  final bool Function() canTurn;
  final ValueChanged<Offset> onTap;
  final GestureDragEndCallback onHorizontalDragEnd;
  final GestureDragStartCallback? onHorizontalDragStart;
  final GestureDragUpdateCallback? onHorizontalDragUpdate;
  final GestureDragCancelCallback? onHorizontalDragCancel;
  const ReaderTapSurface({
    super.key,
    required this.child,
    required this.canTurn,
    required this.onTap,
    required this.onHorizontalDragEnd,
    this.onHorizontalDragStart,
    this.onHorizontalDragUpdate,
    this.onHorizontalDragCancel,
  });
  @override
  State<ReaderTapSurface> createState() => _ReaderTapSurfaceState();
}

class _ReaderHorizontalDrag extends HorizontalDragGestureRecognizer {
  void acceptSwipe() => resolve(GestureDisposition.accepted);
  void yieldToSelection() => resolve(GestureDisposition.rejected);
}

class _ReaderTapSurfaceState extends State<ReaderTapSurface> {
  Offset? down;
  Offset? touchOrigin;
  bool held = false;
  _ReaderHorizontalDrag? horizontal;
  Timer? hold;
  int? pointer;
  bool allowed = false, dragCancelled = false;
  @override
  void dispose() {
    hold?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RawGestureDetector(
    behavior: HitTestBehavior.opaque,
    gestures: {
      _ReaderHorizontalDrag:
          GestureRecognizerFactoryWithHandlers<_ReaderHorizontalDrag>(
            () => _ReaderHorizontalDrag(),
            (recognizer) {
              horizontal = recognizer;
              recognizer
                ..dragStartBehavior = DragStartBehavior.down
                ..onStart = (d) {
                  // Over page whitespace this can win the arena on pointer down, before
                  // any movement. Only pointer travel / holding should disqualify a tap.
                  if (widget.canTurn()) widget.onHorizontalDragStart?.call(d);
                }
                ..onUpdate = (d) {
                  if (widget.canTurn()) widget.onHorizontalDragUpdate?.call(d);
                }
                ..onCancel = widget.onHorizontalDragCancel
                ..onEnd = (d) {
                  if (!dragCancelled && widget.canTurn()) {
                    widget.onHorizontalDragEnd(d);
                  } else {
                    widget.onHorizontalDragCancel?.call();
                  }
                };
            },
          ),
    },
    child: Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) {
        if (pointer != null) {
          down = null;
          touchOrigin = null;
          return;
        }
        pointer = e.pointer;
        dragCancelled = false;
        down = e.localPosition;
        touchOrigin = e.localPosition;
        held = false;
        hold?.cancel();
        hold = Timer(const Duration(milliseconds: 250), () {
          down = null;
          held = true;
          // Leave a stationary press to native text selection.
          horizontal?.yieldToSelection();
        });
        allowed = widget.canTurn();
      },
      onPointerMove: (e) {
        final origin = touchOrigin;
        if (e.pointer == pointer &&
            origin != null &&
            !held &&
            allowed &&
            widget.canTurn()) {
          final travel = e.localPosition - origin;
          if (travel.dx.abs() > kTouchSlop &&
              travel.dx.abs() > travel.dy.abs()) {
            // Listener sees movement before pointer-router recognizers do.
            // Resolve a clear horizontal swipe before the editable paragraph
            // can claim it as drag-selection; long presses remain untouched.
            horizontal?.acceptSwipe();
          }
        }
        if (down != null && (e.localPosition - down!).distance > 12) {
          down = null;
        }
      },
      onPointerCancel: (_) {
        dragCancelled = true;
        widget.onHorizontalDragCancel?.call();
        hold?.cancel();
        pointer = null;
        down = null;
        touchOrigin = null;
      },
      onPointerUp: (e) {
        if (e.pointer != pointer) return;
        pointer = null;
        touchOrigin = null;
        hold?.cancel();
        final isTap = down != null;
        down = null;
        if (!isTap) return;
        if (mounted && allowed && widget.canTurn()) {
          widget.onTap(e.localPosition);
        }
      },
      child: widget.child,
    ),
  );
}
