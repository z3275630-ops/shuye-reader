import 'app_icons.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

import 'models.dart';
import 'pdf_controls.dart';
import 'reader.dart';
import 'repository.dart';
import 'workbench.dart';

class DocumentReader extends StatefulWidget {
  final Book book;
  final ReaderRepository repo;
  final ReaderSettings settings;
  const DocumentReader({
    super.key,
    required this.book,
    required this.repo,
    required this.settings,
  });
  @override
  State<DocumentReader> createState() => _DocumentReaderState();
}

class _DocumentReaderState extends State<DocumentReader>
    with WidgetsBindingObserver {
  final controller = PdfViewerController();
  PdfTextSearcher? searcher;
  late final Uint8List bytes;
  PdfDocument? document;
  bool night = false, drawing = false, busy = false;
  int page = 1, seconds = 0;
  Timer? timer;
  bool active = true;
  late final int libraryGeneration;
  bool get staleLibrary => libraryGeneration != widget.repo.libraryGeneration;
  DateTime recordAt = DateTime.now();
  List<Map<String, dynamic>> strokes = [];
  @override
  void initState() {
    super.initState();
    libraryGeneration = widget.repo.libraryGeneration;
    widget.repo.readingFlushers.add(flush);
    bytes = base64Decode(widget.book.source!);
    WidgetsBinding.instance.addObserver(this);
    page = (widget.book.metadata['pdfPage'] as int? ?? 1);
    unawaited(loadStrokes());
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!staleLibrary &&
          !widget.repo.libraryChanging &&
          active &&
          !busy &&
          document != null &&
          (ModalRoute.of(context)?.isCurrent ?? true)) {
        final now = DateTime.now();
        if (now.hour != recordAt.hour ||
            now.day != recordAt.day ||
            now.month != recordAt.month ||
            now.year != recordAt.year) {
          unawaited(flush());
          recordAt = now;
        }
        seconds++;
        if (seconds >= 60) unawaited(flush());
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    active = state == AppLifecycleState.resumed;
    if (!active) unawaited(flush());
  }

  Future<void> flush() async {
    if (staleLibrary || widget.repo.libraryChanging) {
      seconds = 0;
      return;
    }
    final n = seconds;
    seconds = 0;
    try {
      await widget.repo.record(widget.book.id, n, at: recordAt);
    } catch (e) {
      if (mounted) toast(context, '阅读时长暂未保存，下次保存时重试：$e');
    }
  }

  Future<void> loadStrokes() async {
    final data = await widget.repo.entries(
      'pdfDrawings',
      bookId: widget.book.id,
    );
    if (mounted) setState(() => strokes = data);
  }

  @override
  void dispose() {
    widget.repo.readingFlushers.remove(flush);
    timer?.cancel();
    searcher?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(flush());
    super.dispose();
  }

  Future<void> run(Future<void> Function() f) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await f();
    } catch (e) {
      if (mounted) toast(context, '操作未完成：$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> extract({bool ocr = false}) async {
    if (document == null) return;
    final chapters = <Chapter>[];
    if (ocr) {
      final target = document!.pages[page - 1];
      final recognizer = TextRecognizer(script: TextRecognitionScript.chinese);
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/shuye-ocr-${DateTime.now().microsecondsSinceEpoch}.png',
      );
      try {
        final rendered = await target.render(
          width: (target.width * 2).round(),
          height: (target.height * 2).round(),
        );
        if (rendered == null) throw const FormatException('无法渲染此页');
        final image = await rendered.createImage();
        rendered.dispose();
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        await file.writeAsBytes(png!.buffer.asUint8List());
        final text = (await recognizer.processImage(
          InputImage.fromFilePath(file.path),
        )).text;
        if (text.trim().isEmpty) throw const FormatException('此页没有识别出文字');
        chapters.add(Chapter('第 $page 页识字', text));
      } finally {
        await recognizer.close();
        if (await file.exists()) await file.delete();
      }
    } else {
      for (final p in document!.pages) {
        final text = (await p.loadText())?.fullText.trim() ?? '';
        if (text.isNotEmpty) chapters.add(Chapter('第 ${p.pageNumber} 页', text));
      }
    }
    if (chapters.isEmpty) throw const FormatException('此 PDF 没有文字层，可尝试“识别当前页”');
    final b = Book(
      id: '${widget.book.id}-${ocr ? 'ocr-$page' : 'reflow'}',
      title: '${widget.book.title} · ${ocr ? '识字 $page' : '重排'}',
      author: widget.book.author,
      format: 'PDF-TEXT',
      chapters: chapters,
    );
    final added = await widget.repo.addBook(b);
    final opened = added ? b : await widget.repo.book(b.id);
    if (mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => ReaderScreen(
            book: opened,
            repository: widget.repo,
            settings: widget.settings,
          ),
        ),
      );
    }
  }

  Future<void> outline() async {
    if (document == null) return;
    final nodes = await document!.loadOutline();
    if (!mounted) return;
    final selected = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(c).height * .78,
          child: PdfContentsPanel(
            pageCount: document!.pages.length,
            currentPage: page,
            outline: nodes,
            thumbnail: (_, n) => PdfPageView(
              document: document,
              pageNumber: n,
              maximumDpi: 72,
              decoration: const BoxDecoration(color: Colors.white),
            ),
            onSelected: (n) => Navigator.pop(c, n),
          ),
        ),
      ),
    );
    if (mounted && selected != null && controller.isReady) {
      await controller.goToPage(pageNumber: selected);
    }
  }

  Future<void> search() async {
    if (searcher == null) return;
    final data = await editFields(context, 'PDF 搜索', {
      '关键词': searcher?.pattern?.toString() ?? '',
    });
    if (!mounted || data == null || data['关键词']!.isEmpty) return;
    searcher?.startTextSearch(data['关键词']!, searchImmediately: true);
  }

  Future<void> jump() async {
    final count = document?.pages.length;
    if (count == null || !controller.isReady) return;
    final data = await editFields(
      context,
      '跳转页码',
      {'页码': '$page'},
      description: '请输入 1–$count 之间的页码。',
      keyboardTypes: const {'页码': TextInputType.number},
      validators: {
        '页码': (value) {
          final n = int.tryParse(value);
          return n != null && n >= 1 && n <= count
              ? null
              : '请输入 1–$count 之间的整数。';
        },
      },
    );
    if (!mounted || data == null || !controller.isReady) return;
    await controller.goToPage(pageNumber: int.parse(data['页码']!));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.book.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      actions: [
        IconButton(
          tooltip: 'PDF 搜索',
          onPressed: !busy && searcher != null
              ? () => unawaited(run(search))
              : null,
          icon: const ShuyeIcon(Icons.search),
        ),
        PopupMenuButton<String>(
          enabled: !busy && document != null,
          onSelected: (v) {
            switch (v) {
              case 'night':
                setState(() => night = !night);
              case 'draw':
                setState(() => drawing = !drawing);
              case 'outline':
                unawaited(run(outline));
              case 'reflow':
                unawaited(run(() => extract()));
              case 'ocr':
                unawaited(run(() => extract(ocr: true)));
              case 'clear':
                unawaited(
                  run(() async {
                    for (final s in strokes.where((s) => s['page'] == page)) {
                      await widget.repo.removeEntry(s['id'] as String);
                    }
                    await loadStrokes();
                  }),
                );
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'outline', child: Text('目录与缩略图')),
            const PopupMenuItem(value: 'reflow', child: Text('提取文字重排')),
            const PopupMenuItem(value: 'ocr', child: Text('识别当前页')),
            PopupMenuItem(value: 'night', child: Text(night ? '恢复日间' : '夜间反色')),
            PopupMenuItem(
              value: 'draw',
              child: Text(drawing ? '退出标注' : '手写标注'),
            ),
            const PopupMenuItem(value: 'clear', child: Text('清除此页标注')),
          ],
        ),
      ],
    ),
    body: Column(
      children: [
        if (busy) const LinearProgressIndicator(),
        Expanded(
          child: ColorFiltered(
            colorFilter: night
                ? const ColorFilter.matrix([
                    -1,
                    0,
                    0,
                    0,
                    255,
                    0,
                    -1,
                    0,
                    0,
                    255,
                    0,
                    0,
                    -1,
                    0,
                    255,
                    0,
                    0,
                    0,
                    1,
                    0,
                  ])
                : const ColorFilter.mode(Colors.transparent, BlendMode.dst),
            child: PdfViewer.data(
              bytes,
              sourceName: 'shuye-pdf:${widget.book.id}',
              controller: controller,
              initialPageNumber: page,
              params: PdfViewerParams(
                onViewerReady: (d, c) {
                  if (!mounted || staleLibrary) return;
                  searcher?.dispose();
                  setState(() {
                    document = d;
                    searcher = PdfTextSearcher(c);
                    page = page.clamp(1, d.pages.length);
                  });
                  widget.book.metadata['pdfPages'] = d.pages.length;
                  unawaited(widget.repo.saveMetadata(widget.book));
                },
                onPageChanged: (n) {
                  if (!mounted ||
                      staleLibrary ||
                      widget.repo.libraryChanging ||
                      n == null) {
                    return;
                  }
                  setState(() => page = n);
                  widget.book.metadata['pdfPage'] = n;
                  widget.book.lastRead = DateTime.now().millisecondsSinceEpoch;
                  unawaited(widget.repo.saveMetadata(widget.book));
                },
                pageOverlaysBuilder: (c, rect, p) => [
                  Positioned.fill(
                    child: IgnorePointer(
                      ignoring: !drawing,
                      child: InkLayer(
                        strokes: strokes
                            .where((s) => s['page'] == p.pageNumber)
                            .toList(),
                        onStroke: (points) async {
                          await widget.repo.putEntry('pdfDrawings', {
                            'page': p.pageNumber,
                            'points': points,
                          }, bookId: widget.book.id);
                          await loadStrokes();
                        },
                      ),
                    ),
                  ),
                ],
                pagePaintCallbacks: [
                  (canvas, rect, p) =>
                      searcher?.pageTextMatchPaintCallback(canvas, rect, p),
                ],
              ),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PdfPageNavigation(
                page: page,
                pageCount: document?.pages.length,
                previous: !busy && controller.isReady
                    ? () => controller.goToPage(pageNumber: page - 1)
                    : null,
                next: !busy && controller.isReady
                    ? () => controller.goToPage(pageNumber: page + 1)
                    : null,
                jump: !busy && controller.isReady
                    ? () => unawaited(run(jump))
                    : null,
              ),
              if (searcher != null) PdfSearchResults(searcher: searcher!),
            ],
          ),
        ),
      ],
    ),
  );
}

class InkLayer extends StatefulWidget {
  final List<Map<String, dynamic>> strokes;
  final Future<void> Function(List<List<double>>) onStroke;
  const InkLayer({super.key, required this.strokes, required this.onStroke});
  @override
  State<InkLayer> createState() => _InkLayerState();
}

class _InkLayerState extends State<InkLayer> {
  List<List<double>> points = [];
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (c, box) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (d) => setState(
        () => points = [
          [
            d.localPosition.dx / box.maxWidth,
            d.localPosition.dy / box.maxHeight,
          ],
        ],
      ),
      onPanUpdate: (d) => setState(
        () => points.add([
          d.localPosition.dx / box.maxWidth,
          d.localPosition.dy / box.maxHeight,
        ]),
      ),
      onPanEnd: (_) async {
        final saved = List<List<double>>.from(points);
        setState(() => points = []);
        await widget.onStroke(saved);
      },
      child: CustomPaint(
        painter: InkPainter([
          ...widget.strokes.map(
            (s) => (s['points'] as List)
                .map(
                  (p) => List<double>.from(
                    (p as List).map((n) => (n as num).toDouble()),
                  ),
                )
                .toList(),
          ),
          points,
        ]),
        size: Size.infinite,
      ),
    ),
  );
}

class InkPainter extends CustomPainter {
  final List<List<List<double>>> strokes;
  InkPainter(this.strokes);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xffb85839)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final stroke in strokes) {
      if (stroke.isEmpty) continue;
      final path = Path()
        ..moveTo(stroke.first[0] * size.width, stroke.first[1] * size.height);
      for (final p in stroke.skip(1)) {
        path.lineTo(p[0] * size.width, p[1] * size.height);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(InkPainter old) => true;
}

class ComicReader extends StatefulWidget {
  final Book book;
  final ReaderRepository repo;
  const ComicReader({super.key, required this.book, required this.repo});
  @override
  State<ComicReader> createState() => _ComicReaderState();
}

class _ComicReaderState extends State<ComicReader> {
  late final PageController controller;
  late int page;
  @override
  void initState() {
    super.initState();
    page = widget.book.chapter;
    controller = PageController(initialPage: page);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(title: Text(widget.book.title)),
    body: PageView.builder(
      controller: controller,
      itemCount: widget.book.chapters.length,
      onPageChanged: (n) {
        setState(() => page = n);
        widget.book.chapter = n;
        widget.book.offset = widget.book.chapters[n].text.length;
        widget.book.lastRead = DateTime.now().millisecondsSinceEpoch;
        unawaited(widget.repo.saveProgress(widget.book));
      },
      itemBuilder: (c, i) => InteractiveViewer(
        minScale: .5,
        maxScale: 5,
        child: Center(
          child: Image.memory(
            base64Decode(widget.book.chapters[i].images.first),
            fit: BoxFit.contain,
          ),
        ),
      ),
    ),
    bottomNavigationBar: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Text(
          '${page + 1} / ${widget.book.chapters.length} 页 · 双指缩放，左右翻页',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white),
        ),
      ),
    ),
  );
}
