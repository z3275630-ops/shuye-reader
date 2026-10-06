import 'package:flutter/material.dart';
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
        final current = find.byType(SelectableText).first;
        final rect = tester.getRect(current);
        final key = tester.widget<SelectableText>(current).key;
        final offset = book.offset;
        final tap = find.byType(ReaderTapSurface);
        tester.widget<ReaderTapSurface>(tap).onDoubleTap();
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
        tester.widget<ReaderTapSurface>(tap).onDoubleTap();
        await tester.pumpAndSettle();
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
}
