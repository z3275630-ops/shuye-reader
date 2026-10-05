import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shuye_reader/appearance.dart';
import 'package:shuye_reader/reading_heatmap.dart';

void main() {
  test(
    'calendar month preserves leap days, six-row months and year boundaries',
    () {
      final february = ReadingHeatmapData.forSpan(
        HeatmapSpan.month,
        DateTime(2024, 3, 3),
        {
          '2024-01-31': 9999,
          '2024-02-28': 300,
          '2024-02-29': 900,
          '2024-03-01': 9999,
        },
        year: 2024,
        month: 2,
      );
      expect(february.start, DateTime(2024, 2));
      expect(february.end, DateTime(2024, 3));
      expect(february.gridStart, DateTime(2024, 1, 29));
      expect(february.elapsedDays.length, 29);
      expect(february.dateAt(4, 3), DateTime(2024, 2, 29));
      expect(february.summary, (total: 1200, active: 2, longest: 2));
      final august = ReadingHeatmapData.forSpan(
        HeatmapSpan.month,
        DateTime(2026, 9),
        {},
        year: 2026,
        month: 8,
      );
      expect(august.columns, 6);
      expect(august.dateAt(5, 0), DateTime(2026, 8, 31));
      final december = ReadingHeatmapData.forSpan(
        HeatmapSpan.month,
        DateTime(2024),
        {},
        year: 2023,
        month: 12,
      );
      expect(december.end, DateTime(2024));
      expect(december.elapsedDays.length, 31);
      final current = ReadingHeatmapData.forSpan(
        HeatmapSpan.month,
        DateTime(2026, 10, 5),
        {'2026-10-06': 900},
      );
      expect(current.elapsedDays.length, 5);
      expect(current.seconds(DateTime(2026, 10, 6)), 0);
      expect(current.summary.total, 0);
    },
  );

  testWidgets(
    'month opens by default, selects real days and browses past months across years',
    (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: applicationTheme(Brightness.light),
          home: Scaffold(
            body: ListView(
              children: [
                ReadingHeatmap(
                  now: DateTime(2024, 3, 3),
                  stats: const {
                    '2024-02-29': 900,
                    '2024-03-01': 1800,
                    '2024-03-03': 7200,
                    '2024-03-04': 9999,
                  },
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('reading-heatmap-month')),
        findsOneWidget,
      );
      expect(find.text('2024 年 3 月'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == '下一月',
              ),
            )
            .onPressed,
        isNull,
      );
      expect(find.text('1'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('heatmap-day-2024-03-01')));
      await tester.pumpAndSettle();
      expect(find.text('2024.3.1 周五'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('heatmap-selected-duration')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('heatmap-selected-duration')),
            )
            .data,
        '30 分钟',
      );
      await tester.tap(find.byKey(const ValueKey('heatmap-day-2024-03-04')));
      await tester.pumpAndSettle();
      expect(find.text('2024.3.1 周五'), findsOneWidget);
      await tester.tap(find.byTooltip('上一月'));
      await tester.pumpAndSettle();
      expect(find.text('2024 年 2 月'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('heatmap-day-2024-02-29')));
      await tester.pumpAndSettle();
      expect(find.text('2024.2.29 周四'), findsOneWidget);
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('heatmap-selected-duration')),
            )
            .data,
        '15 分钟',
      );
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == '下一月',
              ),
            )
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byTooltip('上一月'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('上一月'));
      await tester.pumpAndSettle();
      expect(find.text('2023 年 12 月'), findsOneWidget);
      await tester.tap(
        find.ancestor(of: find.text('本月'), matching: find.byType(ChoiceChip)),
      );
      await tester.pumpAndSettle();
      expect(find.text('2024 年 3 月'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [const Size(320, 640), const Size(390, 844)]) {
    testWidgets(
      'weekly grid has full square edges on $size after positioning and dragging',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: applicationTheme(Brightness.dark),
            builder: (c, child) => MediaQuery(
              data: MediaQuery.of(c)
                  .copyWith(textScaler: const TextScaler.linear(1.5)),
              child: child!,
            ),
            home: Scaffold(
              body: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  ReadingHeatmap(now: DateTime(2026, 10, 5), stats: const {}),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('reading-heatmap-month')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('半年'));
        await tester.pumpAndSettle();
        final canvas = find.descendant(
          of: find.byKey(const ValueKey('reading-heatmap-chart')),
          matching: find.byType(CustomPaint),
        );
        var painter =
            tester.widget<CustomPaint>(canvas).painter!
                as ReadingHeatmapPainter;
        final controller = tester
            .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
            .controller!;
        void aligned() {
          painter =
              tester.widget<CustomPaint>(canvas).painter!
                  as ReadingHeatmapPainter;
          expect(painter.cell(0, 0).width, greaterThanOrEqualTo(20));
          expect(
            painter.cell(0, 0).height,
            closeTo(painter.cell(0, 0).width, .000001),
          );
          expect(
            controller.offset / painter.pitch,
            closeTo((controller.offset / painter.pitch).roundToDouble(), .001),
          );
          expect(
            painter.viewportWidth / painter.pitch,
            closeTo(
              (painter.viewportWidth / painter.pitch).roundToDouble(),
              .001,
            ),
          );
          final first = (controller.offset / painter.pitch).round();
          final visible = (painter.viewportWidth / painter.pitch).round();
          expect(
            painter.cell(first, 0).left,
            greaterThanOrEqualTo(controller.offset),
          );
          expect(
            painter.cell(first + visible - 1, 0).right,
            lessThanOrEqualTo(controller.offset + painter.viewportWidth + .01),
          );
        }

        aligned();
        await tester.ensureVisible(
          find.byKey(const ValueKey('reading-heatmap-chart')),
        );
        await tester.drag(
          find.byType(SingleChildScrollView),
          const Offset(57, 0),
        );
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 150));
        await tester.pumpAndSettle();
        aligned();
        await tester.ensureVisible(find.text('全年'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('全年'));
        await tester.pumpAndSettle();
        aligned();
        expect(painter.data.start, DateTime(2026));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
