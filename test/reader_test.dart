import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shuye_reader/reader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('pagination covers every character and fits actual view metrics', () {
    final text = List.filled(100, '山间来信，Hello 世界。😀\n').join();
    const style = TextStyle(fontSize: 20, height: 1.8, letterSpacing: .35);
    for (final scaler in [TextScaler.noScaling, TextScaler.linear(1.5)]) {
      final pages = paginate(text, style, 300, 450, scaler);
      expect(pages.length, greaterThan(1));
      expect(pages.map((p) => text.substring(p.start, p.end)).join(), text);
      for (final p in pages) {
        final painter = TextPainter(
          text: TextSpan(text: text.substring(p.start, p.end), style: style),
          textDirection: TextDirection.ltr,
          textScaler: scaler,
        )..layout(maxWidth: 300);
        expect(
          painter.height,
          lessThanOrEqualTo(450),
          reason: 'page ${p.start}-${p.end}; scale ${scaler.scale(1)}',
        );
        painter.dispose();
        if (p.end < text.length) {
          expect(
            text.codeUnitAt(p.end - 1) < 0xd800 ||
                text.codeUnitAt(p.end - 1) > 0xdbff,
            isTrue,
          );
        }
      }
    }
  });
}
