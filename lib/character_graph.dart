import 'dart:math' as math;

import 'appearance.dart';

import 'package:flutter/material.dart';

class CharacterGraph extends StatelessWidget {
  final List<Map<String, dynamic>> characters;
  const CharacterGraph({super.key, required this.characters});
  @override
  Widget build(BuildContext context) {
    final names = <String>{};
    final links = <(String, String, String)>[];
    for (final item in characters) {
      final name = (item['人物'] as String? ?? '').trim();
      if (name.isEmpty) continue;
      names.add(name);
      for (final associated in (item['关联人物'] as String? ?? '').split(
        RegExp(r'[,，、;；\n]'),
      )) {
        final other = associated.trim();
        if (other.isEmpty || other == name) continue;
        names.add(other);
        links.add((name, other, item['关系说明'] as String? ?? '关联'));
      }
    }
    return Scaffold(
      appBar: AppBar(title: const Text('人物关系图')),
      body: names.isEmpty
          ? const Center(child: Text('先添加人物，填写“关联人物”和“关系说明”。'))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    '共 ${names.length} 位人物；可双指缩放与拖动。图中最多显示前 30 位，多位关联人物用逗号分隔。',
                  ),
                ),
                Expanded(
                  child: InteractiveViewer(
                    constrained: false,
                    minScale: .3,
                    maxScale: 3,
                    child: CustomPaint(
                      size: const Size(900, 900),
                      painter: _GraphPainter(
                        names.take(30).toList(),
                        links,
                        Theme.of(context).colorScheme,
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  height: 140,
                  child: ListView(
                    children: [
                      for (final link in links)
                        ListTile(
                          dense: true,
                          title: Text('${link.$1} → ${link.$2}'),
                          subtitle: Text(link.$3),
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _GraphPainter extends CustomPainter {
  final List<String> names;
  final List<(String, String, String)> links;
  final ColorScheme colors;
  _GraphPainter(this.names, this.links, this.colors);
  void text(Canvas canvas, String value, Offset center, {double width = 100}) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          color: colors.onSurface,
          fontSize: 14,
          fontFamily: ShuyeStyle.fontFamily,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: width);
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final points = <String, Offset>{};
    for (var i = 0; i < names.length; i++) {
      final angle = -math.pi / 2 + 2 * math.pi * i / names.length;
      points[names[i]] =
          center + Offset(math.cos(angle), math.sin(angle)) * 340;
    }
    final line = Paint()
      ..color = colors.outline
      ..strokeWidth = 1.5;
    for (final link in links) {
      final from = points[link.$1], to = points[link.$2];
      if (from == null || to == null) continue;
      final vector = to - from, unit = vector / vector.distance;
      final end = to - unit * 57, start = from + unit * 57;
      canvas.drawLine(start, end, line);
      final normal = Offset(-unit.dy, unit.dx);
      canvas.drawLine(end, end - unit * 12 + normal * 6, line);
      canvas.drawLine(end, end - unit * 12 - normal * 6, line);
      final mid = (from + to) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: mid, width: 100, height: 42),
          const Radius.circular(8),
        ),
        Paint()..color = colors.surface,
      );
      text(canvas, link.$3, mid, width: 96);
    }
    for (final e in points.entries) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: e.value, width: 108, height: 48),
          const Radius.circular(12),
        ),
        Paint()..color = colors.secondaryContainer,
      );
      text(canvas, e.key, e.value);
    }
  }

  @override
  bool shouldRepaint(covariant _GraphPainter oldDelegate) => true;
}
