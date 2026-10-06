import 'package:flutter/material.dart';

/// Book/leaf geometry adapted from the repository's Claude-style concept SVG.
/// Paths are cached; theme changes only replace paint colors. No SVG decoder,
/// bitmap, animation or fixed-size page mockup is shipped.
class ShuyeBookLeaf extends StatelessWidget {
  final double width, height;
  const ShuyeBookLeaf({super.key, this.width = 144, this.height = 100});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: SizedBox(
        width: width,
        height: height,
        child: CustomPaint(
          painter: _BookLeafPainter(
            colors.onSurface,
            colors.surface,
            colors.primary,
            colors.secondaryContainer,
          ),
        ),
      ),
    );
  }
}

class _BookLeafPainter extends CustomPainter {
  final Color ink, paper, accent, soft;
  const _BookLeafPainter(this.ink, this.paper, this.accent, this.soft);

  static final _book = Path()
    ..moveTo(128, 748)
    ..cubicTo(260, 642, 430, 631, 650, 704)
    ..cubicTo(683, 715, 704, 734, 714, 756)
    ..cubicTo(724, 734, 747, 715, 780, 704)
    ..cubicTo(1005, 632, 1170, 646, 1302, 742)
    ..cubicTo(1137, 728, 966, 741, 795, 800)
    ..cubicTo(762, 811, 735, 828, 714, 848)
    ..cubicTo(692, 828, 666, 811, 632, 800)
    ..cubicTo(455, 740, 291, 727, 128, 748)
    ..close();
  static final _leaf = Path()
    ..moveTo(714, 758)
    ..cubicTo(683, 640, 640, 552, 568, 484)
    ..cubicTo(618, 451, 685, 472, 724, 533)
    ..cubicTo(767, 451, 842, 343, 1028, 260)
    ..cubicTo(1044, 348, 1014, 434, 950, 493)
    ..cubicTo(876, 560, 799, 637, 714, 758)
    ..close();
  static final _lines = Path()
    ..moveTo(152, 752)
    ..cubicTo(320, 705, 477, 720, 631, 779)
    ..moveTo(184, 805)
    ..cubicTo(337, 763, 487, 777, 630, 827)
    ..moveTo(1275, 750)
    ..cubicTo(1113, 706, 953, 720, 796, 779)
    ..moveTo(1241, 805)
    ..cubicTo(1091, 763, 944, 777, 799, 827)
    ..moveTo(714, 759)
    ..cubicTo(752, 610, 820, 452, 986, 301);

  @override
  void paint(Canvas canvas, Size size) {
    // Preserve the illustration's proportions, including its circular accent.
    final scale = (size.width / 1260).clamp(0.0, size.height / 750);
    canvas.save();
    canvas.translate(
      (size.width - 1260 * scale) / 2,
      (size.height - 750 * scale) / 2,
    );
    canvas.scale(scale);
    canvas.translate(-80, -150);
    final fill = Paint();
    canvas.drawCircle(const Offset(1080, 350), 165, fill..color = soft);
    canvas.drawCircle(const Offset(1080, 350), 118, fill..color = accent);
    final stroke = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 24
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final path in [_book, _leaf]) {
      canvas.drawPath(path, fill..color = paper);
      canvas.drawPath(path, stroke);
    }
    canvas.drawPath(_lines, stroke..strokeWidth = 19);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BookLeafPainter old) =>
      ink != old.ink ||
      paper != old.paper ||
      accent != old.accent ||
      soft != old.soft;
}
