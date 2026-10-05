import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class PageTurnSurface extends StatefulWidget {
  final Widget child;
  final Color color;
  const PageTurnSurface({super.key, required this.child, required this.color});
  @override
  State<PageTurnSurface> createState() => PageTurnSurfaceState();
}

class PageTurnSurfaceState extends State<PageTurnSurface>
    with SingleTickerProviderStateMixin {
  final boundary = GlobalKey();
  ui.Image? snapshot;
  ui.FragmentShader? shader;
  bool busy = false;
  String mode = 'none';
  int direction = 1;
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
  );
  Future<void> turn(
    VoidCallback action,
    String effect, {
    int direction = 1,
  }) async {
    if (busy) return;
    if (effect == 'none') {
      action();
      return;
    }
    busy = true;
    mode = effect;
    this.direction = direction;
    try {
      if (effect == 'curl') {
        shader ??= (await ui.FragmentProgram.fromAsset(
          'shaders/page_curl.frag',
        )).fragmentShader();
      }
      if (!mounted) return;
      final render =
          boundary.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (render == null || render.debugNeedsPaint) {
        action();
        return;
      }
      snapshot = await render.toImage(pixelRatio: 1.5);
      if (!mounted) {
        snapshot?.dispose();
        snapshot = null;
        return;
      }
      action();
      controller.duration = Duration(
        milliseconds: effect == 'slide' ? 300 : 360,
      );
      setState(() {});
      await controller.forward(from: 0).orCancel;
    } catch (_) {
      if (mounted && snapshot == null) action();
    } finally {
      if (mounted) {
        setState(() {
          snapshot?.dispose();
          snapshot = null;
        });
      }
      busy = false;
    }
  }

  @override
  void dispose() {
    controller.dispose();
    snapshot?.dispose();
    shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      RepaintBoundary(
        key: boundary,
        child: ColoredBox(color: widget.color, child: widget.child),
      ),
      if (snapshot != null)
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: controller,
              builder: (c, w) => CustomPaint(
                painter: TurnPainter(
                  snapshot!,
                  controller.value,
                  mode == 'curl' ? shader : null,
                  mode: mode,
                  direction: direction,
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

class TurnPainter extends CustomPainter {
  final ui.Image image;
  final double progress;
  final ui.FragmentShader? shader;
  final String mode;
  final int direction;
  TurnPainter(
    this.image,
    this.progress,
    this.shader, {
    this.mode = 'slide',
    this.direction = 1,
  });
  @override
  void paint(Canvas c, Size size) {
    final src = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    final dst = Offset.zero & size;
    if (shader != null) {
      shader!.setFloat(0, size.width);
      shader!.setFloat(1, size.height);
      shader!.setFloat(2, progress);
      shader!.setImageSampler(0, image);
      c.drawRect(Offset.zero & size, Paint()..shader = shader);
    } else if (mode == 'fade') {
      // Cross-fade the outgoing page: modulate its alpha instead of tinting it
      // white, which used to blind the screen and dissolve the old page.
      c.drawImageRect(
        image,
        src,
        dst,
        Paint()
          ..colorFilter = ColorFilter.mode(
            Colors.white.withValues(alpha: 1 - progress),
            BlendMode.dstIn,
          ),
      );
    } else {
      // Horizontal slide: the outgoing page glides away in the reading
      // direction and reveals the incoming page beneath it, with a soft
      // shadow cast onto the revealed page by the moving page's edge.
      final dx = -progress * size.width * (direction >= 0 ? 1 : -1);
      c.save();
      c.translate(dx, 0);
      c.drawImageRect(image, src, dst, Paint());
      c.restore();
      final forward = direction >= 0;
      final edge = forward
          ? size.width - progress * size.width
          : progress * size.width;
      final shadow = Rect.fromLTWH(
        forward ? edge : edge - 28,
        0,
        28,
        size.height,
      );
      c.drawRect(
        shadow,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(shadow.left, 0),
            Offset(shadow.right, 0),
            [
              forward
                  ? Colors.transparent
                  : Colors.black.withValues(alpha: .16),
              forward
                  ? Colors.black.withValues(alpha: .16)
                  : Colors.transparent,
            ],
          ),
      );
    }
  }

  @override
  bool shouldRepaint(TurnPainter old) =>
      old.progress != progress ||
      old.image != image ||
      old.mode != mode ||
      old.direction != direction;
}
