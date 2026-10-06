import 'package:flutter/material.dart';

enum EditorialScene { library, notes, journey, balance }

/// Small, static editorial drawings: paper shapes, ink contours and one accent.
/// Each context has its own motif, rather than repeating the home brand mark.
class EditorialArt extends StatelessWidget {
  final EditorialScene scene;
  final double width, height;
  const EditorialArt(
    this.scene, {
    super.key,
    this.width = 160,
    this.height = 100,
  });
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: SizedBox(
        width: width,
        height: height,
        child: CustomPaint(painter: _EditorialPainter(scene, colors)),
      ),
    );
  }
}

class _EditorialPainter extends CustomPainter {
  final EditorialScene scene;
  final ColorScheme colors;
  const _EditorialPainter(this.scene, this.colors);
  static final _bridge = Path()
    ..moveTo(34, 65)
    ..cubicTo(52, 7, 112, 8, 129, 65);
  static final _hill = Path()
    ..moveTo(31, 77)
    ..lineTo(63, 31)
    ..lineTo(78, 48)
    ..lineTo(108, 19)
    ..lineTo(139, 77)
    ..close();
  static final _pen = Path()
    ..moveTo(104, 61)
    ..lineTo(128, 31)
    ..quadraticBezierTo(136, 23, 141, 30)
    ..lineTo(115, 66)
    ..lineTo(102, 71)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    final scale = (size.width / 160).clamp(0.0, size.height / 100);
    canvas.save();
    canvas.translate(
      (size.width - scale * 160) / 2,
      (size.height - scale * 100) / 2,
    );
    canvas.scale(scale);
    final fill = Paint()..color = colors.surface;
    final ink = Paint()
      ..color = colors.onSurface
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    void paper(Rect r, {double radius = 2}) {
      final shape = RRect.fromRectAndRadius(r, Radius.circular(radius));
      canvas.drawRRect(shape, fill..color = colors.surface);
      canvas.drawRRect(shape, ink);
    }

    canvas.drawCircle(const Offset(120, 32), 22, fill..color = colors.primary);
    switch (scene) {
      case EditorialScene.library:
        canvas.drawLine(const Offset(24, 80), const Offset(140, 78), ink);
        paper(const Rect.fromLTWH(33, 29, 25, 49));
        paper(const Rect.fromLTWH(62, 18, 28, 60));
        canvas.save();
        canvas.translate(105, 74);
        canvas.rotate(-.19);
        paper(const Rect.fromLTWH(0, -48, 23, 48));
        canvas.restore();
        canvas.drawLine(const Offset(39, 40), const Offset(50, 40), ink);
        canvas.drawLine(const Offset(69, 29), const Offset(83, 29), ink);
        canvas.drawLine(const Offset(69, 34), const Offset(83, 34), ink);
      case EditorialScene.notes:
        paper(const Rect.fromLTWH(40, 20, 61, 65));
        canvas.drawLine(const Offset(56, 37), const Offset(89, 37), ink);
        canvas.drawLine(const Offset(56, 48), const Offset(87, 48), ink);
        canvas.drawLine(const Offset(56, 60), const Offset(75, 60), ink);
        for (final y in [29.0, 42.0, 55.0, 68.0, 79.0]) {
          canvas.drawArc(Rect.fromLTWH(35, y - 4, 13, 8), .3, 5, false, ink);
        }
        canvas.drawPath(_pen, fill..color = colors.surface);
        canvas.drawPath(_pen, ink);
      case EditorialScene.journey:
        canvas.drawPath(_hill, fill..color = colors.surface);
        canvas.drawPath(_hill, ink);
        canvas.drawLine(const Offset(108, 19), const Offset(108, 4), ink);
        canvas.drawLine(const Offset(108, 5), const Offset(124, 8), ink);
        canvas.drawLine(const Offset(124, 8), const Offset(108, 12), ink);
        canvas.drawLine(const Offset(24, 85), const Offset(141, 85), ink);
      case EditorialScene.balance:
        canvas.drawOval(
          const Rect.fromLTWH(16, 59, 32, 18),
          fill..color = colors.surface,
        );
        canvas.drawOval(const Rect.fromLTWH(115, 59, 32, 18), fill);
        canvas.drawPath(_bridge, ink);
        canvas.drawCircle(
          const Offset(34, 65),
          3,
          ink..style = PaintingStyle.fill,
        );
        canvas.drawCircle(const Offset(129, 65), 3, ink);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_EditorialPainter old) =>
      old.scene != scene || old.colors != colors;
}
