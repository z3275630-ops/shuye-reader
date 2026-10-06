import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shuye_reader/appearance.dart';
import 'package:shuye_reader/models.dart';
import 'package:shuye_reader/privacy.dart';
import 'package:shuye_reader/progress_queue.dart';
import 'package:shuye_reader/reader.dart';
import 'package:shuye_reader/repository.dart';
import 'package:shuye_reader/runtime_maintenance.dart';

void main() {
  test('progress writes coalesce immutable columns and serialize', () async {
    final gate = Completer<void>();
    final writes = <Map<String, Object?>>[];
    final queue = ProgressQueue((snapshot) async {
      writes.add(snapshot);
      if (writes.length == 1) await gate.future;
    });
    final input = <String, Object?>{'offset': 1};
    final first = queue.save(input);
    input['offset'] = 999;
    final others = [
      queue.save({'offset': 2, 'metadata': 'frozen'}),
      queue.save({'offset': 3}),
      queue.save({'offset': 4}),
    ];
    expect(writes, [
      {'offset': 1},
    ]);
    gate.complete();
    await Future.wait([first, ...others, queue.flush()]);
    expect(writes.length, 2);
    expect(writes.last, {'offset': 4, 'metadata': 'frozen'});
  });

  test('failed progress remains available for a later flush', () async {
    var fail = true;
    final written = <int>[];
    final queue = ProgressQueue((data) async {
      if (fail) throw StateError('disk unavailable');
      written.add(data['offset'] as int);
    });
    await expectLater(queue.save({'offset': 7}), throwsStateError);
    fail = false;
    await queue.flush();
    expect(written, [7]);
  });

  test(
    'synchronous progress failures can retry without sticking the queue',
    () async {
      var fail = true;
      final queue = ProgressQueue((data) {
        if (fail) throw StateError('writer unavailable');
        return Future.value();
      });
      await expectLater(queue.save({'offset': 9}), throwsStateError);
      fail = false;
      await queue.flush();
    },
  );

  test(
    'fonts register once, changed content loads and failures retry',
    () async {
      var loads = 0, fail = false;
      final cache = ImportedFontCache((family, data) async {
        loads++;
        if (fail) throw FormatException('invalid face');
      });
      await Future.wait([
        cache.load('user', 'first'),
        cache.load('user', 'first'),
      ]);
      await cache.load('user', 'first');
      expect(loads, 1);
      await cache.load('user', 'changed');
      fail = true;
      await expectLater(cache.load('other', 'bad'), throwsFormatException);
      fail = false;
      await cache.load('other', 'bad');
      expect(loads, 4);
    },
  );

  test('share cleanup keeps recent, foreign and non-file entries', () async {
    final root = await Directory.systemTemp.createTemp('shuye-cache-test-');
    addTearDown(() => root.delete(recursive: true));
    final now = DateTime.now();
    final old = await File('${root.path}/shuye-share-1.png')
        .writeAsString('old');
    await old.setLastModified(now.subtract(const Duration(days: 2)));
    final recent = await File('${root.path}/shuye-share-2.png')
        .writeAsString('new');
    final foreign = await File('${root.path}/other.png').writeAsString('keep');
    final directory = await Directory('${root.path}/shuye-share-3.png')
        .create();
    await cleanOldShareCards(root, now: now);
    expect(await old.exists(), false);
    expect(await recent.exists(), true);
    expect(await foreign.exists(), true);
    expect(await directory.exists(), true);
  });

  test(
    'audio rollback removes unregistered copies and preserves registered ones',
    () async {
      final root = await Directory.systemTemp.createTemp('shuye-audio-test-');
      addTearDown(() => root.delete(recursive: true));
      final failed = await File('${root.path}/failed.mp3')
          .writeAsString('audio');
      await expectLater(
        registerAudioCopy(failed, () async => throw StateError('db')),
        throwsStateError,
      );
      expect(await failed.exists(), false);
      final saved = await File('${root.path}/saved.mp3').writeAsString('audio');
      await registerAudioCopy(saved, () async {});
      expect(await saved.exists(), true);
    },
  );

  test(
    'alignment changes preserve prepared source and complete pagination',
    () {
      final settings = ReaderSettings();
      final text = List.filled(60, '短句。她说：“我们读下一页。”\n').join();
      expect(readerTextAlign(settings), TextAlign.justify);
      settings.extra['reader.alignment'] = 'left';
      expect(readerTextAlign(settings), TextAlign.left);
      for (final width in [264.0, 334.0]) {
        final pages = paginate(
          text,
          const TextStyle(fontSize: 18, height: 1.65),
          width,
          450,
          TextScaler.linear(1.5),
          settings: settings,
        );
        expect(pages.map((p) => text.substring(p.start, p.end)).join(), text);
      }
      expect(
        ReaderSettings.fromJson(settings.toJson())
            .value('reader.alignment', ''),
        'left',
      );
    },
  );

  test('backup waits for latest progress and metadata; restore isolates old queues', () async {
    sqfliteFfiInit();
    final repo = await ReaderRepository.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(repo.close);
    final book = await repo.book((await repo.books()).first.id);
    final saves = <Future<void>>[];
    for (var n = 0; n < 20; n++) {
      book.offset = n;
      saves.add(repo.saveProgress(book));
    }
    book.metadata['pdfPage'] = 17;
    saves.add(repo.saveMetadata(book));
    final backup = await repo.backup();
    await Future.wait(saves);
    final row = (jsonDecode(backup)['books'] as List).firstWhere(
      (row) => row['id'] == book.id,
    );
    expect(row['offset'], 19);
    expect(row['metadata']['pdfPage'], 17);
    await repo.restore(backup);
    await repo.flushProgress();
    expect((await repo.book(book.id)).offset, 19);
  });

  testWidgets(
    'privacy lock pauses reading time and hardware/automatic page turns',
    (tester) async {
      sqfliteFfiInit();
      privacyLocked.value = false;
      final repo = (await tester.runAsync(
        () => ReaderRepository.open(
          path: inMemoryDatabasePath,
          factory: databaseFactoryFfi,
        ),
      ))!;
      final chosen = (await tester.runAsync(
        () async => repo.book((await repo.books()).first.id),
      ))!;
      final settings = ReaderSettings()..extra['reader.autoInterval'] = 2;
      await tester.pumpWidget(
        MaterialApp(
          theme: applicationTheme(Brightness.light),
          home: ReaderScreen(
            book: chosen,
            settings: settings,
            repository: repo,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('阅读工具'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('自动翻页'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
      privacyLocked.value = true;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(repo.flushReading);
      final before = (await tester.runAsync(repo.statistics))!;
      final offset = chosen.offset;
      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.pump(const Duration(seconds: 5));
      await tester.runAsync(repo.flushReading);
      expect((await tester.runAsync(repo.statistics))!, before);
      expect(chosen.offset, offset);
      privacyLocked.value = false;
      await tester.pump(const Duration(seconds: 2));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(repo.flushReading);
      final after = (await tester.runAsync(repo.statistics))!;
      expect(
        after.values.fold<int>(0, (a, b) => a + b),
        greaterThan(before.values.fold<int>(0, (a, b) => a + b)),
      );
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      await tester.runAsync(repo.flushReading);
      await tester.runAsync(repo.close);
      privacyLocked.value = false;
    },
  );
}
