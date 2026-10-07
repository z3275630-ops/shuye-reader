import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:http/io_client.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shuye_reader/importer.dart';
import 'package:shuye_reader/models.dart';
import 'package:shuye_reader/reader_gestures.dart';
import 'package:shuye_reader/repository.dart';
import 'package:shuye_reader/services.dart';
import 'package:shuye_reader/typography.dart';
import 'package:shuye_reader/workbench.dart';
import 'package:shuye_reader/lan_backup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  test(
    'DOCX, RTF and uncompressed PalmDOC import actual content and reject DRM',
    () {
      final zip = Archive();
      final xml = utf8.encode(
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body><w:p><w:r><w:t>文档正文🙂</w:t></w:r></w:p></w:body></w:document>',
      );
      zip.addFile(ArchiveFile('word/document.xml', xml.length, xml));
      expect(
        parseBook({
          'name': 'test.docx',
          'bytes': Uint8List.fromList(ZipEncoder().encode(zip)),
        }).chapters.single.text,
        '文档正文🙂',
      );
      final rtf = parseBook({
        'name': 'test.rtf',
        'bytes': Uint8List.fromList(
          ascii.encode(r'{\rtf1\ansi\u20013?\u25991?\par paragraph}'),
        ),
      });
      expect(rtf.chapters.single.text, contains('中文'));
      expect(rtf.chapters.single.text, contains('paragraph'));
      final content = utf8.encode('<html><body><p>Kindle正文</p></body></html>');
      final palm = Uint8List(112 + content.length);
      final header = ByteData.sublistView(palm);
      header.setUint16(76, 2);
      header.setUint32(78, 96);
      header.setUint32(86, 112);
      header.setUint16(96, 1);
      header.setUint16(104, 1);
      palm.setRange(112, palm.length, content);
      expect(
        parseBook({'name': 'test.mobi', 'bytes': palm}).chapters.single.text,
        'Kindle正文',
      );
      header.setUint16(108, 1);
      expect(
        () => parseBook({'name': 'test.azw', 'bytes': palm}),
        throwsFormatException,
      );
    },
  );
  test('book proposals require explicit application and reject stale or unsupported changes', () async {
    final repo = await ReaderRepository.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(repo.close);
    final b = Book(
      id: 'proposal-book',
      title: '原名',
      chapters: const [Chapter('章', '原文')],
    );
    await repo.addBook(b);
    final id = await repo.proposeBookUpdate(b.id, {
      'title': '新书名',
      'tags': '小说',
    });
    expect((await repo.book(b.id)).title, '原名');
    await repo.applyBookProposal(id);
    expect((await repo.book(b.id)).title, '新书名');
    expect((await repo.book(b.id)).chapters.single.text, '原文');
    await expectLater(repo.applyBookProposal(id), throwsStateError);
    final stale = await repo.proposeBookUpdate(b.id, {'title': '另一名称'});
    final changed = (await repo.book(b.id))..title = '人工修改';
    await repo.updateBook(changed);
    await expectLater(repo.applyBookProposal(stale), throwsStateError);
    expect((await repo.book(b.id)).title, '人工修改');
    await expectLater(
      repo.proposeBookUpdate(b.id, {'source': 'overwrite'}),
      throwsFormatException,
    );
  });
  test(
    'temporary LAN transfer serves only authenticated encrypted snapshots',
    () async {
      final transfer = LanBackup();
      await transfer.start(
        'private-text',
        'backup-password',
        address: InternetAddress.loopbackIPv4,
      );
      addTearDown(transfer.stop);
      final c = IOClient(_DirectHttp().createHttpClient(null));
      addTearDown(c.close);
      final base = 'http://127.0.0.1:${transfer.server!.port}/backup';
      expect((await c.get(Uri.parse(base))).statusCode, 403);
      final response = await c.get(Uri.parse('$base?key=${transfer.token}'));
      expect(response.statusCode, 200);
      expect(response.body, isNot(contains('private-text')));
      expect(
        await BackupCipher.decrypt(response.body, 'backup-password'),
        'private-text',
      );
      expect(response.headers['cache-control'], 'no-store');
      expect(
        (await c.post(Uri.parse('$base?key=${transfer.token}'))).statusCode,
        404,
      );
    },
  );
  test('KOReader uses official authentication and refuses incompatible text uploads', () async {
    final mock = MockClient((r) async {
      expect(r.headers['x-auth-user'], 'reader');
      expect(r.headers['x-auth-key'], '5f4dcc3b5aa765d61d8327deb882cf99');
      expect(r.headers['accept'], 'application/vnd.koreader.v1+json');
      expect(r.url.path, '/syncs/progress/document');
      return http.Response('{"percentage":0.75}', 200);
    });
    expect(
      await KoReaderProgress(client: mock)
          .download('https://sync.example', 'reader', 'password', 'document'),
      .75,
    );
    await expectLater(
      KoReaderProgress(client: mock).uploadPdf(
        'https://sync.example',
        'reader',
        'password',
        'document',
        Book(id: 'txt', title: '书', chapters: const [Chapter('章', '文')]),
      ),
      throwsFormatException,
    );
  });
  Future<ReaderRepository> memory() => ReaderRepository.open(
    path: inMemoryDatabasePath,
    factory: databaseFactoryFfi,
  );
  Book book() => Book(
    id: 'new',
    title: '新书',
    source: base64Encode([1, 2, 3]),
    chapters: const [Chapter('章一', '前言🙂中文Flutter故事'), Chapter('章二', '新的故事')],
  );

  test(
    'summary queries retain accurate progress and never load book resources',
    () async {
      final repo = await memory();
      addTearDown(repo.close);
      final b = book()
        ..chapter = 1
        ..offset = 2;
      await repo.addBook(b);
      final small = (await repo.books(summaries: true))
          .singleWhere((b) => b.id == 'new');
      expect(small.isSummary, isTrue);
      expect(small.source, isNull);
      expect(small.chapters.every((c) => c.text == ' '), isTrue);
      expect(small.words, b.words);
      expect(small.progress, closeTo(b.progress, 1e-9));
      expect((await repo.book('new')).source, b.source);
      expect(small.toRow, throwsStateError);
    },
  );

  test('editing a chapter repairs note anchors and preserves backups and hourly statistics', () async {
    final repo = await memory();
    addTearDown(repo.close);
    final b = book()..offset = 12;
    await repo.addBook(b);
    await repo.addNote(
      const Note(
        id: 'n',
        bookId: 'new',
        chapter: 0,
        offset: 12,
        quote: '故事',
        comment: '原文保留',
        tags: '小说,关注',
        created: 1,
      ),
    );
    await repo.editChapter(b, 0, const Chapter('修订', '故事结束'));
    expect((await repo.notes()).single.offset, 0);
    expect(b.offset, 4);
    await repo.record('new', 60, at: DateTime(2026, 10, 5, 23));
    final backup = await repo.backup();
    await repo.restore(backup);
    expect((await repo.notes()).single.tags, '小说,关注');
    expect(await repo.hourlyStatistics(), {23: 60});
    expect(
      (await repo.books(summaries: true))
          .singleWhere((b) => b.id == 'new')
          .words,
      b.words,
    );
  });

  test('v1 SQLite upgrades retain progress, notes and records without resurrecting deleted samples', () async {
    final dir = await Directory.systemTemp.createTemp('shuye-upgrade-');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/legacy.db';
    final legacy = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE books (id TEXT PRIMARY KEY, title TEXT NOT NULL, author TEXT NOT NULL, format TEXT NOT NULL, cover TEXT, added INTEGER NOT NULL, chapter INTEGER NOT NULL, offset INTEGER NOT NULL, last_read INTEGER NOT NULL, content TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE notes (id TEXT PRIMARY KEY, book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE, chapter INTEGER NOT NULL, offset INTEGER NOT NULL, quote TEXT NOT NULL, comment TEXT NOT NULL, created INTEGER NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE read_records (id INTEGER PRIMARY KEY AUTOINCREMENT, book_id TEXT NOT NULL REFERENCES books(id) ON DELETE CASCADE, day TEXT NOT NULL, seconds INTEGER NOT NULL)',
          );
        },
      ),
    );
    final row = (book()..offset = 7).toRow()
      ..remove('metadata')
      ..remove('source');
    await legacy.insert('books', row);
    await legacy.insert('settings', {
      'key': '_migration_seed_v1_completed',
      'value': 'true',
    });
    await legacy.insert('notes', {
      'id': 'legacy-note',
      'book_id': 'new',
      'chapter': 0,
      'offset': 7,
      'quote': '中文',
      'comment': '旧笔记',
      'created': 1,
    });
    await legacy.insert('read_records', {
      'book_id': 'new',
      'day': '2026-10-04',
      'seconds': 300,
    });
    await legacy.close();
    final repo = await ReaderRepository.open(
      path: path,
      factory: databaseFactoryFfi,
    );
    try {
      expect((await repo.books(summaries: true)).single.offset, 7);
      expect(
        (await repo.book('new')).chapters.first.text,
        book().chapters.first.text,
      );
      expect((await repo.notes()).single.comment, '旧笔记');
      expect((await repo.notes()).single.tags, '');
      expect(await repo.statistics(), {'2026-10-04': 300});
      expect(await repo.hourlyStatistics(), isEmpty);
      await repo.restore(await repo.backup());
      expect((await repo.books()).length, 1);
    } finally {
      await repo.close();
    }
  });

  test('encrypted snapshots round trip, reject wrong passwords and authenticated tampering', () async {
    const plain = '{"书库":"中文🙂", "key":123}';
    final encrypted = await BackupCipher.encrypt(plain, 'safe-password');
    expect(encrypted.contains('中文'), isFalse);
    expect(await BackupCipher.decrypt(encrypted, 'safe-password'), plain);
    await expectLater(
      BackupCipher.decrypt(encrypted, 'wrong-password'),
      throwsFormatException,
    );
    final changed = jsonDecode(encrypted) as Map<String, dynamic>;
    final bytes = base64Decode(changed['data'] as String);
    bytes[0] ^= 1;
    changed['data'] = base64Encode(bytes);
    await expectLater(
      BackupCipher.decrypt(jsonEncode(changed), 'safe-password'),
      throwsFormatException,
    );
  });

  test('simplified/traditional conversion, inserted spacing and hyphenation preserve source anchors', () async {
    await ChineseConverter.load();
    const raw = '中文Flutter閱讀🙂\n广告\ncharacteristically';
    final s = ReaderSettings(purifyLines: '广告');
    s.extra.addAll({
      'reader.chinese': 'simplified',
      'reader.hyphenation': true,
    });
    final mapped = prepareText(raw, s);
    expect(mapped.text.replaceAll('\u00ad', ''), contains('中文 Flutter 阅读🙂'));
    expect(mapped.text.contains('广告'), isFalse);
    expect(mapped.offsets.length, mapped.text.length + 1);
    expect(mapped.offsets.last, raw.length);
    expect(mapped.offsets.every((n) => n >= 0 && n <= raw.length), isTrue);
    for (var i = 1; i < mapped.offsets.length; i++) {
      expect(mapped.offsets[i] >= mapped.offsets[i - 1], isTrue);
    }
    final at = mapped.text.indexOf('阅读');
    expect(raw.substring(mapped.offsets[at], mapped.offsets[at + 2]), '閱讀');
    expect(ChineseConverter.convert('中文阅读', 'traditional'), '中文閱讀');
  });

  test('EPUB image export reimports with text and chapter order, CBZ sorts page numbers naturally', () {
    final image = base64Encode(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9Zl1sAAAAASUVORK5CYII=',
      ),
    );
    final original = Book(
      id: 'illustrated',
      title: '图文',
      author: '作者',
      chapters: [
        Chapter('第一章', '首段正文', images: [image]),
        const Chapter('第二章', '末段正文'),
      ],
    );
    final exported = exportEpub(original);
    final archive = ZipDecoder().decodeBytes(exported);
    expect(archive.files.first.name, 'mimetype');
    expect(archive.files.first.compression, CompressionType.none);
    final parsed = parseBook({'name': '图文.epub', 'bytes': exported});
    expect(parsed.title, '图文');
    expect(parsed.author, '作者');
    expect(parsed.chapters.first.text, contains('首段正文'));
    expect(parsed.chapters.first.images.single, image);
    expect(parsed.chapters.last.text, contains('末段正文'));
    final comic = Archive();
    for (final number in [10, 2, 1]) {
      final bytes = [...base64Decode(image), number];
      comic.addFile(ArchiveFile('page$number.png', bytes.length, bytes));
    }
    final cbz = parseBook({
      'name': '漫画.cbz',
      'bytes': Uint8List.fromList(ZipEncoder().encode(comic)),
    });
    expect(
      cbz.chapters.map((c) => base64Decode(c.images.single).last).toList(),
      [1, 2, 10],
    );
  });

  test(
    'AI sends only bounded user-approved context and sanitizes HTTP failures',
    () async {
      final mock = MockClient((r) async {
        expect(r.url.toString(), 'https://reader.example/v1/chat/completions');
        expect(r.headers['authorization'], 'Bearer sample-key');
        final payload = jsonDecode(r.body) as Map;
        final text = (payload['messages'] as List).last['content'] as String;
        expect(text.length, lessThan(30100));
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': '答复'},
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      expect(
        await AiClient(client: mock).answer(
          endpoint: 'https://reader.example/v1',
          key: 'sample-key',
          model: 'user-model',
          prompt: '解释',
          context: List.filled(40000, '文').join(),
        ),
        '答复',
      );
      final error = MockClient(
        (_) async => http.Response('secret server data', 401),
      );
      await expectLater(
        request('GET', Uri.parse('https://reader.example'), client: error),
        throwsA(
          isA<HttpException>().having(
            (e) => e.message,
            'safe error',
            isNot(contains('secret')),
          ),
        ),
      );
      expect(
        () => secureEndpoint('https://name:secret@reader.example'),
        throwsFormatException,
      );
      expect(
        () => secureEndpoint('http://reader.example'),
        throwsFormatException,
      );
    },
  );

  test('MCP enforces token, origin and session; handshake and bounded book search work', () async {
    final repo = await memory();
    addTearDown(repo.close);
    await repo.addBook(book());
    final mcp = McpService(repo);
    await mcp.start();
    addTearDown(mcp.stop);
    final c = IOClient(_DirectHttp().createHttpClient(null));
    addTearDown(c.close);
    final uri = Uri.parse(mcp.address);
    final headers = {
      'Authorization': 'Bearer ${mcp.token}',
      'Content-Type': 'application/json',
    };
    Map<String, dynamic> rpc(String method, [Map<String, dynamic>? params]) => {
      'jsonrpc': '2.0',
      'id': 1,
      'method': method,
      'params': ?params,
    };
    expect(
      (await c.post(uri, body: jsonEncode(rpc('initialize')))).statusCode,
      401,
    );
    expect(
      (await c.post(
        uri,
        headers: {...headers, 'Origin': 'https://untrusted.example'},
        body: jsonEncode(rpc('initialize')),
      )).statusCode,
      403,
    );
    expect(
      (await c.post(
        uri,
        headers: headers,
        body: jsonEncode(rpc('tools/list')),
      )).statusCode,
      404,
    );
    final initialized = await c.post(
      uri,
      headers: headers,
      body: jsonEncode(rpc('initialize', {'protocolVersion': '2025-11-25'})),
    );
    expect(initialized.statusCode, 200);
    expect(
      jsonDecode(initialized.body)['result']['protocolVersion'],
      '2025-11-25',
    );
    final session = initialized.headers['mcp-session-id']!;
    final authenticated = {...headers, 'Mcp-Session-Id': session};
    final found = await c.post(
      uri,
      headers: authenticated,
      body: jsonEncode(
        rpc('tools/call', {
          'name': 'search',
          'arguments': {'query': '故事'},
        }),
      ),
    );
    expect(found.statusCode, 200);
    expect(found.body, contains('新书'));
    expect((await c.delete(uri, headers: authenticated)).statusCode, 204);
    expect(
      (await c.post(
        uri,
        headers: authenticated,
        body: jsonEncode(rpc('tools/list')),
      )).statusCode,
      404,
    );
  });

  testWidgets(
    'reader taps respond immediately without a double-tap delay; long presses select',
    (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReaderTapSurface(
              canTurn: () => true,
              onTap: (_) => taps++,
              onHorizontalDragEnd: (_) {},
              child: const SizedBox.expand(child: SelectableText('可选择的正文')),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(SelectableText));
      expect(taps, 1);
      await tester.tapAt(const Offset(200, 200));
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tapAt(const Offset(200, 200));
      await tester.pump(const Duration(milliseconds: 350));
      expect(taps, 3);
      await tester.longPress(find.byType(SelectableText));
      await tester.pump(const Duration(milliseconds: 350));
      expect(taps, 3);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

class _DirectHttp extends HttpOverrides {}
