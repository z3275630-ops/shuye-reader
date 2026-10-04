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
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
  );
  Future<void> turn(VoidCallback action, String effect) async {
    if (busy) return;
    if (effect == 'none') {
      action();
      return;
    }
    busy = true;
    mode = effect;
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
  TurnPainter(this.image, this.progress, this.shader);
  @override
  void paint(Canvas c, Size size) {
    if (shader != null) {
      shader!.setFloat(0, size.width);
      shader!.setFloat(1, size.height);
      shader!.setFloat(2, progress);
      shader!.setImageSampler(0, image);
      c.drawRect(Offset.zero & size, Paint()..shader = shader);
    } else {
      c.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        Offset.zero & size,
        Paint()..color = Colors.white.withValues(alpha: 1 - progress),
      );
    }
  }

  @override
  bool shouldRepaint(TurnPainter old) =>
      old.progress != progress || old.image != image;
}
