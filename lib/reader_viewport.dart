import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Controls never change the page's layout. Settings crop its visible lower
/// portion while retaining the complete canvas and current reading position.
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
              child: ClipRect(
                key: const ValueKey('reader-visible-page'),
                child: OverflowBox(
                  alignment: Alignment.topCenter,
                  minHeight: canvas!.height,
                  maxHeight: canvas!.height,
                  child: Padding(padding: safe, child: widget.child),
                ),
              ),
            ),
            ...[
              Positioned(
                top: safe.top,
                left: safe.left,
                right: safe.right,
                height: ReaderViewport.headerExtent,
                child: ReaderChrome(
                  visible: !widget.immersive,
                  top: true,
                  child: widget.topControls,
                ),
              ),
              if (widget.bottomPanel == null)
                Positioned(
                  bottom: safe.bottom,
                  left: 0,
                  right: 0,
                  height: ReaderViewport.footerExtent(context),
                  child: ReaderChrome(
                    visible: !widget.immersive,
                    top: false,
                    child: Material(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      child: widget.bottomControls,
                    ),
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

class ReaderChrome extends StatelessWidget {
  final bool visible, top;
  final Widget child;
  const ReaderChrome({
    super.key,
    required this.visible,
    required this.top,
    required this.child,
  });
  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: !visible,
    child: ExcludeSemantics(
      excluding: !visible,
      child: AnimatedSwitcher(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 150),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: Offset(0, top ? -.08 : .08),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        ),
        child: visible
            ? KeyedSubtree(key: const ValueKey('visible'), child: child)
            : const SizedBox(key: ValueKey('hidden')),
      ),
    ),
  );
}
