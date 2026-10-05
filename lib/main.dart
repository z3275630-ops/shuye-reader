import 'form_field.dart';
import 'app_icons.dart';

import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'importer.dart';
import 'models.dart';
import 'reader.dart';
import 'repository.dart';
import 'document_reader.dart';
import 'services.dart';
import 'workbench.dart';
import 'shelf_layouts.dart';
import 'privacy.dart';
import 'typography.dart';
import 'appearance.dart';
import 'branding.dart';
import 'home_dashboard.dart';
import 'statistics_period.dart';
import 'reading_heatmap.dart';
import 'library_collections.dart';

const ink = Color(0xff263b32);
const sage = Color(0xff58735f);
const paper = Color(0xfff7f6f1);

List<Map<String, dynamic>> decodeArchive(Uint8List bytes) => [
  for (final f in checkedZip(bytes))
    if (f.isFile &&
        RegExp(
          r'\.(txt|epub|pdf|md|markdown|html?|docx|rtf|mobi|azw3?|cbz)$',
          caseSensitive: false,
        ).hasMatch(f.name))
      if (f.size > maxImportBytes)
        {'name': f.name, 'error': '文件超过 20 MB'}
      else
        {'name': f.name, 'bytes': Uint8List.fromList(f.content)},
];

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      '书叶',
    ], await rootBundle.loadString('LICENSE'));
  });
  try {
    await ChineseConverter.load();
    if (Platform.isAndroid) {
      await JustAudioBackground.init(
        androidNotificationChannelId: 'dev.shuye.audio',
        androidNotificationChannelName: '书叶有声书',
        androidNotificationOngoing: true,
      );
    }
    runApp(ShuyeApp(repository: await ReaderRepository.open()));
  } catch (e) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Text('无法打开本地书库。请保留应用数据并重试。\n\n$e'),
            ),
          ),
        ),
      ),
    );
  }
}

class ShuyeApp extends StatelessWidget {
  final ReaderRepository repository;
  const ShuyeApp({super.key, required this.repository});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AppAppearance>(
    valueListenable: appAppearance,
    builder: (context, appearance, _) => MaterialApp(
      title: '书叶',
      debugShowCheckedModeBanner: false,
      theme: applicationTheme(Brightness.light),
      darkTheme: applicationTheme(Brightness.dark),
      themeMode: appearance.themeMode,
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(
          textScaler: TextScaler.linear(
            MediaQuery.textScalerOf(c).scale(1) * appearance.scale,
          ),
        ),
        child: PrivacyGate(repo: repository, child: child!),
      ),
      home: LibraryHome(repository: repository),
    ),
  );
}

class BookCover extends StatelessWidget {
  final Book book;
  final double? width, height;
  const BookCover(this.book, {super.key, this.width, this.height});
  static const colors = [
    Color(0xff617561),
    Color(0xffab755c),
    Color(0xff556b7d),
    Color(0xff89755a),
    Color(0xff7c6674),
  ];
  @override
  Widget build(BuildContext context) {
    final color =
        colors[book.id.codeUnits.fold<int>(0, (a, b) => a + b) % colors.length];
    Widget artwork() => DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, Color.lerp(color, Colors.black, .22)!],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 9,
            top: 0,
            bottom: 0,
            child: Container(width: 1, color: Colors.white24),
          ),
          Positioned(
            right: -18,
            bottom: -28,
            child: ShuyeIcon(
              Icons.eco_outlined,
              size: 120,
              color: Colors.white.withValues(alpha: .12),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(23, 24, 16, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'SHUYE / READING',
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 8,
                    letterSpacing: 1,
                  ),
                ),
                const Spacer(),
                Text(
                  book.title,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    height: 1.4,
                    fontFamily: 'serif',
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 12),
                Container(width: 24, height: 2, color: Colors.white54),
                const SizedBox(height: 10),
                Text(
                  book.author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 9),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    Widget fallback() => FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(width: 160, height: 230, child: artwork()),
    );
    final cover =
        book.cover ??
        {
          'shuye-original-1': 'asset:assets/art/mountain.webp',
          'shuye-original-2': 'asset:assets/art/poetry.webp',
          'shuye-original-3': 'asset:assets/art/notebook.webp',
        }[book.id] ??
        'asset:${originalCovers[book.id.codeUnits.fold<int>(0, (a, b) => a + b) % originalCovers.length]}';
    Widget illustrated() => Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          cover.substring(6),
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => fallback(),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withValues(alpha: .35),
                Colors.transparent,
                Colors.black.withValues(alpha: .55),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                book.title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'serif',
                  fontSize: 19,
                  height: 1.4,
                  color: ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                book.author,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10, color: Colors.white),
              ),
            ],
          ),
        ),
      ],
    );
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: .18),
            blurRadius: 14,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: cover.startsWith('asset:')
            ? FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(width: 160, height: 230, child: illustrated()),
              )
            : Image.memory(
                base64Decode(cover),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback(),
              ),
      ),
    );
  }
}

class LibraryHome extends StatefulWidget {
  final ReaderRepository repository;
  const LibraryHome({super.key, required this.repository});
  @override
  State<LibraryHome> createState() => _LibraryHomeState();
}

class _LibraryHomeState extends State<LibraryHome> {
  StreamSubscription<MethodCall>? deviceEvents;
  bool initialLinkRead = false;
  List<Book> books = [];
  List<Note> notes = [];
  ReaderSettings settings = ReaderSettings();
  Map<String, int> stats = {};
  Map<int, int> hourlyStats = {};
  int tab = 4, filter = 0;
  bool loading = true, busy = false, grid = true;
  String query = '';
  String noteQuery = '';
  ReaderRepository get repo => widget.repository;
  @override
  void initState() {
    super.initState();
    DeviceReader.initialize();
    deviceEvents = DeviceReader.events.stream.listen((call) {
      if (call.method == 'link') {
        unawaited(handleLink(call.arguments as String?));
      }
    });
    reload();
  }

  @override
  void dispose() {
    unawaited(deviceEvents?.cancel());
    super.dispose();
  }

  Future<void> handleLink(String? value) async {
    if (value == null || !mounted) return;
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'shuye') return;
    if (uri.host == 'book' && uri.pathSegments.isNotEmpty) {
      final b = books.where((b) => b.id == uri.pathSegments.first).firstOrNull;
      if (b != null) await openBook(b);
    }
    if (uri.host == 'library' && mounted) setState(() => tab = 0);
  }

  Future<void> reload() async {
    try {
      final b = await repo.books(summaries: true);
      final n = await repo.notes();
      final s = await repo.settings();
      final t = await repo.statistics();
      final hours = await repo.hourlyStatistics();
      if (mounted) {
        setState(() {
          books = b;
          notes = n;
          settings = s;
          appAppearance.value = AppAppearance.fromSettings(s);
          privacyEnabled.value = s.flag('privacy.lock');
          stats = t;
          hourlyStats = hours;
          loading = false;
          grid = settings.value('bookshelf.layout', 'grid') == 'grid';
        });
        for (final font in await repo.entries('fonts')) {
          try {
            final loader = FontLoader(font['name'] as String)
              ..addFont(
                Future.value(
                  ByteData.sublistView(base64Decode(font['data'] as String)),
                ),
              );
            await loader.load();
          } catch (_) {
            /* The original font may be invalid on this device. */
          }
        }
        await updateWidgets();
        if (!initialLinkRead) {
          initialLinkRead = true;
          await handleLink(await DeviceReader.call<String>('initialLink'));
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => loading = false);
        message('读取失败：$e');
      }
    }
  }

  void message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> operation(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } catch (e) {
      message('操作未完成：$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> importBooks() => operation(() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'txt',
        'epub',
        'pdf',
        'md',
        'markdown',
        'html',
        'htm',
        'docx',
        'rtf',
        'mobi',
        'azw',
        'azw3',
        'cbz',
        'zip',
      ],
      allowMultiple: true,
      withData: false,
    );
    if (result == null) return;
    var added = 0, duplicates = 0;
    final errors = <String>[];
    for (final file in result.files) {
      try {
        final archiveFile = file.name.toLowerCase().endsWith('.zip');
        if (file.size > maxImportBytes || file.path == null) {
          throw const FormatException('文件过大或无法访问');
        }
        final bytes = await File(file.path!).readAsBytes();
        final inputs = <Map<String, dynamic>>[];
        if (archiveFile) {
          final archive = await compute(decodeArchive, bytes);
          inputs.addAll(archive);
        } else {
          inputs.add({'name': file.name, 'bytes': bytes});
        }
        if (inputs.isEmpty) {
          throw const FormatException('压缩包中没有支持的书籍文件');
        }
        for (final input in inputs) {
          try {
            if (input['error'] != null) {
              throw FormatException(input['error'] as String);
            }
            final book = await compute(parseBook, {
              ...input,
              'pattern': settings.chapterPattern,
            });
            if (await repo.addBook(book)) {
              added++;
            } else {
              duplicates++;
            }
          } catch (e) {
            errors.add('${input['name']}：$e');
          }
        }
      } catch (e) {
        errors.add('${file.name}：$e');
      }
    }
    await reload();
    message('已导入 $added 本${duplicates > 0 ? '，跳过 $duplicates 本重复书籍' : ''}');
    if (errors.isNotEmpty && mounted) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('部分文件未导入'),
          content: SingleChildScrollView(child: Text(errors.join('\n\n'))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('知道了')),
          ],
        ),
      );
    }
  });
  Future<void> openBook(Book book, [Note? note]) async {
    book = await repo.book(book.id);
    if (!mounted) return;
    if (note != null) {
      book.chapter = note.chapter;
      book.offset = note.offset;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => book.format == 'PDF'
            ? DocumentReader(book: book, repo: repo, settings: settings)
            : book.format == 'CBZ'
            ? ComicReader(book: book, repo: repo)
            : ReaderScreen(book: book, repository: repo, settings: settings),
      ),
    );
    await reload();
  }

  Future<void> updateWidgets() async {
    if (settings.flag('privacy.lock')) {
      await DeviceReader.call('widgets', {
        for (final name in [
          'shelf',
          'current',
          'stats',
          'weekly',
          'heatmap',
          'quote',
          'lists',
        ])
          name: '解锁书叶后查看',
        'link': 'shuye://library',
      });
      return;
    }
    final recent = books.where((b) => b.lastRead > 0).firstOrNull;
    final now = DateTime.now();
    var weekly = 0;
    final marks = <String>[];
    for (var i = 27; i >= 0; i--) {
      final day = dayKey(DateTime(now.year, now.month, now.day - i));
      final seconds = stats[day] ?? 0;
      if (i < 7) weekly += seconds;
      marks.add(seconds > 0 ? '■' : '□');
    }
    await DeviceReader.call('widgets', {
      'shelf': books.take(5).map((b) => b.title).join('\n'),
      'current': recent == null
          ? '还没有开始阅读'
          : '${recent.title}\n已读 ${(recent.progress * 100).round()}%',
      'stats':
          '${books.length} 本藏书\n累计阅读 ${stats.values.fold<int>(0, (a, b) => a + b) ~/ 60} 分钟',
      'weekly': '近 7 天阅读 ${weekly ~/ 60} 分钟',
      'heatmap': [
        for (var i = 0; i < 4; i++) marks.sublist(i * 7, i * 7 + 7).join(' '),
      ].join('\n'),
      'quote': notes.firstOrNull?.quote ?? '开始阅读，记下让你心动的文字。',
      'lists': books
          .map((b) => b.metadata['list'] as String? ?? '')
          .where((s) => s.isNotEmpty)
          .toSet()
          .join('\n'),
      'link': recent == null ? 'shuye://library' : 'shuye://book/${recent.id}',
    });
  }

  Future<void> bookMenu(Book book) async {
    book = await repo.book(book.id);
    if (!mounted) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(book.title)),
            ListTile(
              leading: ShuyeIcon(Icons.edit_outlined),
              title: Text('书籍资料与管理'),
              onTap: () => Navigator.pop(c, 'edit'),
            ),
            ListTile(
              leading: ShuyeIcon(Icons.delete_outline),
              title: Text('移除书籍'),
              onTap: () => Navigator.pop(c, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'edit') {
      await showBookDetails(context, book, repo, reload);
    } else if (action == 'delete') {
      await deleteBook(book);
    }
  }

  Future<void> shelfSettings() async {
    await configureShelf(context, settings, () => repo.saveSettings(settings));
    await reload();
  }

  Future<bool> confirm(String title, String content) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('继续'),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> deleteBook(Book book) => operation(() async {
    if (!await confirm(
      '移除《${book.title}》？',
      '应用内的正文、阅读进度、笔记和该书统计将一并移除。原始文件不会改变。建议先导出备份。',
    )) {
      return;
    }
    await repo.deleteBook(book.id);
    await reload();
  });
  Future<void> exportData({bool markdown = false}) => operation(() async {
    String text;
    if (markdown) {
      text =
          '# 书叶摘录\n\n${notes.map((n) {
            final b = books.where((b) => b.id == n.bookId).firstOrNull;
            return '## ${b?.title ?? '书籍'} · ${b?.chapters[n.chapter].title ?? ''}\n\n> ${n.quote.replaceAll('\n', '\n> ')}\n\n${n.comment}\n\n---\n';
          }).join('\n')}';
    } else {
      text = await repo.backup();
    }
    final date = DateTime.now().toIso8601String().substring(0, 10);
    final path = await FilePicker.platform.saveFile(
      dialogTitle: markdown ? '导出笔记' : '保存完整备份',
      fileName: 'shuye-$date.${markdown ? 'md' : 'json'}',
      type: FileType.custom,
      allowedExtensions: [markdown ? 'md' : 'json'],
      bytes: Uint8List.fromList(utf8.encode(text)),
    );
    if (path != null) message('已导出${markdown ? '笔记' : '完整备份'}');
  });
  Future<void> restore() => operation(() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result == null) return;
    final file = result.files.single;
    if (file.path == null || file.size > 80 * 1024 * 1024) {
      throw const FormatException('备份过大或无法读取');
    }
    final data = await File(file.path!).readAsString();
    if (!await confirm(
      '恢复书叶备份？',
      '恢复会替换当前全部书籍、进度、笔记和设置。请先保存当前备份。无效备份不会修改现有数据。',
    )) {
      return;
    }
    await repo.restore(data);
    await reload();
    message('备份恢复完成');
  });
  Future<void> editRules() async {
    final chapter = TextEditingController(text: settings.chapterPattern);
    final purify = TextEditingController(text: settings.purifyLines);
    String? error;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: Text('分章与净化规则'),
          content: SizedBox(
            width: 450,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '分章规则作用于之后导入的 TXT。净化规则只隐藏匹配的整行，原文会保留。',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 18),
                  LabeledField(
                    label: 'TXT 分章正则',
                    child: TextField(
                      controller: chapter,
                      maxLines: 3,
                      decoration: const InputDecoration(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  LabeledField(
                    label: '净化规则 · 每行一条',
                    child: TextField(
                      controller: purify,
                      minLines: 3,
                      maxLines: 6,
                      decoration: const InputDecoration(
                        hintText: '关注公众号\n本书首发',
                      ),
                    ),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(ctx).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                chapter.text = defaultChapterPattern;
                purify.clear();
              },
              child: Text('恢复默认'),
            ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('取消')),
            FilledButton(
              onPressed: () async {
                try {
                  validateRules(chapter.text.trim(), purify.text);
                  settings.chapterPattern = chapter.text.trim();
                  settings.purifyLines = purify.text;
                  await repo.saveSettings(settings);
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {
                  update(() => error = '$e');
                }
              },
              child: Text('保存'),
            ),
          ],
        ),
      ),
    );
    chapter.dispose();
    purify.dispose();
    await reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      centerTitle: tab == 2,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ShuyeIcon(
            Icons.eco_outlined,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Text(
            ['书架', '我的摘录', '阅读足迹', '设置', '书叶'][tab],
            style: TextStyle(letterSpacing: 2, fontWeight: FontWeight.w600),
          ),
        ],
      ),
      actions: tab == 4
          ? [
              IconButton(
                tooltip: '调整首页布局',
                onPressed: () async {
                  await configureHome(
                    context,
                    settings,
                    () => repo.saveSettings(settings),
                  );
                  await reload();
                },
                icon: ShuyeIcon(Icons.dashboard_customize_outlined),
              ),
              IconButton(
                tooltip: '导入书籍',
                onPressed: busy ? null : importBooks,
                icon: ShuyeIcon(Icons.add),
              ),
            ]
          : tab == 0
          ? [
              IconButton(
                tooltip: '整理书库',
                onPressed: openCollections,
                icon: ShuyeIcon(Icons.folder_outlined),
              ),
              PopupMenuButton<String>(
                tooltip: '书架选项',
                onSelected: (v) async {
                  if (v == 'layout') {
                    await shelfSettings();
                  } else {
                    setState(() => grid = !grid);
                    settings.extra['bookshelf.layout'] = grid ? 'grid' : 'list';
                    await repo.saveSettings(settings);
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'view',
                    child: Text(grid ? '切换列表视图' : '切换网格视图'),
                  ),
                  const PopupMenuItem(value: 'layout', child: Text('书架装修')),
                ],
              ),
              IconButton(
                tooltip: '导入书籍',
                onPressed: busy ? null : importBooks,
                icon: ShuyeIcon(Icons.add),
              ),
            ]
          : tab == 1
          ? [
              IconButton(
                tooltip: '导出 Markdown 笔记',
                onPressed: busy ? null : () => exportData(markdown: true),
                icon: ShuyeIcon(Icons.ios_share_outlined),
              ),
            ]
          : null,
    ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [
              if (busy) const LinearProgressIndicator(minHeight: 2),
              Expanded(
                child: [
                  library,
                  notebook,
                  statistics,
                  preferences,
                  dashboard,
                ][tab](),
              ),
            ],
          ),
    bottomNavigationBar: NavigationBar(
      backgroundColor: Theme.of(context).colorScheme.surface,
      selectedIndex: const [4, 0, 1, 2, 3].indexOf(tab),
      onDestinationSelected: (i) =>
          setState(() => tab = const [4, 0, 1, 2, 3][i]),
      destinations: const [
        NavigationDestination(
          icon: ShuyeIcon(Icons.home_outlined),
          selectedIcon: ShuyeIcon(Icons.home),
          label: '首页',
        ),
        NavigationDestination(
          icon: ShuyeIcon(Icons.auto_stories_outlined),
          selectedIcon: ShuyeIcon(Icons.auto_stories),
          label: '书架',
        ),
        NavigationDestination(
          icon: ShuyeIcon(Icons.bookmarks_outlined),
          selectedIcon: ShuyeIcon(Icons.bookmarks),
          label: '笔记',
        ),
        NavigationDestination(
          icon: ShuyeIcon(Icons.bar_chart_outlined),
          selectedIcon: ShuyeIcon(Icons.bar_chart),
          label: '统计',
        ),
        NavigationDestination(icon: ShuyeIcon(Icons.tune), label: '设置'),
      ],
    ),
  );
  Future<void> openTools() async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => WorkshopScreen(repo: repo, settings: settings),
      ),
    );
    await reload();
  }

  Future<void> openCollections() async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => LibraryCollections(
          repo: repo,
          open: openBook,
          cover: (b) => BookCover(b),
        ),
      ),
    );
    await reload();
  }

  Future<void> editDailyGoal() => operation(() async {
    final data = await editFields(context, '每日阅读目标', {
      '分钟': '${settings.number('stats.goalMinutes', 20).round()}',
    });
    if (data == null) return;
    settings.extra['stats.goalMinutes'] = (int.tryParse(data['分钟']!) ?? 20)
        .clamp(5, 240);
    await repo.saveSettings(settings);
    await reload();
  });
  Widget dashboard() => HomeDashboard(
    books: books,
    stats: stats,
    notes: notes.length,
    settings: settings,
    cover: (b) => BookCover(b),
    open: openBook,
    shelf: () => setState(() => tab = 0),
    tools: openTools,
    statistics: () => setState(() => tab = 2),
    goal: editDailyGoal,
  );
  Widget library() {
    final filtered = books
        .where(
          (b) =>
              (b.title.toLowerCase().contains(query.toLowerCase()) ||
                  b.author.toLowerCase().contains(query.toLowerCase()) ||
                  ['category', 'tags', 'list', 'review']
                      .map((k) => b.metadata[k] ?? '')
                      .any(
                        (v) => v.toString().toLowerCase().contains(
                          query.toLowerCase(),
                        ),
                      )) &&
              (filter == 0 ||
                  (filter == 1 && b.lastRead > 0 && b.progress < .99) ||
                  (filter == 2 && b.progress >= .99)),
        )
        .toList();
    switch (settings.value('bookshelf.sort', 'recent')) {
      case 'added':
        filtered.sort((a, b) => b.added.compareTo(a.added));
      case 'title':
        filtered.sort((a, b) => a.title.compareTo(b.title));
      case 'author':
        filtered.sort((a, b) => a.author.compareTo(b.author));
      case 'progress':
        filtered.sort((a, b) => b.progress.compareTo(a.progress));
      case 'rating':
        filtered.sort(
          (a, b) => (b.metadata['rating'] as num? ?? 0).compareTo(
            a.metadata['rating'] as num? ?? 0,
          ),
        );
    }
    final recent = books.where((b) => b.lastRead > 0).firstOrNull;
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (settings.flag('bookshelf.banner', true))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: const ShuyeCover(),
                  ),
                Text(
                  '给自己，一页安静。',
                  style: TextStyle(
                    fontSize: 27,
                    fontFamily: 'serif',
                    color: Theme.of(context).colorScheme.onSurface,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${books.length} 本藏书 · 文字留在你的设备里',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 24),
                if (recent != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 22),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () => openBook(recent),
                      child: Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Row(
                          children: [
                            BookCover(recent, width: 58, height: 82),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '继续上次的故事',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    recent.title,
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '${recent.chapters[recent.chapter].title} · ${(recent.progress * 100).round()}%',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            ShuyeIcon(
                              Icons.arrow_forward_rounded,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                TextField(
                  onChanged: (v) => setState(() => query = v),
                  decoration: const InputDecoration(
                    hintText: '找一本书，或一位作者',
                    prefixIcon: ShuyeIcon(Icons.search, size: 21),
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: List.generate(
                    3,
                    (i) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(['全部', '在读', '读完'][i]),
                        selected: filter == i,
                        showCheckmark: false,
                        onSelected: (_) => setState(() => filter = i),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
        if (filtered.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: empty(
              Icons.menu_book_outlined,
              books.isEmpty ? '书架等待你的第一本书' : '没有找到符合条件的书籍',
              books.isEmpty ? '点击右上角 +，导入 TXT 或 EPUB。' : '试试其他关键词或分类。',
            ),
          )
        else if (![
          'grid',
          'list',
        ].contains(settings.value('bookshelf.layout', 'grid')))
          SliverToBoxAdapter(
            child: AlternativeShelf(
              books: filtered,
              settings: settings,
              open: openBook,
              menu: bookMenu,
              cover: (b) => BookCover(b),
            ),
          )
        else if (grid)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 30),
            sliver: SliverLayoutBuilder(
              builder: (ctx, c) {
                final count = settings.number('bookshelf.columns', 0) > 0
                    ? settings
                          .number('bookshelf.columns', 2)
                          .round()
                          .clamp(1, 5)
                    : c.crossAxisExtent > 650
                    ? 4
                    : c.crossAxisExtent > 450
                    ? 3
                    : 2;
                return SliverGrid.builder(
                  itemCount: filtered.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: count,
                    mainAxisSpacing: settings.number('bookshelf.gap', 22),
                    crossAxisSpacing: settings.number('bookshelf.gap', 22),
                    mainAxisExtent: settings.number(
                      'bookshelf.cardHeight',
                      290,
                    ),
                  ),
                  itemBuilder: (_, i) {
                    final b = filtered[i];
                    return InkWell(
                      onTap: () => openBook(b),
                      onLongPress: () => bookMenu(b),
                      borderRadius: BorderRadius.circular(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: SizedBox(
                              width: double.infinity,
                              child: BookCover(b),
                            ),
                          ),
                          const SizedBox(height: 13),
                          Text(
                            b.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 5),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  b.author,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                ),
                              ),
                              Text(
                                b.lastRead > 0
                                    ? '${(b.progress * 100).round()}%'
                                    : b.format,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 7),
                          LinearProgressIndicator(
                            value: b.progress,
                            minHeight: 2,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverList.builder(
              itemCount: filtered.length,
              itemBuilder: (_, i) {
                final b = filtered[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(12),
                      leading: BookCover(b, width: 45, height: 65),
                      title: Text(b.title),
                      subtitle: Text(
                        '${b.author}\n${b.chapters.length} 章 · ${(b.progress * 100).round()}%',
                      ),
                      isThreeLine: true,
                      onTap: () => openBook(b),
                      trailing: IconButton(
                        tooltip: '书籍管理',
                        onPressed: () => bookMenu(b),
                        icon: ShuyeIcon(Icons.more_horiz),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget notebook() {
    final matching = notes
        .where(
          (n) =>
              noteQuery.isEmpty ||
              '${n.quote} ${n.comment} ${n.tags}'.toLowerCase().contains(
                noteQuery.toLowerCase(),
              ),
        )
        .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
          child: TextField(
            decoration: const InputDecoration(
              hintText: '搜索摘录、想法或标签',
              prefixIcon: ShuyeIcon(Icons.search),
            ),
            onChanged: (v) => setState(() => noteQuery = v),
          ),
        ),
        Expanded(
          child: matching.isEmpty
              ? empty(Icons.bookmark_border, '把心动的句子留下来', '阅读时长按选择正文，点击摘录按钮保存。')
              : ListView.separated(
                  padding: const EdgeInsets.all(22),
                  itemCount: matching.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 14),
                  itemBuilder: (_, i) {
                    final n = matching[i];
                    final b = books.where((b) => b.id == n.bookId).firstOrNull;
                    return Card(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: b == null ? null : () => openBook(b, n),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      b?.title ?? '书籍',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: '分享摘录卡片',
                                    onPressed: () => showShareCard(
                                      context,
                                      n.quote,
                                      b?.title ?? '书叶',
                                      settings: settings,
                                      saveSettings: () =>
                                          repo.saveSettings(settings),
                                    ),
                                    icon: ShuyeIcon(Icons.ios_share, size: 16),
                                  ),
                                  IconButton(
                                    tooltip: '编辑笔记',
                                    icon: ShuyeIcon(
                                      Icons.edit_outlined,
                                      size: 16,
                                    ),
                                    onPressed: () => operation(() async {
                                      final data = await editFields(
                                        context,
                                        '编辑笔记',
                                        {
                                          '摘录正文': n.quote,
                                          '想法说明': n.comment,
                                          '标签（逗号分隔）': n.tags,
                                        },
                                      );
                                      if (data == null) return;
                                      await repo.updateNote(
                                        Note(
                                          id: n.id,
                                          bookId: n.bookId,
                                          chapter: n.chapter,
                                          offset: n.offset,
                                          quote: data['摘录正文']!,
                                          comment: data['想法说明']!,
                                          tags: data['标签（逗号分隔）']!,
                                          created: n.created,
                                        ),
                                      );
                                      await reload();
                                    }),
                                  ),
                                  IconButton(
                                    tooltip: '删除笔记',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () => operation(() async {
                                      if (await confirm(
                                        '删除这条笔记？',
                                        '删除后不能撤销。',
                                      )) {
                                        await repo.deleteNote(n.id);
                                        await reload();
                                      }
                                    }),
                                    icon: ShuyeIcon(Icons.close, size: 16),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                n.quote,
                                maxLines: 8,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'serif',
                                  height: 1.8,
                                  fontSize: 16,
                                ),
                              ),
                              if (n.comment.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 14),
                                  child: Text(
                                    n.comment,
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                      height: 1.6,
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 15),
                              Text(
                                '${b?.chapters[n.chapter].title ?? ''} · ${DateTime.fromMillisecondsSinceEpoch(n.created).toIso8601String().substring(0, 10)}',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget statistics() {
    final today = DateTime.now();
    String key(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final total = stats.values.fold<int>(0, (n, s) => n + s);
    return ListView(
      key: const PageStorageKey('reading-statistics'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        ReadingHeatmap(stats: stats),
        const SizedBox(height: 18),
        PeriodStatistics(stats: stats),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(child: metric('累计阅读', '${total ~/ 60}', '分钟')),
            const SizedBox(width: 12),
            Expanded(
              child: metric('今天阅读', '${(stats[key(today)] ?? 0) ~/ 60}', '分钟'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: metric(
                '阅读天数',
                '${stats.values.where((v) => v > 0).length}',
                '天',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: metric('留下摘录', '${notes.length}', '条')),
          ],
        ),
        const SizedBox(height: 28),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '每日目标 ${settings.number('stats.goalMinutes', 20).round()} 分钟',
                        style: TextStyle(fontSize: 17),
                      ),
                    ),
                    IconButton(
                      tooltip: '设置每日目标',
                      onPressed: () => operation(() async {
                        final data = await editFields(context, '每日阅读目标', {
                          '分钟':
                              '${settings.number('stats.goalMinutes', 20).round()}',
                        });
                        if (data != null) {
                          settings.extra['stats.goalMinutes'] =
                              (int.tryParse(data['分钟']!) ?? 20).clamp(5, 240);
                          await repo.saveSettings(settings);
                          await reload();
                        }
                      }),
                      icon: ShuyeIcon(Icons.edit_outlined),
                    ),
                  ],
                ),
                LinearProgressIndicator(
                  value:
                      ((stats[key(today)] ?? 0) /
                              (settings
                                      .number('stats.goalMinutes', 20)
                                      .clamp(5, 240) *
                                  60))
                          .clamp(0, 1),
                ),
                const SizedBox(height: 16),
                Text('常读时段（本次升级后开始记录）'),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 5,
                  runSpacing: 8,
                  children: [
                    for (var h = 0; h < 24; h++)
                      Tooltip(
                        message: '$h 点：${(hourlyStats[h] ?? 0) ~/ 60} 分钟',
                        child: Container(
                          width: 28,
                          height: 34,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: (hourlyStats[h] ?? 0) > 0
                                ? Theme.of(context).colorScheme.primary
                                      .withValues(alpha: .6)
                                : Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text('$h', style: TextStyle(fontSize: 10)),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          '只统计停留在阅读页的前台时间，短于 5 秒的片段不计入。统计在退出阅读页或进入后台后更新。删除书籍会移除对应记录。',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            height: 1.8,
          ),
        ),
      ],
    );
  }

  Widget preferences() => ListView(
    padding: const EdgeInsets.all(22),
    children: [
      const ShuyeIdentityCard(),
      const SizedBox(height: 24),
      Text(
        '阅读偏好',
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
      const SizedBox(height: 10),
      Card(
        child: Column(
          children: [
            ListTile(
              leading: ShuyeIcon(Icons.palette_outlined),
              title: Text('字体与纸色'),
              subtitle: Text('字号、行距、字体、中西文间距'),
              trailing: ShuyeIcon(Icons.chevron_right),
              onTap: () async {
                await showReaderSettings(
                  context,
                  settings,
                  () => repo.saveSettings(settings),
                );
                await reload();
              },
            ),
            ListTile(
              leading: ShuyeIcon(Icons.filter_alt_outlined),
              title: Text('分章与净化规则'),
              subtitle: Text('识别章节，隐藏正文中的广告行'),
              trailing: ShuyeIcon(Icons.chevron_right),
              onTap: editRules,
            ),
            ListTile(
              leading: ShuyeIcon(Icons.handyman_outlined),
              title: Text('阅读工具箱'),
              subtitle: Text('AI、听书、识字、在线书库、字体和加密同步'),
              trailing: ShuyeIcon(Icons.chevron_right),
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        WorkshopScreen(repo: repo, settings: settings),
                  ),
                );
                await reload();
              },
            ),
            ListTile(
              leading: ShuyeIcon(Icons.dashboard_customize_outlined),
              title: Text('书架装修'),
              subtitle: Text('五种布局、列数、间距和置顶横幅'),
              onTap: shelfSettings,
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      Text(
        '你的数据',
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
      const SizedBox(height: 10),
      Card(
        child: Column(
          children: [
            ListTile(
              leading: ShuyeIcon(Icons.folder_outlined),
              title: Text('整理书库'),
              subtitle: Text('标签、分类、书单和作者'),
              trailing: ShuyeIcon(Icons.chevron_right),
              onTap: openCollections,
            ),
            ListTile(
              leading: ShuyeIcon(Icons.palette_outlined),
              title: Text('应用外观'),
              subtitle: Text('跟随系统、深浅色和界面文字大小'),
              trailing: ShuyeIcon(Icons.chevron_right),
              onTap: () async {
                await configureAppearance(
                  context,
                  settings,
                  () => repo.saveSettings(settings),
                );
                await reload();
              },
            ),
            ListTile(
              leading: ShuyeIcon(Icons.save_alt),
              title: Text('导出完整备份'),
              subtitle: Text('书籍、进度、笔记、设置和统计 · JSON'),
              onTap: busy ? null : () => exportData(),
            ),
            ListTile(
              leading: ShuyeIcon(Icons.restore),
              title: Text('从备份恢复'),
              subtitle: Text('替换当前书库，请先保存现有数据'),
              onTap: busy ? null : restore,
            ),
            ListTile(
              leading: ShuyeIcon(Icons.ios_share),
              title: Text('导出全部笔记'),
              subtitle: Text('Markdown 格式，可在笔记工具中打开'),
              onTap: busy ? null : () => exportData(markdown: true),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      Card(
        child: ListTile(
          leading: const ShuyeIcon(Icons.info_outline),
          title: const Text('关于书叶'),
          subtitle: const Text('版本 $shuyeVersion'),
          onTap: () => showShuyeAbout(context),
        ),
      ),
      const SizedBox(height: 22),
      Text(
        '书籍不会自动上传。导出的备份包含正文和笔记，请保存在可信位置。',
        style: TextStyle(
          fontSize: 12,
          height: 1.8,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ],
  );
  Widget metric(String label, String value, String unit) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: TextStyle(
                    fontSize: 32,
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                TextSpan(
                  text: ' $unit',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  Widget empty(IconData icon, String title, String subtitle) => Center(
    child: Padding(
      padding: const EdgeInsets.all(30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ShuyeIcon(
            icon,
            size: 52,
            color: Theme.of(context).colorScheme.primary.withValues(alpha: .5),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.7,
            ),
          ),
        ],
      ),
    ),
  );
}
