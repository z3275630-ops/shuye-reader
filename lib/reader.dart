import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'importer.dart';
import 'models.dart';
import 'repository.dart';

const readerSchemes = {
  'paper': [Color(0xfff4eddf), Color(0xff3f392e)],
  'white': [Color(0xfffafafa), Color(0xff303330)],
  'sage': [Color(0xffe4ebdf), Color(0xff344333)],
  'night': [Color(0xff202521), Color(0xffbcc4b7)],
};
const readerNames = {'paper': '暖纸', 'white': '纸白', 'sage': '青竹', 'night': '夜读'};

Future<void> showReaderSettings(
  BuildContext context,
  ReaderSettings s,
  Future<void> Function() save, {
  VoidCallback? changed,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, update) {
        void change(VoidCallback action) {
          update(action);
          changed?.call();
        }

        return SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '让文字，刚刚好。',
                    style: TextStyle(fontSize: 22, fontFamily: 'serif'),
                  ),
                  const SizedBox(height: 22),
                  Text('字号  ${s.fontSize.round()}'),
                  Slider(
                    value: s.fontSize,
                    min: 14,
                    max: 32,
                    divisions: 18,
                    onChanged: (v) => change(() => s.fontSize = v),
                  ),
                  Text('行距  ${s.lineHeight.toStringAsFixed(2)}'),
                  Slider(
                    value: s.lineHeight,
                    min: 1.3,
                    max: 2.4,
                    divisions: 22,
                    onChanged: (v) => change(() => s.lineHeight = v),
                  ),
                  Wrap(
                    spacing: 10,
                    children: readerSchemes.entries
                        .map(
                          (e) => ChoiceChip(
                            label: Text(readerNames[e.key]!),
                            selected: s.theme == e.key,
                            avatar: CircleAvatar(
                              backgroundColor: e.value[0],
                              radius: 8,
                            ),
                            onSelected: (_) => change(() => s.theme = e.key),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 16),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'serif', label: Text('衬线字体')),
                      ButtonSegment(value: 'sans', label: Text('无衬线字体')),
                    ],
                    selected: {s.font},
                    onSelectionChanged: (v) => change(() => s.font = v.first),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('中西文自动留空'),
                    subtitle: const Text('让中文与 English、数字之间更舒展'),
                    value: s.cjkSpacing,
                    onChanged: (v) => change(() => s.cjkSpacing = v),
                  ),
                  const Text(
                    '中文字体由设备提供，实际字形以手机为准。',
                    style: TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('开始阅读'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
  try {
    await save();
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('设置保存失败：$e')));
    }
  }
}

class PageSlice {
  final int start, end;
  const PageSlice(this.start, this.end);
}

// Layout uses actual font metrics, direction and accessibility text scaling.
// Every measurement is bounded to 5000 UTF-16 units for large TXT chapters.
List<PageSlice> paginate(
  String text,
  TextStyle style,
  double width,
  double height,
  TextScaler scaler,
) {
  if (text.isEmpty) return [const PageSlice(0, 0)];
  final pages = <PageSlice>[];
  var start = 0;
  bool fits(int end) {
    // A dangling UTF-16 high surrogate makes some engines report a one-line
    // paragraph. Measure complete surrogate pairs during binary search too.
    if (end < text.length &&
        text.codeUnitAt(end - 1) >= 0xd800 &&
        text.codeUnitAt(end - 1) <= 0xdbff) {
      end = end > start + 1 ? end - 1 : end + 1;
    }
    final painter = TextPainter(
      text: TextSpan(text: text.substring(start, end), style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    );
    painter.layout(maxWidth: width);
    final fits = painter.height <= height - 4;
    painter.dispose();
    return fits;
  }

  while (start < text.length) {
    var low = start + 1, high = math.min(text.length, start + 5000), end = low;
    while (low <= high) {
      final mid = (low + high) ~/ 2;
      if (fits(mid)) {
        end = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    if (end < text.length &&
        end > start + 1 &&
        text.codeUnitAt(end - 1) >= 0xd800 &&
        text.codeUnitAt(end - 1) <= 0xdbff) {
      end--;
    }
    if (end < text.length &&
        '，。！？；：、）】》”’'.contains(text[end]) &&
        end - start > 2) {
      end--;
    }
    if (end < text.length &&
        end > start + 1 &&
        text.codeUnitAt(end - 1) >= 0xd800 &&
        text.codeUnitAt(end - 1) <= 0xdbff) {
      end--;
    }
    pages.add(PageSlice(start, end));
    start = end;
  }
  return pages;
}

class ReaderScreen extends StatefulWidget {
  final Book book;
  final ReaderRepository repository;
  final ReaderSettings settings;
  const ReaderScreen({
    super.key,
    required this.book,
    required this.repository,
    required this.settings,
  });
  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen>
    with WidgetsBindingObserver {
  late int chapter;
  int page = 0, initialOffset = 0, seconds = 0;
  List<PageSlice> pages = [];
  String text = '', selected = '', layoutKey = '';
  List<int> sourceOffsets = [];
  Timer? timer;
  bool active = true, dialogOpen = false, saving = false;
  Book get book => widget.book;
  ReaderSettings get settings => widget.settings;
  ReaderRepository get repo => widget.repository;
  @override
  void initState() {
    super.initState();
    chapter = book.chapter;
    initialOffset = book.offset;
    book.lastRead = DateTime.now().millisecondsSinceEpoch;
    WidgetsBinding.instance.addObserver(this);
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (active && !dialogOpen) seconds++;
    });
    unawaited(persist());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    active = state == AppLifecycleState.resumed;
    if (!active) {
      unawaited(flushTime());
      unawaited(persist());
    }
  }

  Future<void> flushTime() async {
    final elapsed = seconds;
    seconds = 0;
    try {
      await repo.record(book.id, elapsed);
    } catch (e) {
      if (mounted) message('阅读时长保存失败：$e');
    }
  }

  Future<void> persist() async {
    try {
      await repo.saveProgress(book);
    } catch (e) {
      if (mounted) message('进度保存失败：$e');
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(flushTime());
    unawaited(persist());
    super.dispose();
  }

  void message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  void buildText() {
    // Map rendered positions back to original text, preserving anchors across
    // purification and automatic CJK/Latin spacing changes.
    final raw = book.chapters[chapter].text;
    final buffer = StringBuffer();
    sourceOffsets = [];
    var pos = 0;
    for (final line in raw.split('\n')) {
      final clean = cleanText(line, settings);
      if (clean.isNotEmpty || line.isEmpty) {
        var i = 0;
        for (var j = 0; j < clean.length; j++) {
          if (i < line.length && clean[j] == line[i]) {
            sourceOffsets.add(pos + i);
            i++;
          } else {
            sourceOffsets.add(pos + math.max(0, i - 1));
          }
          buffer.write(clean[j]);
        }
        if (pos + line.length < raw.length) {
          buffer.write('\n');
          sourceOffsets.add(pos + line.length);
        }
      }
      pos += line.length + 1;
    }
    text = buffer.toString();
    sourceOffsets.add(raw.length);
  }

  int sourceOffset(int rendered) =>
      sourceOffsets[rendered.clamp(0, sourceOffsets.length - 1)];
  void updateProgress() {
    book.chapter = chapter;
    initialOffset = sourceOffset(pages[page].start);
    book.offset = sourceOffset(
      page == pages.length - 1 ? pages[page].end : pages[page].start,
    );
    book.lastRead = DateTime.now().millisecondsSinceEpoch;
    unawaited(persist());
  }

  void turn(int delta) {
    if (pages.isEmpty) return;
    selected = '';
    if (page + delta >= 0 && page + delta < pages.length) {
      setState(() => page += delta);
      updateProgress();
    } else if (delta > 0 && chapter < book.chapters.length - 1) {
      jump(chapter + 1);
    } else if (delta < 0 && chapter > 0) {
      jump(chapter - 1, offset: book.chapters[chapter - 1].text.length);
    } else {
      if (delta > 0) updateProgress();
      message(delta > 0 ? '已到全书最后一页' : '已到全书第一页');
    }
  }

  void jump(int to, {int offset = 0}) {
    setState(() {
      chapter = to;
      initialOffset = offset;
      layoutKey = '';
      selected = '';
    });
    book.chapter = chapter;
    book.offset = offset;
    book.lastRead = DateTime.now().millisecondsSinceEpoch;
    unawaited(persist());
  }

  Future<void> outline() async {
    dialogOpen = true;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(ctx).height * .7,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        book.title,
                        style: const TextStyle(
                          fontSize: 21,
                          fontFamily: 'serif',
                        ),
                      ),
                    ),
                    Text(
                      '${book.chapters.length} 章',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: book.chapters.length,
                  itemBuilder: (_, i) => ListTile(
                    selected: i == chapter,
                    leading: Text(
                      '${i + 1}'.padLeft(2, '0'),
                      style: const TextStyle(fontSize: 12),
                    ),
                    title: Text(book.chapters[i].title),
                    trailing: i == chapter
                        ? const Icon(Icons.bookmark, size: 18)
                        : null,
                    onTap: () {
                      Navigator.pop(ctx);
                      jump(i);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    dialogOpen = false;
  }

  Future<void> search() async {
    dialogOpen = true;
    final controller = TextEditingController();
    var results = <({int chapter, int offset, String snippet})>[];
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(ctx).height * .75,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                0,
                20,
                MediaQuery.viewInsetsOf(ctx).bottom,
              ),
              child: Column(
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: '搜索整本书 · 至少 2 个字',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onSubmitted: (q) {
                      final found =
                          <({int chapter, int offset, String snippet})>[];
                      if (q.trim().length >= 2) {
                        final needle = q.trim().toLowerCase();
                        for (
                          var i = 0;
                          i < book.chapters.length && found.length < 100;
                          i++
                        ) {
                          final source = book.chapters[i].text;
                          final lower = source.toLowerCase();
                          var at = lower.indexOf(needle);
                          while (at >= 0 && found.length < 100) {
                            found.add((
                              chapter: i,
                              offset: at,
                              snippet: source
                                  .substring(
                                    math.max(0, at - 25),
                                    math.min(source.length, at + q.length + 60),
                                  )
                                  .replaceAll('\n', ' '),
                            ));
                            at = lower.indexOf(needle, at + needle.length);
                          }
                        }
                      }
                      update(() => results = found);
                    },
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '找到 ${results.length} 处（最多显示 100 处）',
                    style: const TextStyle(fontSize: 12),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: results.length,
                      itemBuilder: (_, i) {
                        final r = results[i];
                        return ListTile(
                          title: Text(
                            r.snippet,
                            style: const TextStyle(fontSize: 14),
                          ),
                          subtitle: Text(book.chapters[r.chapter].title),
                          onTap: () {
                            Navigator.pop(ctx);
                            jump(r.chapter, offset: r.offset);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    controller.dispose();
    dialogOpen = false;
  }

  Future<void> addNote() async {
    if (saving || pages.isEmpty) return;
    dialogOpen = true;
    final slice = pages[page];
    final quote = selected.isEmpty
        ? text.substring(slice.start, math.min(slice.end, slice.start + 180))
        : selected;
    final at = selected.isEmpty
        ? slice.start
        : text.indexOf(selected, slice.start);
    final comment = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(selected.isEmpty ? '记下这一页' : '保存摘录'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                quote.isEmpty ? '此页正文已被净化规则隐藏' : quote,
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, height: 1.7),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: comment,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(hintText: '此刻的想法（可选）'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (accepted == true) {
      saving = true;
      try {
        final now = DateTime.now().microsecondsSinceEpoch;
        await repo.addNote(
          Note(
            id: '${book.id}-$now',
            bookId: book.id,
            chapter: chapter,
            offset: sourceOffset(math.max(0, at)),
            quote: quote,
            comment: comment.text.trim(),
            created: now ~/ 1000,
          ),
        );
        message('摘录已保存到笔记');
      } catch (e) {
        message('笔记保存失败：$e');
      } finally {
        saving = false;
      }
    }
    comment.dispose();
    dialogOpen = false;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = readerSchemes[settings.theme]!;
    final style = TextStyle(
      color: scheme[1],
      fontSize: settings.fontSize,
      height: settings.lineHeight,
      fontFamily: settings.font,
      letterSpacing: .35,
    );
    return Theme(
      data: Theme.of(context).copyWith(
        brightness: settings.theme == 'night'
            ? Brightness.dark
            : Brightness.light,
        scaffoldBackgroundColor: scheme[0],
        appBarTheme: AppBarTheme(
          backgroundColor: scheme[0],
          foregroundColor: scheme[1],
          surfaceTintColor: Colors.transparent,
        ),
        iconTheme: IconThemeData(color: scheme[1]),
      ),
      child: Scaffold(
        appBar: AppBar(
          title: Text(book.title, style: const TextStyle(fontSize: 14)),
          actions: [
            IconButton(
              tooltip: '全文搜索',
              onPressed: search,
              icon: const Icon(Icons.search, size: 21),
            ),
            IconButton(
              tooltip: '摘录与笔记',
              onPressed: addNote,
              icon: const Icon(Icons.bookmark_add_outlined, size: 21),
            ),
            IconButton(
              tooltip: '阅读设置',
              onPressed: () async {
                dialogOpen = true;
                initialOffset = pages.isEmpty
                    ? book.offset
                    : sourceOffset(pages[page].start);
                await showReaderSettings(
                  context,
                  settings,
                  () => repo.saveSettings(settings),
                  changed: () => setState(() => layoutKey = ''),
                );
                dialogOpen = false;
              },
              icon: const Icon(Icons.palette_outlined, size: 21),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 10, 28, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        book.chapters[chapter].title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme[1].withValues(alpha: .65),
                        ),
                      ),
                    ),
                    Text(
                      '${chapter + 1} / ${book.chapters.length} 章',
                      style: TextStyle(
                        fontSize: 10,
                        color: scheme[1].withValues(alpha: .5),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: LayoutBuilder(
                    builder: (ctx, box) {
                      final key =
                          '$chapter/${box.maxWidth}/${box.maxHeight}/${settings.fontSize}/${settings.lineHeight}/${settings.font}/${settings.cjkSpacing}/${settings.purifyLines}/${MediaQuery.textScalerOf(ctx).scale(1)}';
                      if (layoutKey != key) {
                        buildText();
                        pages = paginate(
                          text,
                          style,
                          box.maxWidth,
                          box.maxHeight,
                          MediaQuery.textScalerOf(ctx),
                        );
                        final rendered = sourceOffsets.indexWhere(
                          (p) => p >= initialOffset,
                        );
                        page = pages.indexWhere((p) => p.end > rendered);
                        if (page < 0) page = pages.length - 1;
                        layoutKey = key;
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) {
                            setState(() {});
                            updateProgress();
                          }
                        });
                      }
                      final slice = pages[page];
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onHorizontalDragEnd: (d) {
                          if ((d.primaryVelocity ?? 0).abs() > 150) {
                            turn(d.primaryVelocity! < 0 ? 1 : -1);
                          }
                        },
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: text.isEmpty
                              ? Text('本章正文已被净化规则隐藏。可以在设置中修改规则。', style: style)
                              : SelectableText(
                                  text.substring(slice.start, slice.end),
                                  key: ValueKey(
                                    '$chapter-$page-${settings.fontSize}',
                                  ),
                                  style: style,
                                  textScaler: MediaQuery.textScalerOf(ctx),
                                  textDirection: TextDirection.ltr,
                                  onSelectionChanged: (s, cause) {
                                    final visible = text.substring(
                                      slice.start,
                                      slice.end,
                                    );
                                    selected = s.isValid && !s.isCollapsed
                                        ? visible.substring(
                                            s.start.clamp(0, visible.length),
                                            s.end.clamp(0, visible.length),
                                          )
                                        : '';
                                  },
                                  contextMenuBuilder: (ctx, editable) =>
                                      AdaptiveTextSelectionToolbar.buttonItems(
                                        anchors: editable.contextMenuAnchors,
                                        buttonItems: [
                                          ContextMenuButtonItem(
                                            label: '复制',
                                            onPressed: () {
                                              Clipboard.setData(
                                                ClipboardData(text: selected),
                                              );
                                              editable.hideToolbar();
                                            },
                                          ),
                                          ContextMenuButtonItem(
                                            label: '摘录',
                                            onPressed: () {
                                              editable.hideToolbar();
                                              addNote();
                                            },
                                          ),
                                        ],
                                      ),
                                ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: '章节目录',
                      onPressed: outline,
                      icon: const Icon(Icons.format_list_bulleted, size: 22),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: '上一页',
                      onPressed: () => turn(-1),
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Text(
                      '${page + 1} / ${pages.length} 页',
                      style: TextStyle(fontSize: 12, color: scheme[1]),
                    ),
                    IconButton(
                      tooltip: '下一页',
                      onPressed: () => turn(1),
                      icon: const Icon(Icons.chevron_right),
                    ),
                    const Spacer(),
                    Text(
                      '${(book.progress * 100).round()}%',
                      style: TextStyle(fontSize: 11, color: scheme[1]),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
