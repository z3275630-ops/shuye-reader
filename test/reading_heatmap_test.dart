import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shuye_reader/appearance.dart';
import 'package:shuye_reader/reading_heatmap.dart';

void main() {
  final now = DateTime(2024, 3, 3);
  final stats = {
    '2023-12-31': 9999,
    '2024-02-27': 59,
    '2024-02-28': 300,
    '2024-02-29': 900,
    '2024-03-01': 1800,
    '2024-03-03': 7200,
    '2024-03-04': 9999, // Future input must not color or inflate results.
  };
  test('heatmap aligns Monday weeks, preserves leap day and excludes future or outside data', () {
    final data = ReadingHeatmapData.forSpan(HeatmapSpan.year, now, stats);
    expect(data.gridStart, DateTime(2024, 1, 1));
    expect(data.columns, 53);
    expect(data.dateAt(8, 3), DateTime(2024, 2, 29));
    expect(data.summary, (total: 10259, active: 5, longest: 4));
    expect(data.seconds(DateTime(2024, 3, 4)), 0);
    expect(data.seconds(DateTime(2023, 12, 31)), 0);
    expect(data.elapsedDays.length, 63);
    final sunday = ReadingHeatmapData.forSpan(
      HeatmapSpan.year,
      DateTime(2023, 12, 31),
      {},
    );
    expect(sunday.gridStart, DateTime(2022, 12, 26));
    expect(sunday.dateAt(0, 6), DateTime(2023, 1, 1));
    expect(sunday.contains(sunday.dateAt(0, 0)), isFalse);
    final rolling = ReadingHeatmapData.forSpan(
      HeatmapSpan.halfYear,
      now,
      stats,
    );
    expect(rolling.elapsedDays.length, 182);
    expect(rolling.gridStart.weekday, DateTime.monday);
  });
  test('seven fixed intensity levels retain seconds and are comparable across years', () {
    expect(
      [
        0,
        1,
        299,
        300,
        899,
        900,
        1799,
        1800,
        3599,
        3600,
        7199,
        7200,
      ].map(readingHeatLevel),
      [0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6],
    );
    expect(readingDuration(59), '59 秒');
    expect(readingDuration(3600), '1 小时');
    expect(readingDuration(3660), '1 小时 1 分钟');
    expect(readingDuration(0), '未阅读');
  });
  testWidgets(
    'day selection, historical years, future disabling and accessible labels use real data',
    (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: applicationTheme(Brightness.light),
            home: Scaffold(
              body: ListView(
                children: [ReadingHeatmap(stats: stats, now: now)],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final label in heatmapWeekdays) {
          expect(find.text(label), findsOneWidget);
        }
        expect(find.text('2 小时'), findsOneWidget);
        final paint = find.descendant(
          of: find.byKey(const ValueKey('reading-heatmap-chart')),
          matching: find.byType(CustomPaint),
        );
        final painter =
            tester.widget<CustomPaint>(paint).painter! as ReadingHeatmapPainter;
        final c =
            (DateTime.utc(2024, 2, 29)
                .difference(
                  DateTime.utc(
                    painter.data.gridStart.year,
                    painter.data.gridStart.month,
                    painter.data.gridStart.day,
                  ),
                )
                .inDays ~/
            7);
        final point = tester.getTopLeft(paint) + painter.cell(c, 3).center;
        await tester.tapAt(point);
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
        final semanticCells = painter.semanticsBuilder(
          Size(painter.pitch * painter.data.columns, 200),
        );
        expect(
          semanticCells.any((s) => s.properties.label == '2024-02-29 周四，15 分钟'),
          isTrue,
        );
        expect(
          semanticCells.any(
            (s) => s.properties.label!.startsWith('2024-03-04'),
          ),
          isFalse,
        );
        await tester.tap(find.text('全年'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<IconButton>(
                find.byWidgetPredicate(
                  (w) => w is IconButton && w.tooltip == '下一年',
                ),
              )
              .onPressed,
          isNull,
        );
        await tester.tap(find.byTooltip('上一年'));
        await tester.pumpAndSettle();
        expect(find.text('2023 年'), findsOneWidget);
        expect(
          tester
              .widget<IconButton>(
                find.byWidgetPredicate(
                  (w) => w is IconButton && w.tooltip == '下一年',
                ),
              )
              .onPressed,
          isNotNull,
        );
        await tester.tap(find.byTooltip('颜色说明'));
        await tester.pumpAndSettle();
        for (final label in heatmapLevels) {
          expect(find.text(label), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );
  testWidgets(
    'heatmap stays readable on a small dark screen with larger text and no records',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: applicationTheme(Brightness.dark),
          builder: (c, child) => MediaQuery(
            data: MediaQuery.of(c)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: Scaffold(
            body: ListView(
              children: [ReadingHeatmap(stats: const {}, now: now)],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('开始阅读后，方格会逐渐亮起来。'), findsOneWidget);
      await tester.tap(find.text('全年'));
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(-200, 0),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('颜色说明'));
      await tester.tap(find.byTooltip('颜色说明'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  final output = Platform.environment['SHUYE_CAPTURE_DIR'];
  testWidgets('capture actual heatmap in light, dark, annual and empty states', (
    tester,
  ) async {
    final font = Platform.environment['SHUYE_PREVIEW_FONT']!;
    final bytes = (await tester.runAsync(() => File(font).readAsBytes()))!;
    await (FontLoader(
      'Roboto',
    )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    final iconBytes = (await tester.runAsync(
      () => File(Platform.environment['SHUYE_PREVIEW_ICONS']!).readAsBytes(),
    ))!;
    await (FontLoader(
      'MaterialIcons',
    )..addFont(Future.value(ByteData.sublistView(iconBytes)))).load();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // Synthetic values belong only to this test. The app never seeds statistics.
    final demo = <String, int>{};
    for (var i = 0; i < 200; i++) {
      final d = DateTime(2026, 10, 5 - i);
      if (i % 5 != 0) {
        demo['${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}'] =
            [120, 600, 1200, 2400, 4800, 8100][i % 6];
      }
    }
    Future<void> render(
      String name,
      Brightness brightness,
      Map<String, int> data, {
      bool year = false,
    }) async {
      final key = GlobalKey();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: applicationTheme(brightness),
            home: Scaffold(
              appBar: AppBar(title: const Text('阅读统计')),
              body: ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  ReadingHeatmap(stats: data, now: DateTime(2026, 10, 5)),
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: Text('界面预览 · 演示数据', textAlign: TextAlign.center),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (year) {
        await tester.tap(find.text('全年'));
        await tester.pumpAndSettle();
      }
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(output!).create(recursive: true);
        await File('$output/$name.png').writeAsBytes(png!.buffer.asUint8List());
        image.dispose();
      });
      expect(tester.takeException(), isNull);
    }

    await render('heatmap-light', Brightness.light, demo);
    await render('heatmap-dark', Brightness.dark, demo);
    await render('heatmap-year', Brightness.light, demo, year: true);
    await render('heatmap-empty', Brightness.light, {});
  }, skip: output == null);
}
