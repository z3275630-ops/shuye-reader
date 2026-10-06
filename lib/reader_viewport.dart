import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Toolbars occupy the page margins. A settings dock has its own space below
/// the page; only opening that dock or resizing the window changes pagination.
class ReaderViewport extends StatefulWidget {
  final Widget child, topControls, bottomControls;
  final Widget? bottomPanel;
  final VoidCallback? closePanel;
  final bool immersive;
  static const headerExtent = 56.0;
  static double footerExtent(BuildContext context) => math.max(
    64,
    MediaQuery.textScalerOf(context).scale(12) *
            (Theme.of(context).textTheme.bodyMedium?.height ?? 1.5) *
            2 +
        16,
  );
  const ReaderViewport({
    super.key,
    required this.child,
    required this.topControls,
    required this.bottomControls,
    required this.immersive,
    this.bottomPanel,
    this.closePanel,
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
  Widget build(BuildContext context) => PopScope(
    canPop: widget.bottomPanel == null,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) widget.closePanel?.call();
    },
    child: LayoutBuilder(
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
        final panelHeight = widget.bottomPanel == null
            ? 0.0
            : math.min(320.0, canvas!.height * .45);
        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: canvas!.height - panelHeight,
              child: Padding(padding: safe, child: widget.child),
            ),
            if (!widget.immersive) ...[
              Positioned(
                top: safe.top,
                left: safe.left,
                right: safe.right,
                height: ReaderViewport.headerExtent,
                child: widget.topControls,
              ),
              if (widget.bottomPanel == null)
                Positioned(
                  bottom: safe.bottom,
                  left: 0,
                  right: 0,
                  height: ReaderViewport.footerExtent(context),
                  child: Material(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    child: widget.bottomControls,
                  ),
                ),
            ],
            if (widget.bottomPanel != null)
              Positioned(
                key: const ValueKey('reader-settings-dock'),
                bottom: 0,
                left: 0,
                right: 0,
                height: panelHeight,
                child: Material(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  child: widget.bottomPanel!,
                ),
              ),
          ],
        );
      },
    ),
  );
}
