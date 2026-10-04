import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'importer.dart';
import 'models.dart';
import 'reader.dart';
import 'repository.dart';

const ink = Color(0xff263b32);
const sage = Color(0xff58735f);
const paper = Color(0xfff7f6f1);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
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
  Widget build(BuildContext context) => MaterialApp(
    title: '书叶',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: sage, surface: paper),
      scaffoldBackgroundColor: paper,
      appBarTheme: const AppBarTheme(
        backgroundColor: paper,
        foregroundColor: ink,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: const CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    ),
    home: LibraryHome(repository: repository),
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
            child: Icon(
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
        child: book.cover == null
            ? fallback()
            : Image.memory(
                base64Decode(book.cover!),
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
  List<Book> books = [];
  List<Note> notes = [];
  ReaderSettings settings = ReaderSettings();
  Map<String, int> stats = {};
  int tab = 0, filter = 0;
  bool loading = true, busy = false, grid = true;
  String query = '';
  ReaderRepository get repo => widget.repository;
  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    try {
      final b = await repo.books();
      final n = await repo.notes();
      final s = await repo.settings();
      final t = await repo.statistics();
      if (mounted) {
        setState(() {
          books = b;
          notes = n;
          settings = s;
          stats = t;
          loading = false;
        });
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
      allowedExtensions: ['txt', 'epub'],
      allowMultiple: true,
      withData: false,
    );
    if (result == null) return;
    var added = 0, duplicates = 0;
    final errors = <String>[];
    for (final file in result.files) {
      try {
        if (file.size > maxImportBytes || file.path == null) {
          throw const FormatException('文件过大或无法访问');
        }
        final bytes = await File(file.path!).readAsBytes();
        final book = await compute(parseBook, {
          'bytes': bytes,
          'name': file.name,
          'pattern': settings.chapterPattern,
        });
        if (await repo.addBook(book)) {
          added++;
        } else {
          duplicates++;
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
          title: const Text('部分文件未导入'),
          content: SingleChildScrollView(child: Text(errors.join('\n\n'))),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    }
  });
  Future<void> openBook(Book book, [Note? note]) async {
    if (note != null) {
      book.chapter = note.chapter;
      book.offset = note.offset;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ReaderScreen(book: book, repository: repo, settings: settings),
      ),
    );
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
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('继续'),
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
          title: const Text('分章与净化规则'),
          content: SizedBox(
            width: 450,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '分章规则作用于之后导入的 TXT。净化规则只隐藏匹配的整行，原文会保留。',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: chapter,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'TXT 分章正则'),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: purify,
                    minLines: 3,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      labelText: '净化规则 · 每行一条',
                      hintText: '关注公众号\n本书首发',
                    ),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        error!,
                        style: const TextStyle(color: Colors.red),
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
              child: const Text('恢复默认'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
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
              child: const Text('保存'),
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
      title: Row(
        children: [
          const Icon(Icons.eco_outlined, color: sage),
          const SizedBox(width: 8),
          Text(
            ['书叶', '我的摘录', '阅读足迹', '设置'][tab],
            style: const TextStyle(
              letterSpacing: 2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      actions: tab == 0
          ? [
              IconButton(
                tooltip: grid ? '列表视图' : '网格视图',
                onPressed: () => setState(() => grid = !grid),
                icon: Icon(
                  grid ? Icons.view_list_outlined : Icons.grid_view_outlined,
                ),
              ),
              IconButton(
                tooltip: '导入书籍',
                onPressed: busy ? null : importBooks,
                icon: const Icon(Icons.add),
              ),
            ]
          : tab == 1
          ? [
              IconButton(
                tooltip: '导出 Markdown 笔记',
                onPressed: busy ? null : () => exportData(markdown: true),
                icon: const Icon(Icons.ios_share_outlined),
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
                child: [library, notebook, statistics, preferences][tab](),
              ),
            ],
          ),
    bottomNavigationBar: NavigationBar(
      backgroundColor: Colors.white,
      selectedIndex: tab,
      onDestinationSelected: (i) => setState(() => tab = i),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.auto_stories_outlined),
          selectedIcon: Icon(Icons.auto_stories),
          label: '书架',
        ),
        NavigationDestination(
          icon: Icon(Icons.bookmarks_outlined),
          selectedIcon: Icon(Icons.bookmarks),
          label: '笔记',
        ),
        NavigationDestination(
          icon: Icon(Icons.bar_chart_outlined),
          selectedIcon: Icon(Icons.bar_chart),
          label: '统计',
        ),
        NavigationDestination(icon: Icon(Icons.tune), label: '设置'),
      ],
    ),
  );
  Widget library() {
    final filtered = books
        .where(
          (b) =>
              (b.title.toLowerCase().contains(query.toLowerCase()) ||
                  b.author.toLowerCase().contains(query.toLowerCase())) &&
              (filter == 0 ||
                  (filter == 1 && b.lastRead > 0 && b.progress < .99) ||
                  (filter == 2 && b.progress >= .99)),
        )
        .toList();
    final recent = books.where((b) => b.lastRead > 0).firstOrNull;
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '给自己，一页安静。',
                  style: TextStyle(
                    fontSize: 27,
                    fontFamily: 'serif',
                    color: ink,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${books.length} 本藏书 · 文字留在你的设备里',
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
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
                          color: const Color(0xffe7ece3),
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
                                  const Text(
                                    '继续上次的故事',
                                    style: TextStyle(fontSize: 11, color: sage),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    recent.title,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '${recent.chapters[recent.chapter].title} · ${(recent.progress * 100).round()}%',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.black54,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.arrow_forward_rounded,
                              color: sage,
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
                    prefixIcon: Icon(Icons.search, size: 21),
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
        else if (grid)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 30),
            sliver: SliverLayoutBuilder(
              builder: (ctx, c) {
                final count = c.crossAxisExtent > 650
                    ? 4
                    : c.crossAxisExtent > 450
                    ? 3
                    : 2;
                return SliverGrid.builder(
                  itemCount: filtered.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: count,
                    mainAxisSpacing: 22,
                    crossAxisSpacing: 22,
                    mainAxisExtent: 290,
                  ),
                  itemBuilder: (_, i) {
                    final b = filtered[i];
                    return InkWell(
                      onTap: () => openBook(b),
                      onLongPress: () => deleteBook(b),
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
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 5),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  b.author,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.black54,
                                  ),
                                ),
                              ),
                              Text(
                                b.lastRead > 0
                                    ? '${(b.progress * 100).round()}%'
                                    : b.format,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: sage,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 7),
                          LinearProgressIndicator(
                            value: b.progress,
                            minHeight: 2,
                            backgroundColor: const Color(0xffe4e5dc),
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
                        tooltip: '移除书籍',
                        onPressed: () => deleteBook(b),
                        icon: const Icon(Icons.more_horiz),
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

  Widget notebook() => notes.isEmpty
      ? empty(Icons.bookmark_border, '把心动的句子留下来', '阅读时长按选择正文，点击摘录按钮保存。')
      : ListView.separated(
          padding: const EdgeInsets.all(22),
          itemCount: notes.length,
          separatorBuilder: (_, _) => const SizedBox(height: 14),
          itemBuilder: (_, i) {
            final n = notes[i];
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
                              style: const TextStyle(fontSize: 12, color: sage),
                            ),
                          ),
                          IconButton(
                            tooltip: '删除笔记',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => operation(() async {
                              if (await confirm('删除这条笔记？', '删除后不能撤销。')) {
                                await repo.deleteNote(n.id);
                                await reload();
                              }
                            }),
                            icon: const Icon(Icons.close, size: 16),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        n.quote,
                        maxLines: 8,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
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
                            style: const TextStyle(
                              color: Colors.black54,
                              height: 1.6,
                            ),
                          ),
                        ),
                      const SizedBox(height: 15),
                      Text(
                        '${b?.chapters[n.chapter].title ?? ''} · ${DateTime.fromMillisecondsSinceEpoch(n.created).toIso8601String().substring(0, 10)}',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.black45,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
  Widget statistics() {
    final today = DateTime.now();
    final days = List.generate(
      28,
      (i) => DateTime(
        today.year,
        today.month,
        today.day,
      ).subtract(Duration(days: 27 - i)),
    );
    String key(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final total = stats.values.fold<int>(0, (n, s) => n + s);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          '每一页，都算数。',
          style: TextStyle(fontSize: 27, fontFamily: 'serif', color: ink),
        ),
        const SizedBox(height: 24),
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
            Expanded(child: metric('阅读天数', '${stats.length}', '天')),
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
                const Text(
                  '最近 28 天',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 18),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 7,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  children: days.map((d) {
                    final seconds = stats[key(d)] ?? 0;
                    return Tooltip(
                      message: '${key(d)} · ${seconds ~/ 60} 分钟',
                      child: Container(
                        decoration: BoxDecoration(
                          color: seconds == 0
                              ? const Color(0xffedf0e9)
                              : sage.withValues(
                                  alpha: (.25 + seconds / 1800).clamp(.25, 1),
                                ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Center(
                          child: Text(
                            '${d.day}',
                            style: TextStyle(
                              fontSize: 11,
                              color: seconds > 1200 ? Colors.white : ink,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                const Text(
                  '颜色越深，阅读时间越长。',
                  style: TextStyle(fontSize: 11, color: Colors.black54),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          '只统计停留在阅读页的前台时间，短于 5 秒的片段不计入。统计在退出阅读页或进入后台后更新。删除书籍会移除对应记录。',
          style: TextStyle(fontSize: 12, color: Colors.black54, height: 1.8),
        ),
      ],
    );
  }

  Widget preferences() => ListView(
    padding: const EdgeInsets.all(22),
    children: [
      Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xffe7ece3),
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.eco_outlined, size: 32, color: sage),
            SizedBox(height: 10),
            Text(
              '书叶 SHUYE',
              style: TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.w600,
                letterSpacing: 2,
              ),
            ),
            SizedBox(height: 8),
            Text(
              '一本书，一段属于自己的时间。\n本地优先 · 无账号 · 无广告',
              style: TextStyle(fontSize: 12, height: 1.8, color: sage),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      const Text('阅读偏好', style: TextStyle(fontSize: 12, color: sage)),
      const SizedBox(height: 10),
      Card(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: const Text('字体与纸色'),
              subtitle: const Text('字号、行距、字体、中西文间距'),
              trailing: const Icon(Icons.chevron_right),
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
              leading: const Icon(Icons.filter_alt_outlined),
              title: const Text('分章与净化规则'),
              subtitle: const Text('识别章节，隐藏正文中的广告行'),
              trailing: const Icon(Icons.chevron_right),
              onTap: editRules,
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      const Text('你的数据', style: TextStyle(fontSize: 12, color: sage)),
      const SizedBox(height: 10),
      Card(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.save_alt),
              title: const Text('导出完整备份'),
              subtitle: const Text('书籍、进度、笔记、设置和统计 · JSON'),
              onTap: busy ? null : () => exportData(),
            ),
            ListTile(
              leading: const Icon(Icons.restore),
              title: const Text('从备份恢复'),
              subtitle: const Text('替换当前书库，请先保存现有数据'),
              onTap: busy ? null : restore,
            ),
            ListTile(
              leading: const Icon(Icons.ios_share),
              title: const Text('导出全部笔记'),
              subtitle: const Text('Markdown 格式，可在笔记工具中打开'),
              onTap: busy ? null : () => exportData(markdown: true),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      Card(
        child: ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('关于书叶 0.1.0'),
          subtitle: const Text('独立实现 · 非 Reeden 官方产品'),
          onTap: () => showAboutDialog(
            context: context,
            applicationName: '书叶',
            applicationVersion: '0.1.0',
            applicationIcon: const Icon(
              Icons.eco_outlined,
              size: 40,
              color: sage,
            ),
            children: const [
              Text(
                '参考提供的阅读器分析报告，使用原创代码实现。示例文章为项目原创。\n\n支持 TXT 与文字 EPUB。暂不支持 PDF、AI、网盘同步、插图排版和仿真卷页。\n\n正文与笔记仅保存在应用内。卸载应用或清除应用数据会丢失本地书库，请定期导出备份。导出的备份未加密，请妥善保管。',
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 22),
      const Text(
        '书籍不会自动上传。导出的备份包含正文和笔记，请保存在可信位置。',
        style: TextStyle(fontSize: 12, height: 1.8, color: Colors.black54),
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
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 12),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: const TextStyle(
                    fontSize: 32,
                    color: ink,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                TextSpan(
                  text: ' $unit',
                  style: const TextStyle(fontSize: 12, color: sage),
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
          Icon(icon, size: 52, color: sage.withValues(alpha: .5)),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, color: ink),
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.black54,
              height: 1.7,
            ),
          ),
        ],
      ),
    ),
  );
}
