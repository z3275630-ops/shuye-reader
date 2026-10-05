import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shuye_reader/appearance.dart';
import 'package:shuye_reader/home_dashboard.dart';
import 'package:shuye_reader/statistics_period.dart';
import 'package:shuye_reader/reader.dart';

import 'preview_fonts.dart';

class _NonlinearScaler extends TextScaler {
  const _NonlinearScaler();
  @override
  double scale(double size) => size * (size < 18 ? 1.8 : 1.3);
  @override
  double get textScaleFactor => 1.8;
}

void main() {
  test(
    'reading selection follows paper with visible handles and readable ink',
    () {
      double contrast(Color a, Color b) {
        final x = a.computeLuminance(), y = b.computeLuminance();
        return (x > y ? x + .05 : y + .05) / (x > y ? y + .05 : x + .05);
      }

      for (final scheme in readerSchemes.values) {
        final selection = readerSelectionTheme(scheme);
        final highlighted = Color.alphaBlend(
          selection.selectionColor!,
          scheme[0],
        );
        expect(
          contrast(selection.selectionHandleColor!, scheme[0]),
          greaterThanOrEqualTo(3),
        );
        expect(contrast(scheme[1], highlighted), greaterThanOrEqualTo(4.5));
      }
      final night = readerSchemes['night']!;
      expect(
        contrast(
          Color.alphaBlend(
            readerSelectionTheme(night).selectionColor!,
            night[0],
          ),
          night[0],
        ),
        greaterThan(1.6),
      );
    },
  );
  for (final scale in [1.5, 2.25]) {
    testWidgets(
      'reader footer keeps three-digit pages and touch targets at 320dp, scale $scale',
      (tester) async {
        await loadShuyeSerif(tester);
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var actions = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: applicationTheme(Brightness.light),
            builder: (c, child) => MediaQuery(
              data: MediaQuery.of(c)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: ReaderFooter(
                  page: 600,
                  pages: 600,
                  progress: 1,
                  ink: Colors.black,
                  outline: () => actions++,
                  previous: () => actions++,
                  next: () => actions++,
                ),
              ),
            ),
          ),
        );
        expect(find.text('600 / 600 页'), findsOneWidget);
        expect(find.text('100%'), findsOneWidget);
        for (final button in find.byType(IconButton).evaluate()) {
          expect(
            tester.getSize(find.byWidget(button.widget)).width,
            greaterThanOrEqualTo(48),
          );
          expect(
            tester.getSize(find.byWidget(button.widget)).height,
            greaterThanOrEqualTo(48),
          );
          await tester.tap(find.byWidget(button.widget));
        }
        expect(actions, 3);
        expect(tester.getRect(find.text('100%')).right, lessThanOrEqualTo(320));
        expect(tester.takeException(), isNull);
      },
    );
  }
  test(
    'app preference preserves nonlinear accessibility scale at every size',
    () {
      for (final factor in [.85, 1.0, 1.5]) {
        final scaler = ApplicationTextScaler(const _NonlinearScaler(), factor);
        expect(scaler.scale(14), closeTo(25.2 * factor, .0001));
        expect(scaler.scale(24), closeTo(31.2 * factor, .0001));
      }
    },
  );
  test(
    'seven natural dates include leap day and cross year, exclude future data',
    () {
      for (final end in [DateTime(2024, 3, 2), DateTime(2026, 1, 2)]) {
        final days = recentReadingDays({
          dayKey(end): 120,
          '2099-01-01': 999,
        }, end);
        expect(days.length, 7);
        expect(days.last, (end, 120));
        expect(days.take(6).every((day) => day.$2 == 0), isTrue);
        expect(days.map((day) => dayKey(day.$1)).toSet().length, 7);
      }
      expect(
        recentReadingDays({}, DateTime(2024, 3, 2))[3].$1,
        DateTime(2024, 2, 28),
      );
      expect(
        recentReadingDays({}, DateTime(2024, 3, 2))[4].$1,
        DateTime(2024, 2, 29),
      );
    },
  );
  for (final brightness in Brightness.values) {
    testWidgets(
      'recent trend selects real duration at 320dp large text: $brightness',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: applicationTheme(brightness),
            builder: (c, child) => MediaQuery(
              data: MediaQuery.of(c)
                  .copyWith(textScaler: const TextScaler.linear(1.5)),
              child: child!,
            ),
            home: Scaffold(
              body: ListView(
                children: [
                  RecentReadingTrend(
                    today: DateTime(2026, 1, 2),
                    stats: const {'2025-12-31': 600, '2026-01-02': 20},
                  ),
                ],
              ),
            ),
          ),
        );
        expect(find.text('2026-01-02 · 20 秒'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('recent-day-2025-12-31')));
        await tester.pump();
        expect(find.text('2025-12-31 · 10 分钟'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('recent-day-2025-12-30')));
        await tester.pump();
        expect(find.text('2025-12-30 · 无阅读记录'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: RecentReadingTrend(
                today: DateTime(2026, 1, 2),
                stats: const {},
              ),
            ),
          ),
        );
        expect(find.text('2026-01-02 · 无阅读记录'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  final output = Platform.environment['SHUYE_CAPTURE_DIR'];
  testWidgets('capture recent reading trend', (tester) async {
    await loadShuyeSerif(tester);
    tester.view.physicalSize = const Size(390, 340);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final end = DateTime(2026, 10, 5);
    final dates = recentReadingDays({}, end);
    final demo = [180, 1200, 0, 900, 2400, 600, 1500];
    for (final brightness in Brightness.values) {
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: applicationTheme(brightness),
            home: Scaffold(
              body: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  RecentReadingTrend(
                    today: end,
                    stats: {
                      for (var i = 0; i < dates.length; i++)
                        dayKey(dates[i].$1): demo[i],
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(output!).create(recursive: true);
        await File('$output/recent-reading-${brightness.name}.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
  }, skip: output == null);
}
