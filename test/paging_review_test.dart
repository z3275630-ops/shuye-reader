import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shuye_reader/reader.dart';
import 'package:shuye_reader/models.dart';
import 'package:shuye_reader/repository.dart';
import 'package:shuye_reader/services.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'reader_test_support.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:shuye_reader/page_turn.dart';
import 'package:shuye_reader/reader_gestures.dart';

void main() {
  for (final edge in [-1, 1]) {
    testWidgets(
      'book edge reverses immediately without invisible travel $edge',
      (tester) async {
        final key = GlobalKey<PageTurnSurfaceState>();
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: SizedBox(
                width: 300,
                height: 400,
                child: PageTurnSurface(
                  key: key,
                  color: Colors.white,
                  previous: edge == 1 ? const Text('prepared-neighbor') : null,
                  next: edge == -1 ? const Text('prepared-neighbor') : null,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        );
        expect(tester.getSize(find.byType(PageTurnSurface)).width, 300);
        final surface = key.currentState!;
        surface.beginDrag();
        surface.updateDrag(-edge * 120.0);
        await tester.pump();
        expect(surface.displacement, 0);
        expect(find.text('prepared-neighbor'), findsOneWidget);
        surface.updateDrag(edge * 25.0);
        await tester.pump();
        expect(surface.displacement, edge * 25.0);
        final commits = <int>[];
        surface.updateDrag(edge * 90.0);
        final done = surface.endDrag(edge * 1000.0, commits.add);
        await tester.pumpAndSettle();
        await done;
        expect(commits, [-edge]);
      },
    );
  }
  testWidgets(
    'moving prepared sheets retain their widget tree during drag and settling',
    (tester) async {
      final key = GlobalKey<PageTurnSurfaceState>();
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 300,
            height: 400,
            child: PageTurnSurface(
              key: key,
              color: Colors.white,
              pageIdentity: 'p0',
              nextIdentity: 'p1',
              next: const SelectableText('Next page'),
              child: const SelectableText('Current page'),
            ),
          ),
        ),
      );
      final surface = key.currentState!;
      surface.beginDrag();
      surface.updateDrag(-30);
      await tester.pump();
      final finder = find.byKey(
        const ValueKey<(String, Object)>(('reader-sheet', 'p0')),
      );
      final prepared = tester.widget(finder);
      for (var i = 0; i < 8; i++) {
        surface.updateDrag(-10);
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.widget(finder), same(prepared));
      }
      final done = surface.endDrag(-1000, (_) {});
      await tester.pump();
      final settling = tester.widget(finder);
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.widget(finder), same(settling));
      }
      await tester.pumpAndSettle();
      await done;
    },
  );
  testWidgets(
    'crossing the resting origin releases toward the newly visible page',
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
                previous: const Text('Previous'),
                next: const Text('Next'),
                child: const Text('Current'),
              ),
            ),
          ),
        ),
      );
      final surface = key.currentState!;
      surface.beginDrag();
      surface.updateDrag(-100);
      surface.updateDrag(200);
      await tester.pump();
      expect(surface.displacement, 100);
      final done = surface.endDrag(1000, commits.add);
      await tester.pumpAndSettle();
      await done;
      expect(commits, [-1]);
    },
  );
  testWidgets('slow reverse release restores instead of committing', (
    tester,
  ) async {
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
    surface.updateDrag(-120);
    surface.updateDrag(20);
    final done = surface.endDrag(300, commits.add);
    await tester.pumpAndSettle();
    await done;
    expect(commits, isEmpty);
  });
  for (final slow in [false, true]) {
    testWidgets(
      'selectable paragraph preserves incremental horizontal swipe slow=$slow',
      (tester) async {
        int starts = 0, updates = 0, ends = 0, cancels = 0;
        const paragraphKey = ValueKey('audit-text');
        await tester.pumpWidget(
          MaterialApp(
            home: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 300,
                height: 400,
                child: ReaderTapSurface(
                  canTurn: () => true,
                  onTap: (_) {},
                  onHorizontalDragStart: (_) => starts++,
                  onHorizontalDragUpdate: (_) => updates++,
                  onHorizontalDragEnd: (_) => ends++,
                  onHorizontalDragCancel: () => cancels++,
                  child: const SelectableText(
                    'This is a selectable paragraph to audit slow horizontal motion. '
                    'The text selection gesture competes with the page swipe gesture.',
                    key: paragraphKey,
                    style: TextStyle(fontSize: 18),
                  ),
                ),
              ),
            ),
          ),
        );
        final origin =
            tester.getTopLeft(find.byKey(paragraphKey)) + const Offset(80, 12);
        final touch = await tester.startGesture(origin);
        if (slow) {
          await tester.pump(const Duration(milliseconds: 100));
          await touch.moveTo(origin + const Offset(-9, 0));
          await tester.pump(const Duration(milliseconds: 120));
          await touch.moveTo(origin + const Offset(-15, 0));
          await tester.pump(const Duration(milliseconds: 80));
        } else {
          await tester.pump(const Duration(milliseconds: 50));
        }
        await touch.moveTo(origin + const Offset(-35, 0));
        await tester.pump(const Duration(milliseconds: 50));
        await touch.moveTo(origin + const Offset(-90, 0));
        await touch.up();
        await tester.pumpAndSettle();
        expect(updates, greaterThan(0));
        expect(ends, 1);
      },
    );
  }
  for (final dir in [-1, 1]) {
    for (final cancel in [false, true]) {
      testWidgets(
        'cold neighbor waits for paint before commit dir=$dir cancel=$cancel',
        (tester) async {
          final key = GlobalKey<PageTurnSurfaceState>();
          final ready = Completer<void>();
          final commits = <int>[];
          var loaded = false;
          late StateSetter update;
          await tester.pumpWidget(
            MaterialApp(
              home: Center(
                child: SizedBox(
                  width: 300,
                  height: 400,
                  child: StatefulBuilder(
                    builder: (context, setState) {
                      update = setState;
                      return PageTurnSurface(
                        key: key,
                        color: Colors.white,
                        previous: dir < 0 && loaded
                            ? const ColoredBox(color: Colors.blue)
                            : null,
                        next: dir > 0 && loaded
                            ? const ColoredBox(color: Colors.blue)
                            : null,
                        previousState: dir < 0 && !loaded
                            ? ReaderNeighborState.loading
                            : ReaderNeighborState.boundary,
                        nextState: dir > 0 && !loaded
                            ? ReaderNeighborState.loading
                            : ReaderNeighborState.boundary,
                        prepareAdjacent: (_) => ready.future,
                        child: const ColoredBox(color: Colors.red),
                      );
                    },
                  ),
                ),
              ),
            ),
          );
          final surface = key.currentState!;
          surface.beginDrag();
          surface.updateDrag(-100.0 * dir);
          final release = surface.endDrag(-800.0 * dir, commits.add);
          await tester.pump(const Duration(milliseconds: 400));
          expect(commits, isEmpty);
          expect(surface.displacement, 0);
          if (cancel) surface.cancel();
          update(() => loaded = true);
          ready.complete();
          await tester.pump();
          await tester.pump();
          if (!cancel) {
            expect(
              commits,
              isEmpty,
              reason: 'painting a loaded neighbor must not hard jump',
            );
            expect(surface.displacement, -100.0 * dir);
          }
          await tester.pumpAndSettle();
          await release;
          expect(commits, cancel ? isEmpty : [dir]);
          expect(surface.busy, isFalse);
        },
      );
    }
  }
  testWidgets(
    'incremental pagination matches synchronous offsets and cancels stale work',
    (tester) async {
      final text = List.filled(12, '山间来信，Hello 世界。😀\n').join();
      const style = TextStyle(fontSize: 20, height: 1.8);
      var complete = false;
      final result =
          paginateInFrames(
            text,
            style,
            280,
            150,
            TextScaler.noScaling,
            isCurrent: () => true,
            shouldPause: () => false,
          ).then((pages) {
            complete = true;
            return pages;
          });
      await tester.pump();
      expect(complete, isFalse);
      for (var i = 0; i < 200 && !complete; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final actual = (await result)!;
      final expected = paginate(text, style, 280, 150, TextScaler.noScaling);
      expect(
        actual.map((p) => (p.start, p.end)),
        expected.map((p) => (p.start, p.end)),
      );
      var current = true;
      final cancelled = paginateInFrames(
        text,
        style,
        280,
        150,
        TextScaler.noScaling,
        isCurrent: () => current,
        shouldPause: () => true,
      );
      await tester.pump();
      current = false;
      await tester.pumpAndSettle();
      expect(await cancelled, isNull);
    },
  );
  testWidgets(
    'reader cold cross-chapter drag waits then promotes the prepared paragraph',
    (tester) async {
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
        id: 'review-cold',
        title: 'Cold chapter',
        chapters: [
          const Chapter('One', 'First chapter.'),
          Chapter(
            'Two',
            List.filled(
              70,
              'A prepared second chapter has several pages.\n',
            ).join(),
          ),
        ],
      );
      await tester.runAsync(() => repo.addBook(book));
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            book: book,
            repository: repo,
            settings: ReaderSettings(extra: {'reader.reminderMinutes': 0}),
          ),
        ),
      );
      final surface = tester.state<PageTurnSurfaceState>(
        find.byType(PageTurnSurface),
      );
      expect(
        tester.widget<PageTurnSurface>(find.byType(PageTurnSurface)).nextState,
        ReaderNeighborState.loading,
      );
      surface.beginDrag();
      surface.updateDrag(-140);
      tester
          .widget<ReaderTapSurface>(find.byType(ReaderTapSurface))
          .onHorizontalDragEnd(
            DragEndDetails(
              primaryVelocity: -1000,
              velocity: const Velocity(pixelsPerSecond: Offset(-1000, 0)),
            ),
          );
      await tester.pump();
      expect(book.chapter, 0);
      RenderObject? prepared;
      for (var i = 0; i < 300 && book.chapter == 0; i++) {
        final widget = tester.widget<PageTurnSurface>(
          find.byType(PageTurnSurface),
        );
        if (prepared == null && widget.nextIdentity != null) {
          prepared = tester.renderObject(
            find
                .descendant(
                  of: find.byKey(
                    ValueKey(('reader-sheet', widget.nextIdentity!)),
                  ),
                  matching: find.byType(EditableText),
                )
                .first,
          );
        }
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pumpAndSettle();
      expect(book.chapter, 1);
      expect(prepared, isNotNull);
      final currentEditable = find
          .descendant(
            of: currentReaderSheet(tester),
            matching: find.byType(EditableText),
          )
          .first;
      expect(tester.renderObject(currentEditable), same(prepared));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await repo.close();
      });
    },
  );
}
