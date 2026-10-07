import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shuye_reader/appearance.dart';
import 'package:shuye_reader/models.dart';
import 'package:shuye_reader/reader.dart';

import 'preview_fonts.dart';

void main() {
  test(
    'Claude paper round trips without changing existing paper or custom fonts',
    () {
      final old = ReaderSettings(theme: 'paper')
        ..extra['reader.background'] = 'F4EDDF'
        ..extra['reader.customFont'] = 'Imported Reader Font';
      final restored = ReaderSettings.fromJson(old.toJson());
      expect(restored.theme, 'follow');
      expect(readerColors(restored)[0], const Color(0xfff4eddf));
      expect(readerFont(restored), 'Imported Reader Font');
      final claude = ReaderSettings.fromJson(
        ReaderSettings(theme: 'claude').toJson(),
      );
      expect(claude.theme, 'follow');
      expect(readerColors(claude), [
        ShuyeStyle.canvas,
        applicationTheme(Brightness.light).colorScheme.onSurface,
      ]);
      expect(readerFont(claude), ShuyeStyle.readerFontFamily);
      final sans = ReaderSettings.fromJson(
        ReaderSettings(font: 'sans').toJson(),
      );
      expect(readerFont(sans), ShuyeStyle.fontFamily);
      sans.extra['reader.customFont'] = 'Imported Reader Font';
      expect(readerFont(sans), 'Imported Reader Font');
      expect(
        readerColors(ReaderSettings(theme: 'night'))[0],
        const Color(0xff212121),
      );
    },
  );

  for (final brightness in Brightness.values) {
    test(
      'interface uses clear sans while reading retains its own font: $brightness',
      () {
        final theme = applicationTheme(brightness);
        for (final style in [
          theme.textTheme.headlineLarge,
          theme.textTheme.headlineSmall,
          theme.textTheme.bodyLarge,
          theme.textTheme.bodyMedium,
          theme.textTheme.labelLarge,
          theme.appBarTheme.titleTextStyle,
          theme.dialogTheme.titleTextStyle,
          theme.listTileTheme.titleTextStyle,
          theme.chipTheme.labelStyle,
          theme.inputDecorationTheme.hintStyle,
        ]) {
          expect(style!.fontFamily, ShuyeStyle.fontFamily);
        }
      },
    );
  }

  testWidgets(
    'real serif font justifies long lines and paginates complete text',
    (tester) async {
      await loadShuyeSerif(tester);
      const paragraph = '风翻过书页，文字慢慢清晰。让文字左右对齐，读过的每一句话，都留在原来的位置。';
      final body = List.filled(
        12,
        '$paragraph\n\nEnglish words and an emoji 😀 stay intact.\n',
      ).join();
      const style = TextStyle(
        fontFamily: ShuyeStyle.readerFontFamily,
        fontSize: 20,
        height: 1.85,
        letterSpacing: .35,
      );
      for (final width in [264.0, 337.0]) {
        for (final scale in [1.0, 1.5]) {
          final scaler = TextScaler.linear(scale);
          final pages = paginate(body, style, width, 460, scaler);
          expect(pages.map((p) => body.substring(p.start, p.end)).join(), body);
          for (final page in pages) {
            final painter = TextPainter(
              text: TextSpan(
                text: body.substring(page.start, page.end),
                style: style,
              ),
              textAlign: ShuyeStyle.readerAlignment,
              textDirection: TextDirection.ltr,
              textScaler: scaler,
            )..layout(maxWidth: width);
            expect(painter.height, lessThanOrEqualTo(460));
            expect(
              painter.computeLineMetrics().every(
                (line) => line.width <= width + .01,
              ),
              isTrue,
            );
            painter.dispose();
          }
        }
      }
      final justified = TextPainter(
        text: const TextSpan(text: paragraph, style: style),
        textAlign: ShuyeStyle.readerAlignment,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 337);
      final lines = justified.computeLineMetrics();
      expect(lines.first.width, closeTo(337, .01));
      expect(lines.last.width, lessThan(337));
      justified.dispose();
    },
  );
}
