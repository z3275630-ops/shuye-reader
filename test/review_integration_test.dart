import 'preview_fonts.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shuye_reader/appearance.dart';
import 'package:shuye_reader/library_collections.dart';
import 'package:shuye_reader/main.dart';
import 'package:shuye_reader/models.dart';
import 'package:shuye_reader/page_turn.dart';
import 'package:shuye_reader/reader.dart';
import 'package:shuye_reader/reader_controls.dart';
import 'package:shuye_reader/reading_time.dart';
import 'package:shuye_reader/repository.dart';
import 'package:shuye_reader/workbench.dart';

void main() {
  sqfliteFfiInit();
  Future<ReaderRepository> memory() => ReaderRepository.open(
    path: inMemoryDatabasePath,
    factory: databaseFactoryFfi,
  );

  test(
    'failed reading batches retry with original hour, including short visits',
    () async {
      final repo = await memory();
      addTearDown(repo.close);
      final id = (await repo.books()).first.id;
      await repo.db.execute(
        "CREATE TRIGGER reject_time BEFORE INSERT ON read_records BEGIN SELECT RAISE(ABORT, 'temporary'); END",
      );
      await expectLater(
        repo.record(id, 3, at: DateTime(2026, 10, 4, 23)),
        throwsA(anything),
      );
      await repo.db.execute('DROP TRIGGER reject_time');
      await repo.record(id, 8, at: DateTime(2026, 10, 5, 0));
      await repo.record(id, 0);
      expect(await repo.statistics(), {'2026-10-04': 3, '2026-10-05': 8});
      expect(await repo.hourlyStatistics(), {23: 3, 0: 8});
    },
  );

  test(
    'concurrent reading saves serialize and drain new batches exactly once',
    () async {
      final gate = Completer<void>();
      final saved = <int>[];
      final queue = ReadingTimeQueue((_, seconds, _) async {
        if (seconds == 10) await gate.future;
        saved.add(seconds);
      });
      await queue.flush();
      final a = queue.record('a', 10, DateTime(2026));
      final b = queue.record('b', 20, DateTime(2026));
      gate.complete();
      await Future.wait([a, b]);
      await queue.record('a', 30, DateTime(2026));
      expect(saved, [10, 20, 30]);
    },
  );

  test('text search skips broken binary documents, finds repeated hits and stops at limit', () async {
    final repo = await memory();
    addTearDown(repo.close);
    for (final b in await repo.books()) {
      await repo.deleteBook(b.id);
    }
    await repo.addBook(
      Book(id: 'text', title: '正文', chapters: [const Chapter('一', '目标目标结尾')]),
    );
    for (final format in ['PDF', 'CBZ']) {
      await repo.addBook(
        Book(
          id: format,
          title: format,
          format: format,
          chapters: [const Chapter('一', '目标')],
          source: 'AQID',
        ),
      );
      await repo.db.update(
        'books',
        {'content': 'broken'},
        where: 'id = ?',
        whereArgs: [format],
      );
    }
    final result = await repo.searchText('目标');
    expect(result.matches.map((r) => r['offset']), [0, 2]);
    expect(result.truncated, isFalse);
    expect((await repo.searchText('目标', limit: 1)).matches.length, 1);
    expect((await repo.searchText('目标', limit: 1)).truncated, isTrue);
    expect(
      (await repo.searchText('目标', isCancelled: () => true)).matches,
      isEmpty,
    );
    expect(
      (await repo.searchText('目标', budget: Duration.zero)).truncated,
      isTrue,
    );
  });

  test(
    'ZIP reports oversized supported entries instead of silently dropping them',
    () {
      final archive = Archive()
        ..addFile(ArchiveFile.bytes('small.txt', utf8.encode('正常正文')))
        ..addFile(
          ArchiveFile.bytes('large.txt', List.filled(20 * 1024 * 1024 + 1, 65)),
        );
      final entries = decodeArchive(
        Uint8List.fromList(ZipEncoder().encode(archive)),
      );
      expect(entries.map((e) => e['name']), ['small.txt', 'large.txt']);
      expect(entries.last['error'], contains('20 MB'));
      expect(entries.last.containsKey('bytes'), isFalse);
    },
  );

  test('scheduled night uses actual paper and eink remains white', () {
    final s = ReaderSettings(
      extra: {'reader.nightSchedule': true, 'reader.background': 'AAAAAA'},
    );
    expect(
      readerColors(s, at: DateTime(2026, 10, 5, 21)),
      readerSchemes['night'],
    );
    expect(
      readerColors(s, at: DateTime(2026, 10, 5, 12)).first,
      const Color(0xffaaaaaa),
    );
    s.extra['reader.eink'] = true;
    expect(readerColors(s, at: DateTime(2026, 10, 5, 21)), [
      Colors.white,
      Colors.black,
    ]);
  });

  testWidgets(
    'slide moves old page in both directions and fade preserves dark colors',
    (tester) async {
      await tester.runAsync(() async {
        final oldRecorder = ui.PictureRecorder();
        Canvas(oldRecorder).drawColor(const Color(0xffff0000), BlendMode.src);
        final picture = oldRecorder.endRecording();
        final old = await picture.toImage(100, 20);
        picture.dispose();
        Future<List<int>> pixel(String mode, int direction, int x) async {
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder)
            ..drawColor(const Color(0xff0000ff), BlendMode.src);
          TurnPainter(
            old,
            .5,
            null,
            mode: mode,
            direction: direction,
          ).paint(canvas, const Size(100, 20));
          final picture = recorder.endRecording();
          final image = await picture.toImage(100, 20);
          final bytes = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          final offset = (10 * 100 + x) * 4;
          final result = List.generate(4, (i) => bytes.getUint8(offset + i));
          image.dispose();
          picture.dispose();
          return result;
        }

        expect(await pixel('slide', 1, 10), [255, 0, 0, 255]);
        expect(await pixel('slide', 1, 90), [0, 0, 255, 255]);
        expect(await pixel('slide', -1, 10), [0, 0, 255, 255]);
        expect(await pixel('slide', -1, 90), [255, 0, 0, 255]);
        final fade = await pixel('fade', 1, 10);
        expect(fade[0], closeTo(128, 1));
        expect(fade[1], 0);
        expect(fade[2], closeTo(127, 1));
        old.dispose();
      });
    },
  );

  testWidgets('disabled animations never capture pages or drop rapid turns', (
    tester,
  ) async {
    final key = GlobalKey<PageTurnSurfaceState>();
    var turns = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: PageTurnSurface(
            key: key,
            color: Colors.black,
            child: const SizedBox(width: 100, height: 100),
          ),
        ),
      ),
    );
    await key.currentState!.turn(() => turns++, 'slide');
    await key.currentState!.turn(() => turns++, 'curl');
    expect(turns, 2);
    expect(key.currentState!.snapshot, isNull);
    expect(key.currentState!.busy, isFalse);
  });

  testWidgets(
    'rapid animated turns are applied in order rather than discarded',
    (tester) async {
      final key = GlobalKey<PageTurnSurfaceState>();
      final actions = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: PageTurnSurface(
            key: key,
            color: Colors.black,
            child: const SizedBox(width: 100, height: 100),
          ),
        ),
      );
      final first = key.currentState!.turn(() => actions.add(1), 'slide');
      final second = key.currentState!.turn(() => actions.add(2), 'slide');
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      await Future.wait([first, second]);
      expect(actions, [1, 2]);
      expect(key.currentState!.snapshot, isNull);
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'live reading preview fits small screen at large text: $brightness',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final s = ReaderSettings();
        await tester.pumpWidget(
          MaterialApp(
            theme: applicationTheme(brightness),
            builder: (c, child) => MediaQuery(
              data: MediaQuery.of(c)
                  .copyWith(textScaler: const TextScaler.linear(1.5)),
              child: child!,
            ),
            home: Scaffold(
              body: Builder(
                builder: (c) => TextButton(
                  onPressed: () => showReaderSettings(c, s, () async {}),
                  child: const Text('设置'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('设置'));
        await tester.pumpAndSettle();
        final preview = find.byKey(const ValueKey('reader-settings-preview'));
        expect(preview, findsOneWidget);
        await tester.ensureVisible(find.byType(Slider).first);
        tester.widget<Slider>(find.byType(Slider).first).onChanged!(30);
        await tester.pumpAndSettle();
        final text = tester.widget<Text>(
          find.descendant(of: preview, matching: find.byType(Text)).first,
        );
        expect((text.textSpan as TextSpan).style!.fontSize, 30);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'author replacement requires confirmation and cancel preserves author',
    (tester) async {
      final repo = (await tester.runAsync(memory))!;
      addTearDown(repo.close);
      await tester.runAsync(() async {
        for (final b in await repo.books()) {
          await repo.deleteBook(b.id);
        }
        await repo.addBook(
          Book(
            id: 'a',
            title: '甲书',
            author: '甲作者',
            chapters: [const Chapter('一', '正文')],
          ),
        );
      });
      await tester.pumpWidget(
        MaterialApp(
          home: LibraryCollections(
            repo: repo,
            open: (_) async {},
            cover: (_) => const SizedBox(),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('作者'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.byTooltip('新建分组'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.enterText(find.byType(TextFormField), '乙作者');
      await tester.tap(find.text('保存'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('甲书'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('加入所选书籍'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('更改作者？'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, '取消').last);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect((await tester.runAsync(() => repo.book('a')))!.author, '甲作者');
    },
  );

  testWidgets('entry loading and errors do not look like an empty collection', (
    tester,
  ) async {
    final repo = _DelayedEntries();
    await tester.pumpWidget(
      MaterialApp(
        home: EntryScreen(
          repo: repo,
          kind: 'vocabulary',
          title: '生词本',
          fields: ['词语'],
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('点击 +，添加你的第一条记录'), findsNothing);
    repo.ready.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(find.textContaining('记录读取失败'), findsOneWidget);
    expect(find.text('点击 +，添加你的第一条记录'), findsNothing);
  });

  final output = Platform.environment['SHUYE_CAPTURE_DIR'];
  testWidgets('capture reading settings integration', (tester) async {
    await loadShuyeSerif(tester);
    await tester.runAsync(() async {
      for (final font in [
        ('Roboto', 'SHUYE_PREVIEW_FONT'),
        ('serif', 'SHUYE_PREVIEW_SERIF'),
        ('MaterialIcons', 'SHUYE_PREVIEW_ICONS'),
      ]) {
        final loader = FontLoader(font.$1)
          ..addFont(
            Future.value(
              ByteData.sublistView(
                await File(Platform.environment[font.$2]!).readAsBytes(),
              ),
            ),
          );
        await loader.load();
      }
    });
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final brightness in Brightness.values) {
      final s = ReaderSettings();
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: applicationTheme(brightness),
            builder: (c, child) => MediaQuery(
              data: MediaQuery.of(c)
                  .copyWith(textScaler: const TextScaler.linear(1.5)),
              child: child!,
            ),
            home: Scaffold(
              body: Builder(
                builder: (c) => Column(
                  children: [
                    TextButton(
                      onPressed: () => showReaderSettings(c, s, () async {}),
                      child: const Text('排版'),
                    ),
                    TextButton(
                      onPressed: () => advancedReaderSettings(c, s, () {}),
                      child: const Text('控制'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      Future<void> capture(String name) async {
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject() as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$output/$name-${brightness.name}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await tester.tap(find.text('排版'));
      await capture('reading-preview');
      Navigator.of(
        tester.element(find.byKey(const ValueKey('reader-settings-preview'))),
      ).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('控制'));
      await capture('reading-controls');
      Navigator.of(tester.element(find.text('阅读控制'))).pop();
      await tester.pumpAndSettle();
    }
  }, skip: output == null);
}

class _DelayedEntries extends ReaderRepository {
  _DelayedEntries() : super(_UnusedDatabase());
  final ready = Completer<List<Map<String, dynamic>>>();
  @override
  Future<List<Map<String, dynamic>>> entries(String kind, {String? bookId}) =>
      ready.future;
}

class _UnusedDatabase implements Database {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
