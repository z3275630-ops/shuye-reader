import 'preview_fonts.dart';
import 'reader_test_support.dart';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shuye_reader/appearance.dart';
import 'package:shuye_reader/models.dart';
import 'package:shuye_reader/page_turn.dart';
import 'package:shuye_reader/reader.dart';
import 'package:shuye_reader/reader_gestures.dart';
import 'package:shuye_reader/reader_viewport.dart';
import 'package:shuye_reader/repository.dart';
import 'package:shuye_reader/services.dart';

void main() {
  testWidgets(
    'chrome and transient system insets preserve page geometry; genuine resize relayouts',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final viewport = GlobalKey();
      var hidden = false;
      var size = const Size(390, 844);
      var padding = const EdgeInsets.only(top: 30, bottom: 24);
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Align(
                alignment: Alignment.topLeft,
                child: SizedBox.fromSize(
                  size: size,
                  child: MediaQuery(
                    data: MediaQueryData(size: size, viewPadding: padding),
                    child: ReaderViewport(
                      immersive: hidden,
                      topControls: const SizedBox(height: 80),
                      bottomControls: const SizedBox(height: 64),
                      child: SizedBox.expand(key: viewport),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
      final before = tester.getRect(find.byKey(viewport));
      update(() => hidden = true);
      await tester.pump();
      expect(tester.getRect(find.byKey(viewport)), before);
      update(() {
        size = const Size(390, 870);
        padding = EdgeInsets.zero;
      });
      await tester.pump();
      expect(tester.getRect(find.byKey(viewport)), before);
      update(() => size = const Size(390, 700));
      await tester.pump();
      expect(
        tester.getRect(find.byKey(viewport)).height,
        lessThan(before.height),
      );
    },
  );

  for (final dir in [1, -1]) {
    testWidgets(
      'slide follows drag, commits only after settling, direction $dir',
      (tester) async {
        final key = GlobalKey<PageTurnSurfaceState>();
        var committed = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: SizedBox(
                width: 300,
                height: 400,
                child: PageTurnSurface(
                  key: key,
                  color: Colors.white,
                  adjacent: (_) => const ColoredBox(color: Colors.blue),
                  child: const ColoredBox(color: Colors.red),
                ),
              ),
            ),
          ),
        );
        final surface = key.currentState!;
        expect(surface.beginDrag(), isTrue);
        surface.updateDrag(-90.0 * dir);
        await tester.pump();
        expect(surface.displacement, -90.0 * dir);
        expect(surface.snapshot, isNull);
        final done = surface.endDrag(0, (d) => committed = d);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(committed, 0);
        await tester.pumpAndSettle();
        await done;
        expect(committed, dir);
        expect(surface.busy, isFalse);
      },
    );
  }

  testWidgets(
    'prepared page text is laid out before drag and not repainted each frame',
    (tester) async {
      final key = GlobalKey<PageTurnSurfaceState>();
      final current = _WorkCounts(), next = _WorkCounts();
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 300,
            height: 400,
            child: PageTurnSurface(
              key: key,
              color: Colors.white,
              next: _CountWork(
                counts: next,
                child: const SelectableText('Prepared next page'),
              ),
              child: _CountWork(
                counts: current,
                child: const SelectableText('Current page'),
              ),
            ),
          ),
        ),
      );
      expect(next.layouts, greaterThan(0));
      expect(next.paints, 0);
      final surface = key.currentState!;
      surface.beginDrag();
      surface.updateDrag(-30);
      await tester.pump();
      final layouts = [current.layouts, next.layouts];
      final paints = [current.paints, next.paints];
      expect(next.paints, greaterThan(0));
      for (var i = 0; i < 10; i++) {
        surface.updateDrag(-10);
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect([current.layouts, next.layouts], layouts);
      expect([current.paints, next.paints], paints);
      final done = surface.endDrag(-1000, (_) {});
      await tester.pump();
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect([current.layouts, next.layouts], layouts);
        expect([current.paints, next.paints], paints);
      }
      await tester.pumpAndSettle();
      await done;
    },
  );

  testWidgets(
    'release velocity stays continuous and a new drag can interrupt settling',
    (tester) async {
      final key = GlobalKey<PageTurnSurfaceState>();
      final commits = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 300,
            height: 400,
            child: PageTurnSurface(
              key: key,
              color: Colors.white,
              next: const ColoredBox(color: Colors.blue),
              child: const ColoredBox(color: Colors.white),
            ),
          ),
        ),
      );
      final surface = key.currentState!;
      surface.beginDrag();
      surface.updateDrag(-80);
      final oldTurn = surface.endDrag(-1000, commits.add);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      expect(surface.displacement + 80, closeTo(-1, .1));
      await tester.pump(const Duration(milliseconds: 40));
      final offset = surface.displacement;
      expect(surface.beginDrag(), isTrue);
      expect(surface.displacement, offset);
      await tester.pump(const Duration(milliseconds: 40));
      expect(surface.displacement, offset);
      expect(commits, isEmpty);
      surface.updateDrag(15);
      expect(surface.displacement, offset + 15);
      final returning = surface.endDrag(1000, commits.add);
      await tester.pumpAndSettle();
      await Future.wait([oldTurn, returning]);
      expect(commits, isEmpty);
      expect(surface.busy, isFalse);
    },
  );

  testWidgets(
    'short drag and cancelled animation preserve progress; queue settles in order',
    (tester) async {
      final key = GlobalKey<PageTurnSurfaceState>();
      final commits = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 300,
            height: 400,
            child: PageTurnSurface(
              key: key,
              color: Colors.white,
              adjacent: (_) => const ColoredBox(color: Colors.blue),
              child: const ColoredBox(color: Colors.red),
            ),
          ),
        ),
      );
      final surface = key.currentState!;
      surface.beginDrag();
      surface.updateDrag(-20);
      final cancel = surface.endDrag(0, commits.add);
      await tester.pumpAndSettle();
      await cancel;
      expect(commits, isEmpty);
      final first = surface.turn(() => commits.add(1), 'slide');
      final second = surface.turn(() => commits.add(2), 'slide', direction: -1);
      await tester.pumpAndSettle();
      await Future.wait([first, second]);
      expect(commits, [1, 2]);
      final interrupted = surface.turn(() => commits.add(3), 'slide');
      await tester.pump(const Duration(milliseconds: 80));
      surface.cancel();
      await tester.pumpAndSettle();
      await interrupted;
      expect(commits, [1, 2]);
    },
  );

  testWidgets(
    'release direction and remaining distance control the slide settle',
    (tester) async {
      final key = GlobalKey<PageTurnSurfaceState>();
      final commits = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 300,
              height: 400,
              child: PageTurnSurface(
                key: key,
                color: Colors.white,
                adjacent: (_) => const ColoredBox(color: Colors.blue),
                child: const ColoredBox(color: Colors.red),
              ),
            ),
          ),
        ),
      );
      final surface = key.currentState!;
      surface.beginDrag();
      surface.updateDrag(-180);
      final reverse = surface.endDrag(1000, commits.add);
      await tester.pumpAndSettle();
      await reverse;
      expect(commits, isEmpty);
      expect(surface.displacement, 0);
      surface.beginDrag();
      surface.updateDrag(-25);
      final flick = surface.endDrag(-1000, commits.add);
      final flickDuration = surface.controller.duration!;
      await tester.pumpAndSettle();
      await flick;
      expect(commits, [1]);
      surface.beginDrag();
      surface.updateDrag(-270);
      final nearEnd = surface.endDrag(-1000, commits.add);
      expect(surface.controller.duration!, lessThan(flickDuration));
      expect(commits, [1]);
      await tester.pumpAndSettle();
      await nearEnd;
      expect(commits, [1, 1]);
    },
  );

  test('pagination identity ignores paper and tool preferences but tracks typography', () {
    final s = ReaderSettings();
    final key = readerLayoutSettingsKey(s);
    s.theme = 'night';
    s.extra['reader.animation'] = 'none';
    s.extra['reader.brightness'] = .3;
    expect(readerLayoutSettingsKey(s), key);
    s.fontSize += 1;
    expect(readerLayoutSettingsKey(s), isNot(key));
    s.fontSize -= 1;
    s.extra['reader.bionic'] = true;
    expect(readerLayoutSettingsKey(s), isNot(key));
    final bionicKey = readerLayoutSettingsKey(s);
    s.extra['reader.highlights'] = 'quiet';
    expect(readerLayoutSettingsKey(s), isNot(bionicKey));
  });

  testWidgets('book boundaries stay still and emit no invented preview', (
    tester,
  ) async {
    final key = GlobalKey<PageTurnSurfaceState>();
    var boundary = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: PageTurnSurface(
          key: key,
          color: Colors.white,
          adjacent: (_) => null,
          child: const SizedBox.expand(),
        ),
      ),
    );
    key.currentState!.beginDrag();
    key.currentState!.updateDrag(120);
    expect(key.currentState!.displacement, 0);
    await key.currentState!.endDrag(800, (_) => boundary++);
    expect(boundary, 1);
    expect(key.currentState!.busy, isFalse);
  });

  sqfliteFfiInit();
  for (final spread in [false, true]) {
    testWidgets(
      'reader keeps text and page identity across chrome, drag cancellation and chapter turns: spread $spread',
      (tester) async {
        tester.view.physicalSize = Size(spread ? 900 : 390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          DeviceReader.channel,
          (_) async => null,
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            DeviceReader.channel,
            null,
          ),
        );
        final repo = (await tester.runAsync(
          () => ReaderRepository.open(
            path: inMemoryDatabasePath,
            factory: databaseFactoryFfi,
          ),
        ))!;
        final book = Book(
          id: 'viewport',
          title: 'Viewport',
          chapters: const [
            Chapter('One', 'First chapter.'),
            Chapter('Two', 'Second chapter.'),
          ],
        );
        await tester.runAsync(() => repo.addBook(book));
        final settings = ReaderSettings(
          extra: {'reader.doublePage': spread, 'reader.reminderMinutes': 0},
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: applicationTheme(Brightness.light),
            home: ReaderScreen(
              book: book,
              repository: repo,
              settings: settings,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(AppBar), findsNothing);
        expect(find.byType(ReaderFooter), findsNothing);
        await tester.tapAt(tester.getCenter(find.byType(ReaderTapSurface)));
        await tester.pump();
        expect(find.byType(AppBar), findsOneWidget);
        await tester.pumpAndSettle();
        expect(find.byType(AppBar), findsOneWidget);
        final current = find.byType(SelectableText).first;
        final rect = tester.getRect(current);
        expect(
          rect.top,
          greaterThanOrEqualTo(tester.getBottomRight(find.byType(AppBar)).dy),
        );
        expect(
          rect.bottom,
          lessThanOrEqualTo(tester.getTopLeft(find.byType(ReaderFooter)).dy),
        );
        final key = tester.widget<SelectableText>(current).key;
        final offset = book.offset;
        final tap = find.byType(ReaderTapSurface);
        await tester.tapAt(tester.getCenter(tap));
        await tester.pumpAndSettle();
        expect(find.byType(AppBar), findsNothing);
        expect(tester.getRect(current), rect);
        expect(tester.widget<SelectableText>(current).key, key);
        expect(book.offset, offset);
        final turn = tester.state<PageTurnSurfaceState>(
          find.byType(PageTurnSurface),
        );
        final touch = await tester.startGesture(tester.getCenter(tap));
        await touch.moveBy(const Offset(-90, 0));
        await tester.pump();
        expect(turn.displacement, closeTo(-90, .01));
        expect(book.chapter, 0);
        await touch.cancel();
        await tester.pumpAndSettle();
        expect(turn.busy, isFalse);
        expect(book.offset, offset);
        turn.beginDrag();
        turn.updateDrag(-20);
        final cancel = turn.endDrag(
          0,
          (_) => fail('short drag must not commit'),
        );
        await tester.pumpAndSettle();
        await cancel;
        expect(book.chapter, 0);
        await tester.tapAt(tester.getCenter(tap));
        await tester.pumpAndSettle();
        await revealReaderControls(tester);
        await tester.tap(find.byTooltip('阅读设置'));
        await tester.pumpAndSettle();
        final dock = find.byKey(const ValueKey('reader-settings-dock'));
        expect(
          tester
              .getBottomRight(find.byKey(const ValueKey('reader-visible-page')))
              .dy,
          lessThanOrEqualTo(tester.getTopLeft(dock).dy),
        );
        expect(tester.getRect(current), rect);
        expect(tester.widget<SelectableText>(current).key, key);
        await tester.ensureVisible(find.widgetWithText(ChoiceChip, '夜读'));
        await tester.tap(find.widgetWithText(ChoiceChip, '夜读'));
        await tester.pumpAndSettle();
        expect(
          readerColors(settings)[0],
          applicationTheme(Brightness.dark).colorScheme.surface,
        );
        expect(tester.getRect(current), rect);
        expect(tester.widget<SelectableText>(current).key, key);
        expect(book.offset, offset);
        expect(
          find.byKey(const ValueKey('reader-settings-preview')),
          findsNothing,
        );
        await tester.tap(find.text('开始阅读'));
        await tester.pumpAndSettle();
        expect(tester.getRect(current), rect);
        expect(tester.widget<SelectableText>(current).key, key);
        expect(book.offset, offset);
        await revealReaderControls(tester);
        await tester.tap(find.byTooltip('下一页'));
        await tester.pump(const Duration(milliseconds: 80));
        expect(book.chapter, 0);
        await tester.pumpAndSettle();
        expect(book.chapter, 1);
        expect(
          tester.widget<SelectableText>(current).textSpan!.toPlainText(),
          'Second chapter.',
        );
        await tester.tap(find.byTooltip('上一页'));
        await tester.pumpAndSettle();
        expect(book.chapter, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await repo.close();
        });
      },
    );
  }

  testWidgets(
    'Chinese slide preview and committed page have identical glyph positions',
    (tester) async {
      await loadShuyeSerif(tester);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        DeviceReader.channel,
        (_) async => null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          DeviceReader.channel,
          null,
        ),
      );
      final repo = (await tester.runAsync(
        () => ReaderRepository.open(
          path: inMemoryDatabasePath,
          factory: databaseFactoryFfi,
        ),
      ))!;
      final book = Book(
        id: 'glyphs',
        title: '字体交接',
        chapters: [
          const Chapter('第一章', '起点。'),
          Chapter(
            '第二章',
            List.filled(
              20,
              '小镇的午后像一页留白的纸。她说：“慢慢来。”\nA quiet page, 2026 年的一点时间。\n',
            ).join(),
          ),
        ],
      );
      await tester.runAsync(() => repo.addBook(book));
      await tester.pumpWidget(
        MaterialApp(
          theme: applicationTheme(Brightness.light),
          home: ReaderScreen(
            book: book,
            repository: repo,
            settings: ReaderSettings(extra: {'reader.reminderMinutes': 0}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final surface = tester.state<PageTurnSurfaceState>(
        find.byType(PageTurnSurface),
      );
      surface.beginDrag();
      surface.updateDrag(-140);
      await tester.pump();
      final header = tester.getRect(find.text('第一章'));
      final nextHeader = tester.getRect(find.text('第二章'));
      expect(header.left, closeTo(28 - 140, .01));
      expect(nextHeader.left, closeTo(28 - 140 + 390, .01));
      expect(
        tester.getRect(find.text('1 / 2 章')).right,
        closeTo(390 - 28 - 140, .01),
      );
      expect(
        tester.getRect(find.text('2 / 2 章')).right,
        closeTo(390 - 28 - 140 + 390, .01),
      );
      final footers = find.byWidgetPredicate(
        (w) => w is Text && (w.data?.contains(' 页 · ') ?? false),
      );
      expect(footers, findsNWidgets(2));
      expect(tester.getCenter(footers.first).dx, closeTo(195 - 140, .01));
      expect(tester.getCenter(footers.last).dx, closeTo(195 - 140 + 390, .01));
      final outgoingRect = tester.getRect(find.byType(SelectableText).first);
      final incomingRect = tester.getRect(find.byType(SelectableText).last);
      expect(incomingRect.left - outgoingRect.right, closeTo(56, .01));
      surface.updateDrag(
        -tester.getSize(find.byType(PageTurnSurface)).width + 140,
      );
      await tester.pump();
      final RenderEditable incoming = tester
          .state<EditableTextState>(find.byType(EditableText).last)
          .renderEditable;
      final text = incoming.text!.toPlainText();
      final boxes = incoming.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: text.length),
      );
      final height = incoming.size.height;
      final rect = tester.getRect(find.byType(SelectableText).last);
      final previewFooter = tester.widget<Text>(footers.last).data;
      surface.cancel();
      await tester.pumpAndSettle();
      await tester.fling(
        find.byType(ReaderTapSurface),
        const Offset(-240, 0),
        1000,
      );
      await tester.pumpAndSettle();
      expect(book.chapter, 1);
      final committed = tester
          .state<EditableTextState>(find.byType(EditableText).first)
          .renderEditable;
      expect(committed.text!.toPlainText(), text);
      expect(committed.size.height, height);
      expect(
        committed.getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: text.length),
        ),
        boxes,
      );
      expect(tester.getRect(find.byType(SelectableText).first), rect);
      expect(tester.widget<Text>(footers).data, previewFooter);
      expect(previewFooter, endsWith('${(book.progress * 100).round()}%'));
      expect(
        committed.size.height,
        lessThanOrEqualTo(tester.getSize(find.byType(PageTurnSurface)).height),
      );
      final firstPageKey = tester
          .widget<SelectableText>(find.byType(SelectableText).first)
          .key;
      await tester.fling(
        find.byType(ReaderTapSurface),
        const Offset(-240, 0),
        1000,
      );
      await tester.pumpAndSettle();
      final saved = tester.widget<SelectableText>(
        find.byType(SelectableText).first,
      );
      expect(saved.key, isNot(firstPageKey));
      final savedOffset = book.offset;
      final savedRect = tester.getRect(find.byType(SelectableText).first);
      await revealReaderControls(tester);
      await tester.pumpAndSettle();
      await revealReaderControls(tester);
      await tester.tap(find.byTooltip('阅读设置'));
      await tester.pumpAndSettle();
      expect(
        tester
            .getBottomRight(find.byKey(const ValueKey('reader-visible-page')))
            .dy,
        lessThanOrEqualTo(
          tester
              .getTopLeft(find.byKey(const ValueKey('reader-settings-dock')))
              .dy,
        ),
      );
      await tester.tap(find.text('开始阅读'));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(SelectableText).first), savedRect);
      final restored = tester.widget<SelectableText>(
        find.byType(SelectableText).first,
      );
      expect(restored.key, saved.key);
      expect(restored.textSpan!.toPlainText(), saved.textSpan!.toPlainText());
      expect(book.offset, savedOffset);
      final paragraph = tester.getRect(find.byType(SelectableText).first);
      await tester.longPressAt(paragraph.topLeft + const Offset(16, 16));
      await tester.pumpAndSettle();
      final selection = tester
          .state<EditableTextState>(find.byType(EditableText).first)
          .renderEditable
          .selection;
      expect(selection, isNotNull);
      expect(selection!.isCollapsed, isFalse);
      expect(
        tester
            .widget<ReaderTapSurface>(find.byType(ReaderTapSurface))
            .canTurn(),
        isFalse,
      );
      expect(book.offset, savedOffset);
      // Clear the selection before exercising the enlarged settings dock.
      tester
          .state<EditableTextState>(find.byType(EditableText).first)
          .hideToolbar();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      tester.platformDispatcher.textScaleFactorTestValue = 2.25;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      await revealReaderControls(tester);
      await tester.tap(find.byTooltip('阅读设置'));
      await tester.pumpAndSettle();
      expect(
        tester
            .getBottomRight(find.byKey(const ValueKey('reader-visible-page')))
            .dy,
        lessThanOrEqualTo(
          tester
              .getTopLeft(find.byKey(const ValueKey('reader-settings-dock')))
              .dy,
        ),
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('reader-settings-dock')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await repo.close();
      });
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}

class _WorkCounts {
  int layouts = 0, paints = 0;
}

class _CountWork extends SingleChildRenderObjectWidget {
  final _WorkCounts counts;
  const _CountWork({required this.counts, required super.child});
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _CountRenderWork(counts);
}

class _CountRenderWork extends RenderProxyBox {
  final _WorkCounts counts;
  _CountRenderWork(this.counts);
  @override
  void performLayout() {
    counts.layouts++;
    super.performLayout();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    counts.paints++;
    super.paint(context, offset);
  }
}
