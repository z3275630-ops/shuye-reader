import 'preview_fonts.dart';

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:shuye_reader/appearance.dart';
import 'package:shuye_reader/document_reader.dart';
import 'package:shuye_reader/edit_dialog.dart';
import 'package:shuye_reader/models.dart';
import 'package:shuye_reader/pdf_controls.dart';
import 'package:shuye_reader/reader_controls.dart';
import 'package:shuye_reader/repository.dart';

void smallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget app(Widget child, Brightness brightness, {double keyboard = 0}) =>
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: applicationTheme(brightness),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(1.5),
          viewInsets: EdgeInsets.only(bottom: keyboard),
        ),
        child: child!,
      ),
      home: child,
    );

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'real editor handles keyboard, validation and secrets: $brightness',
      (tester) async {
        smallScreen(tester);
        Map<String, String>? saved;
        await tester.pumpWidget(
          app(
            Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    saved = await editFields(
                      context,
                      '编辑连接与密码',
                      {'名称': '原名', '密码': 'local-test'},
                      passwords: const {'密码'},
                      validators: {'名称': (v) => v.isEmpty ? '请填写名称' : null},
                    );
                  },
                  child: const Text('编辑'),
                ),
              ),
            ),
            brightness,
            keyboard: 220,
          ),
        );
        await tester.tap(find.text('编辑'));
        await tester.pumpAndSettle();
        final fields = find.byType(TextFormField);
        await tester.ensureVisible(fields.first);
        await tester.enterText(fields.first, '');
        await tester.tap(find.text('保存'));
        await tester.pumpAndSettle();
        expect(find.text('请填写名称'), findsOneWidget);
        expect(saved, isNull);
        await tester.ensureVisible(fields.first);
        await tester.enterText(fields.first, '  家中书库  ');
        await tester.testTextInput.receiveAction(TextInputAction.next);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<EditableText>(find.byType(EditableText).last)
              .focusNode
              .hasFocus,
          isTrue,
        );
        await tester.ensureVisible(find.byTooltip('显示密码'));
        await tester.tap(find.byTooltip('显示密码'));
        await tester.pumpAndSettle();
        final secret = tester.widget<EditableText>(
          find.byType(EditableText).last,
        );
        expect(secret.obscureText, isFalse);
        expect(secret.controller.text, 'local-test');
        await tester.tap(find.byTooltip('隐藏密码'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<EditableText>(find.byType(EditableText).last)
              .obscureText,
          isTrue,
        );
        await tester.tap(fields.last);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(saved, {'名称': '家中书库', '密码': 'local-test'});
        expect(find.byType(AlertDialog), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'PDF thumbnails stay lazy and outline targets are valid: $brightness',
      (tester) async {
        smallScreen(tester);
        final built = <int>{};
        int? selected;
        await tester.pumpWidget(
          app(
            Scaffold(
              body: PdfContentsPanel(
                pageCount: 1000,
                currentPage: 500,
                outline: const [],
                thumbnail: (_, page) {
                  built.add(page);
                  return const ColoredBox(color: Colors.white);
                },
                onSelected: (page) => selected = page,
              ),
            ),
            brightness,
          ),
        );
        await tester.pumpAndSettle();
        expect(built, contains(500));
        expect(built.length, lessThan(15));
        expect(built, isNot(contains(1)));
        await tester.tap(find.text('第 500 页 · 当前页'));
        expect(selected, 500);
        await tester.tap(find.text('目录'));
        await tester.pumpAndSettle();
        expect(find.textContaining('文件未提供目录'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          app(
            Scaffold(
              body: PdfContentsPanel(
                pageCount: 1000,
                currentPage: 1,
                outline: const [
                  PdfOutlineNode(
                    title: '分组标题',
                    dest: null,
                    children: [
                      PdfOutlineNode(
                        title: '第二章',
                        dest: PdfDest(30, PdfDestCommand.fit, null),
                        children: [],
                      ),
                    ],
                  ),
                  PdfOutlineNode(
                    title: '失效页码',
                    dest: PdfDest(1001, PdfDestCommand.fit, null),
                    children: [],
                  ),
                ],
                thumbnail: (_, _) => const SizedBox(),
                onSelected: (page) => selected = page,
              ),
            ),
            brightness,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('分组标题'));
        expect(selected, 500);
        await tester.tap(find.text('失效页码'));
        expect(selected, 500);
        await tester.tap(find.text('第二章'));
        expect(selected, 30);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'invalid reading colors stay in the editor without changing settings',
    (tester) async {
      smallScreen(tester);
      final settings = ReaderSettings();
      var changes = 0;
      await tester.pumpWidget(
        app(
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    advancedReaderSettings(context, settings, () => changes++),
                child: const Text('控制'),
              ),
            ),
          ),
          Brightness.light,
        ),
      );
      await tester.tap(find.text('控制'));
      await tester.pumpAndSettle();
      final colorsEntry = find.text('自定义纸色与文字颜色');
      await tester.scrollUntilVisible(colorsEntry.hitTestable(), 240);
      await tester.pumpAndSettle();
      expect(colorsEntry.hitTestable(), findsOneWidget);
      await tester.tap(colorsEntry.hitTestable());
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.first, 'invalid');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.textContaining('请输入 6 位颜色'), findsOneWidget);
      expect(changes, 0);
      await tester.enterText(fields.first, 'F4EDDF');
      await tester.enterText(fields.last, '3F392E');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(settings.value('reader.background', ''), 'F4EDDF');
      expect(settings.value('reader.foreground', ''), '3F392E');
      expect(changes, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'PDF page controls wrap long counts and disable boundary actions',
    (tester) async {
      smallScreen(tester);
      var jumps = 0;
      await tester.pumpWidget(
        app(
          Scaffold(
            body: PdfPageNavigation(
              page: 100000,
              pageCount: 100000,
              previous: () {},
              next: () {},
              jump: () => jumps++,
            ),
          ),
          Brightness.dark,
        ),
      );
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == '下一页',
              ),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('100000 / 100000 页'));
      expect(jumps, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('PDF search initializes only after the viewer becomes ready', (
    tester,
  ) async {
    final previousBackend = PdfrxEntryFunctions.instance;
    final previousCache = Pdfrx.cacheDirectoryPath;
    PdfrxEntryFunctions.instance = _PendingPdfBackend();
    Pdfrx.cacheDirectoryPath = '.';
    addTearDown(() {
      PdfrxEntryFunctions.instance = previousBackend;
      Pdfrx.cacheDirectoryPath = previousCache;
    });
    final book = Book(
      id: 'pending-pdf',
      title: '同名文件',
      format: 'PDF',
      source: 'AA==',
      chapters: const [],
    );
    final repo = _Repository();
    await tester.pumpWidget(
      app(
        DocumentReader(book: book, repo: repo, settings: ReaderSettings()),
        Brightness.light,
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 6));
    expect(repo.recordedSeconds, 0);
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (w) => w is IconButton && w.tooltip == 'PDF 搜索',
            ),
          )
          .onPressed,
      isNull,
    );
    final viewer = tester.widget<PdfViewer>(find.byType(PdfViewer));
    expect(viewer.documentRef.key.sourceName, 'shuye-pdf:pending-pdf');
    final document = _Document();
    viewer.params.onViewerReady!(document, _ReadyController(document));
    await tester.pump();
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (w) => w is IconButton && w.tooltip == 'PDF 搜索',
            ),
          )
          .onPressed,
      isNotNull,
    );
    expect(book.metadata['pdfPages'], 1);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    final oldPage = book.metadata['pdfPage'];
    viewer.params.onPageChanged!(2);
    await tester.pump();
    expect(book.metadata['pdfPage'], oldPage);
    expect(repo.recordedSeconds, 6);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'PDF search updates counts, boundaries and close without rebuilding the viewer',
    (tester) async {
      smallScreen(tester);
      final searcher = _Search();
      await tester.pumpWidget(
        app(
          Scaffold(body: PdfSearchResults(searcher: searcher)),
          Brightness.dark,
        ),
      );
      expect(find.text('1 / 3 处'), findsOneWidget);
      await tester.tap(find.byTooltip('下个搜索结果'));
      await tester.pump();
      expect(find.text('2 / 3 处'), findsOneWidget);
      await tester.tap(find.byTooltip('下个搜索结果'));
      await tester.pump();
      expect(find.text('3 / 3 处'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == '下个搜索结果',
              ),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byTooltip('上个搜索结果'));
      await tester.pump();
      expect(find.text('2 / 3 处'), findsOneWidget);
      await tester.tap(find.byTooltip('关闭 PDF 搜索'));
      await tester.pump();
      expect(find.byType(IconButton), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  final output = Platform.environment['SHUYE_CAPTURE_DIR'];
  testWidgets('capture real editor and PDF controls', (tester) async {
    await loadShuyeSerif(tester);
    final font = FontLoader('Roboto')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            (await tester.runAsync(
              () =>
                  File(Platform.environment['SHUYE_PREVIEW_FONT']!)
                      .readAsBytes(),
            ))!,
          ),
        ),
      );
    await font.load();
    smallScreen(tester);
    for (final brightness in Brightness.values) {
      final key = GlobalKey();
      final suffix = brightness == Brightness.dark ? 'dark' : 'light';
      Future<void> capture(String name) async {
        final boundary =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(output!).create(recursive: true);
          await File('$output/$name-$suffix.png')
              .writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }

      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: app(
            Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => editFields(context, '自定义主题', {
                    '纸色': 'F4EDDF',
                    '文字': '3F392E',
                  }, description: '填写 6 位颜色，留空恢复默认。'),
                  child: const Text('编辑'),
                ),
              ),
            ),
            brightness,
          ),
        ),
      );
      await tester.tap(find.text('编辑'));
      await tester.pumpAndSettle();
      await capture('editor');
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: app(
            Scaffold(
              body: PdfContentsPanel(
                pageCount: 1000,
                currentPage: 1,
                outline: const [
                  PdfOutlineNode(
                    title: '第一部分',
                    dest: null,
                    children: [
                      PdfOutlineNode(
                        title: '第一章 · 山间来信',
                        dest: PdfDest(1, PdfDestCommand.fit, null),
                        children: [],
                      ),
                      PdfOutlineNode(
                        title: '第二章 · 向远处走',
                        dest: PdfDest(30, PdfDestCommand.fit, null),
                        children: [],
                      ),
                    ],
                  ),
                ],
                thumbnail: (_, _) => const SizedBox(),
                onSelected: (_) {},
              ),
            ),
            brightness,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await capture('pdf-contents');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
  }, skip: output == null);
}

class _PendingPdfBackend implements PdfrxEntryFunctions {
  @override
  Future<void> init() async {}
  @override
  Future<PdfDocument> openData(
    Uint8List data, {
    PdfPasswordProvider? passwordProvider,
    bool firstAttemptByEmptyPassword = true,
    String? sourceName,
    bool allowDataOwnershipTransfer = false,
    bool useProgressiveLoading = false,
    int? maxSizeToCacheOnMemory,
    void Function()? onDispose,
  }) => Completer<PdfDocument>().future;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Document implements PdfDocument {
  @override
  List<PdfPage> get pages => [_Page()];
  @override
  Stream<PdfDocumentEvent> get events => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Page implements PdfPage {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ReadyController extends PdfViewerController {
  _ReadyController(this.document);
  @override
  final PdfDocument document;
  @override
  bool get isReady => true;
}

class _Repository implements ReaderRepository {
  int recordedSeconds = 0;
  @override
  final readingFlushers = <Future<void> Function()>{};
  @override
  int libraryGeneration = 0;
  @override
  bool libraryChanging = false;
  @override
  Future<List<Map<String, dynamic>>> entries(
    String kind, {
    String? bookId,
  }) async => [];
  @override
  Future<void> saveMetadata(Book book) async {}
  @override
  Future<void> record(String bookId, int seconds, {DateTime? at}) async {
    recordedSeconds += seconds;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Range implements PdfPageTextRange {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Search implements PdfTextSearcher {
  final listeners = <VoidCallback>[];
  @override
  int? currentIndex = 0;
  @override
  Pattern? pattern = '查找';
  @override
  bool get isSearching => false;
  @override
  List<PdfPageTextRange> get matches => List.filled(3, _Range());
  @override
  VoidCallback addListener(VoidCallback listener) {
    listeners.add(listener);
    return () => listeners.remove(listener);
  }

  @override
  void removeListener(VoidCallback listener) => listeners.remove(listener);
  @override
  void notifyListeners() {
    for (final listener in List.of(listeners)) {
      listener();
    }
  }

  @override
  Future<int> goToNextMatch() async => currentIndex = currentIndex! + 1;
  @override
  Future<int> goToPrevMatch() async => currentIndex = currentIndex! - 1;
  @override
  void resetTextSearch() {
    pattern = null;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
