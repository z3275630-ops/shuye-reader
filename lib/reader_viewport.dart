import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Chrome and transient system bars never change the page's layout constraints.
class ReaderViewport extends StatefulWidget {
  final Widget child, topControls, bottomControls;
  final bool immersive;
  const ReaderViewport({
    super.key,
    required this.child,
    required this.topControls,
    required this.bottomControls,
    required this.immersive,
  });
  @override
  State<ReaderViewport> createState() => _ReaderViewportState();
}

class _ReaderViewportState extends State<ReaderViewport> {
  Size? canvas;
  Size? lastSize;
  EdgeInsets? lastInsets;
  EdgeInsets safe = EdgeInsets.zero;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final padding = MediaQuery.viewPaddingOf(context);
      final size = box.biggest;
      final resized =
          canvas == null ||
          canvas!.width != size.width ||
          (size != lastSize && padding == lastInsets);
      if (resized) {
        canvas = box.biggest;
        safe = EdgeInsets.fromLTRB(
          padding.left,
          math.max(24, padding.top),
          padding.right,
          math.max(20, padding.bottom),
        );
      }
      lastSize = size;
      lastInsets = padding;
      return Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: canvas!.height,
            child: Padding(padding: safe, child: widget.child),
          ),
          if (!widget.immersive) ...[
            Positioned(top: 0, left: 0, right: 0, child: widget.topControls),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                top: false,
                child: Material(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  child: widget.bottomControls,
                ),
              ),
            ),
          ],
        ],
      );
    },
  );
}
