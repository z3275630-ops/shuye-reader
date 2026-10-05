import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shuye_reader/appearance.dart';
import 'package:shuye_reader/main.dart';
import 'package:shuye_reader/models.dart';
import 'package:shuye_reader/reader.dart';
import 'package:shuye_reader/reader_gestures.dart';
import 'package:shuye_reader/repository.dart';
import 'package:shuye_reader/services.dart';

import 'preview_fonts.dart';

Future<void> ready(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 120)),
  );
  await tester.pumpAndSettle();
}

class _SyncSecrets extends Secrets {
  @override
  Future<String> read(String key) async => 'test-local-sync';
}

// Only the ephemeral loopback server in this test receives real networking.
class _LocalHttp extends HttpOverrides {}

void main() {
  sqfliteFfiInit();
  setUp(() => appAppearance.value = const AppAppearance());
  test('old defaults become Claude; mist round trips and custom typography survives', () {
    final old = ReaderSettings.fromJson({
      'reader.fontSize': 20,
      'reader.lineHeight': 1.85,
      'reader.theme': 'paper',
    });
    expect(old.theme, 'follow');
    expect(old.fontSize, 18);
    expect(old.lineHeight, 1.65);
    final mist = ReaderSettings.fromJson({
      'reader.theme': 'mist',
      'reader.fontSize': 26,
      'reader.lineHeight': 2.1,
      'reader.customFont': 'Personal',
    });
    expect(AppAppearance.fromSettings(mist).theme, 'mist');
    expect(mist.fontSize, 26);
    expect(readerFont(mist), 'Personal');
    expect(
      readerColors(ReaderSettings.fromJson(mist.toJson()))[0],
      const Color(0xfff7fafc),
    );
  });
  testWidgets(
    'reader palette reaches home, shelf, re-entry and app restart; chrome and boundary feedback',
    (tester) async {
      await loadShuyeSerif(tester);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = (await tester.runAsync(
        () => ReaderRepository.open(
          path: inMemoryDatabasePath,
          factory: databaseFactoryFfi,
        ),
      ))!;
      final book = Book(
        id: 'theme-flow',
        title: '主题联动验证',
        chapters: [const Chapter('一', '正文测试。')],
      );
      await tester.runAsync(() => repo.addBook(book));
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        DeviceReader.channel,
        (call) async {
          calls.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          DeviceReader.channel,
          null,
        ),
      );
      await tester.pumpWidget(ShuyeApp(repository: repo));
      await ready(tester);
      Future<void> open() async {
        DeviceReader.events.add(MethodCall('link', 'shuye://book/${book.id}'));
        await ready(tester);
      }

      Color appPaper() => Theme.of(
        tester.element(find.byType(LibraryHome, skipOffstage: false)),
      ).colorScheme.surface;
      await open();
      await tester.tap(find.byTooltip('阅读设置'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.widgetWithText(ChoiceChip, '海雾'));
      await tester.tap(find.widgetWithText(ChoiceChip, '海雾'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('开始阅读'));
      await tester.tap(find.text('开始阅读'));
      await ready(tester);
      expect(appPaper(), const Color(0xfff7fafc));
      expect(
        tester
            .widget<Scaffold>(
              find
                  .descendant(
                    of: find.byType(ReaderScreen),
                    matching: find.byType(Scaffold),
                  )
                  .first,
            )
            .backgroundColor,
        isNull,
      );
      expect(
        readerColors((await tester.runAsync(repo.settings))!)[0],
        const Color(0xfff7fafc),
      );
      final surface = find.byType(SelectableText).first;
      await tester.tapAt(tester.getCenter(surface));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsNothing);
      expect(find.byType(ReaderFooter), findsNothing);
      expect(
        calls.any((c) => c.method == 'fullscreen' && c.arguments == true),
        isTrue,
      );
      // Swipe against the start repeatedly: no intrusive first-page toast.
      for (var i = 0; i < 3; i++) {
        await tester.fling(
          find.byType(ReaderTapSurface).first,
          const Offset(220, 0),
          1000,
        );
        await tester.pumpAndSettle();
      }
      expect(find.text('已到全书第一页'), findsNothing);
      await tester.fling(
        find.byType(ReaderTapSurface).first,
        const Offset(-220, 0),
        1000,
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('已读到全书末页'), findsOneWidget);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      await tester.fling(
        find.byType(ReaderTapSurface).first,
        const Offset(-220, 0),
        1000,
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('已读到全书末页'), findsNothing);
      await tester.tapAt(tester.getCenter(find.byType(SelectableText).first));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(find.byType(ReaderFooter), findsOneWidget);
      await tester.pageBack();
      await ready(tester);
      expect(appPaper(), const Color(0xfff7fafc));
      await tester.tap(find.text('书架'));
      await ready(tester);
      expect(appPaper(), const Color(0xfff7fafc));
      await open();
      await tester.tap(find.byTooltip('阅读设置'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.widgetWithText(ChoiceChip, '夜读'));
      await tester.tap(find.widgetWithText(ChoiceChip, '夜读'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('开始阅读'));
      await tester.tap(find.text('开始阅读'));
      await ready(tester);
      expect(
        Theme.of(tester.element(find.byType(LibraryHome, skipOffstage: false)))
            .brightness,
        Brightness.dark,
      );
      await tester.pageBack();
      await ready(tester);
      await tester.pumpWidget(const SizedBox());
      await ready(tester);
      await tester.pumpWidget(ShuyeApp(repository: repo));
      await ready(tester);
      expect(
        Theme.of(tester.element(find.byType(LibraryHome))).brightness,
        Brightness.dark,
      );
      await tester.pumpWidget(const SizedBox());
      await ready(tester);
      await tester.runAsync(repo.close);
      expect(tester.takeException(), isNull);
    },
  );
  test('corrupt settings keep books and raw recovery value; invalid dates never replace library', () async {
    final repo = await ReaderRepository.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(repo.close);
    final before = (await repo.books()).length;
    await repo.db.execute(
      'INSERT OR REPLACE INTO settings (key,value) VALUES (?,?)',
      ['reader.config', '{bad'],
    );
    final recovered = await repo.settings();
    expect(recovered.theme, 'follow');
    expect(recovered.flag('privacy.lock'), isTrue);
    expect((await repo.settings()).flag('reader.configRecovered'), isTrue);
    expect(repo.settingsWarning, isNotNull);
    expect((await repo.books()).length, before);
    expect(
      (await repo.db.query(
        'settings',
        where: 'key = ?',
        whereArgs: ['_reader.config.corrupt'],
      )).single['value'],
      '{bad',
    );
    for (final day in ['2026-02-31', '2026-13-01', '0000-01-01']) {
      expect(validRecordDay(day), isFalse);
      final backup = jsonDecode(await repo.backup()) as Map<String, dynamic>;
      backup['records'] = [
        {
          'book_id': (await repo.books()).first.id,
          'day': day,
          'seconds': 30,
          'hour': -1,
        },
      ];
      await expectLater(
        repo.restore(jsonEncode(backup)),
        throwsFormatException,
      );
      expect((await repo.books()).length, before);
    }
    expect(validRecordDay('2028-02-29'), isTrue);
    expect(validRecordDay('2030-01-01'), isTrue);
  });
  test('backup flushes active readers, restore drains old pending records before replacement', () async {
    final repo = await ReaderRepository.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(repo.close);
    final book = (await repo.books()).first;
    var pending = 17;
    Future<void> flush() async {
      final n = pending;
      pending = 0;
      await repo.record(book.id, n, at: DateTime(2026, 10, 5, 8));
    }

    repo.readingFlushers.add(flush);
    final backup = jsonDecode(await repo.backup()) as Map<String, dynamic>;
    expect((backup['records'] as List).single['seconds'], 17);
    pending = 23;
    await repo.restore(jsonEncode(backup));
    await repo.flushReading();
    expect((await repo.statistics())['2026-10-05'], 17);
    repo.libraryChanging = true;
    await expectLater(repo.record(book.id, 20), throwsStateError);
    await expectLater(repo.backup(), throwsStateError);
    repo.libraryChanging = false;
    await repo.flushReading();
    expect((await repo.statistics())['2026-10-05'], 17);
  });
  testWidgets('widget platform failure does not block cold-start book link', (
    tester,
  ) async {
    final repo = (await tester.runAsync(
      () => ReaderRepository.open(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      ),
    ))!;
    final book = (await tester.runAsync(repo.books))!.first;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      DeviceReader.channel,
      (call) async {
        if (call.method == 'widgets') {
          throw PlatformException(code: 'widgets_failed');
        }
        if (call.method == 'initialLink') return 'shuye://book/${book.id}';
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        DeviceReader.channel,
        null,
      ),
    );
    await tester.pumpWidget(ShuyeApp(repository: repo));
    for (
      var i = 0;
      i < 8 && find.byType(ReaderScreen).evaluate().isEmpty;
      i++
    ) {
      await ready(tester);
    }
    expect(find.byType(ReaderScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await ready(tester);
    await tester.runAsync(repo.close);
  });
  test(
    'download refreshes the same settings object before a subsequent save',
    () async {
      final repo = await ReaderRepository.open(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      );
      addTearDown(repo.close);
      final restored = ReaderSettings(fontSize: 25, lineHeight: 2.0);
      selectAppPalette(restored, 'mist', mode: 'light');
      await repo.saveSettings(restored);
      final encrypted = await BackupCipher.encrypt(
        await repo.backup(),
        'local-test-password',
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        request.response.write(encrypted);
        await request.response.close();
      });
      final current = ReaderSettings(
        extra: {
          'sync.endpoint': 'http://127.0.0.1:${server.port}/backup',
          'sync.user': 'test-user',
        },
      );
      await repo.saveSettings(current);
      await HttpOverrides.runWithHttpOverrides(
        () => SyncService(
          repo,
          _SyncSecrets(),
        ).run(current, download: true, password: 'local-test-password'),
        _LocalHttp(),
      );
      expect(current.fontSize, 25);
      expect(current.value('app.theme', ''), 'mist');
      expect(current.value('sync.endpoint', ''), contains('${server.port}'));
      current.lineHeight = 1.9;
      await repo.saveSettings(current);
      final saved = await repo.settings();
      expect(saved.fontSize, 25);
      expect(saved.lineHeight, 1.9);
      expect(saved.value('app.theme', ''), 'mist');
    },
  );
}
