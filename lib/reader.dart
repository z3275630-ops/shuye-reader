import 'app_icons.dart';

import 'dart:async';
import 'dart:math' as math;
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models.dart';
import 'repository.dart';
import 'reader_controls.dart';
import 'services.dart';
import 'workbench.dart';
import 'page_turn.dart';
import 'typography.dart';
import 'reader_gestures.dart';

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
                  ListTile(
                    leading: const ShuyeIcon(Icons.tune),
                    title: const Text('更多阅读控制'),
                    subtitle: const Text('翻页、亮度、自动阅读、听书、双页和主题'),
                    onTap: () => advancedReaderSettings(ctx, s, () {
                      update(() {});
                      changed?.call();
                    }),
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

class ReadingLayout {
  final String text;
  final List<int> offsets;
  final List<PageSlice> pages;
  const ReadingLayout(this.text, this.offsets, this.pages);
}

// Layout uses actual font metrics, direction and accessibility text scaling.
// Every measurement is bounded to 5000 UTF-16 units for large TXT chapters.
List<PageSlice> paginate(
  String text,
  TextStyle style,
  double width,
  double height,
  TextScaler scaler, {
  ReaderSettings? settings,
}) {
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
      text: readerSpan(text.substring(start, end), style, settings),
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
  bool autoPaging = false, speaking = false, shield = false, immersive = false;
  bool showingSpread = false;
  int autoSeconds = 0, reminderSeconds = 0;
  DateTime recordAt = DateTime.now();
  List<String> speechChunks = [];
  int speechIndex = 0;
  final pageSurface = GlobalKey<PageTurnSurfaceState>();
  final layoutCache = <String, ReadingLayout>{};
  StreamSubscription<MethodCall>? deviceEvents;
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
    HardwareKeyboard.instance.addHandler(handlePhysicalKey);
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (active && !dialogOpen && !shield) {
        final now = DateTime.now();
        if (now.hour != recordAt.hour || now.day != recordAt.day) {
          unawaited(flushTime());
          recordAt = now;
        }
        seconds++;
        if (seconds >= 60) unawaited(flushTime());
        reminderSeconds++;
        final minutes = settings.number('reader.reminderMinutes', 30).round();
        if (minutes > 0 && reminderSeconds >= minutes * 60) {
          reminderSeconds = 0;
          autoPaging = false;
          message('已经阅读 $minutes 分钟，休息一下眼睛吧。');
        }
        if (autoPaging && !shield && pages.isNotEmpty) {
          autoSeconds++;
          final interval =
              settings.value('reader.autoMode', 'interval') == 'speed'
              ? ((pages[page].end - pages[page].start) /
                        settings
                            .number('reader.charsPerSecond', 10)
                            .clamp(3, 30))
                    .ceil()
              : settings.number('reader.autoInterval', 15).round();
          if (autoSeconds >= interval) {
            autoSeconds = 0;
            turn(1);
          }
        }
        if (settings.flag('reader.nightSchedule') &&
            DateTime.now().second == 0) {
          setState(() {});
        }
      }
    });
    unawaited(DeviceReader.configure(settings));
    DeviceReader.initialize();
    deviceEvents = DeviceReader.events.stream.listen((call) async {
      if (call.method == 'turn' && active && !dialogOpen && !shield) {
        turn(call.arguments as int);
      }
      if (call.method == 'ttsDone' && speaking && active && !dialogOpen) {
        if (speechIndex < speechChunks.length) {
          await speakChunk();
        } else {
          turnImmediate(1);
          await WidgetsBinding.instance.endOfFrame;
          if (mounted && speaking) await speakPage();
        }
      } else if (call.method == 'ttsDone' && speaking) {
        if (mounted) setState(() => speaking = false);
      }
      if (call.method == 'ttsError') {
        speaking = false;
        message('语音引擎播放失败，请检查系统语音设置。');
      }
    });
    unawaited(persist());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    active = state == AppLifecycleState.resumed;
    if (!active) {
      speaking = false;
      unawaited(DeviceReader.call('stopSpeech'));
      unawaited(flushTime());
      unawaited(persist());
    }
  }

  Future<void> flushTime() async {
    final elapsed = seconds;
    seconds = 0;
    try {
      await repo.record(book.id, elapsed, at: recordAt);
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
    HardwareKeyboard.instance.removeHandler(handlePhysicalKey);
    timer?.cancel();
    unawaited(deviceEvents?.cancel());
    unawaited(DeviceReader.call('stopSpeech'));
    unawaited(DeviceReader.configure(settings, reading: false));
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

  bool handlePhysicalKey(KeyEvent event) {
    if (event is! KeyDownEvent ||
        !active ||
        dialogOpen ||
        shield ||
        selected.isNotEmpty ||
        !settings.flag('reader.physicalKeys', true)) {
      return false;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isShiftPressed ||
        keyboard.isMetaPressed) {
      return false;
    }
    if ([
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.pageDown,
      LogicalKeyboardKey.space,
    ].contains(event.logicalKey)) {
      turn(1);
      return true;
    }
    if ([
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.pageUp,
    ].contains(event.logicalKey)) {
      turn(-1);
      return true;
    }
    return false;
  }

  void buildText() {
    final result = prepareText(book.chapters[chapter].text, settings);
    text = result.text;
    sourceOffsets = result.offsets;
  }

  int sourceOffset(int rendered) =>
      sourceOffsets[rendered.clamp(0, sourceOffsets.length - 1)];
  void updateProgress() {
    book.chapter = chapter;
    initialOffset = sourceOffset(pages[page].start);
    book.offset = sourceOffset(
      page + (showingSpread ? 1 : 0) >= pages.length - 1
          ? pages.last.end
          : pages[page].start,
    );
    book.lastRead = DateTime.now().millisecondsSinceEpoch;
    unawaited(persist());
  }

  void turn(int delta) {
    if (settings.flag('reader.sound') && !settings.flag('reader.eink')) {
      unawaited(SystemSound.play(SystemSoundType.click));
    }
    final effect = settings.flag('reader.eink')
        ? 'none'
        : settings.value('reader.animation', 'slide');
    if (pageSurface.currentState != null) {
      unawaited(
        pageSurface.currentState!.turn(
          () => turnImmediate(delta),
          effect,
          direction: delta >= 0 ? 1 : -1,
        ),
      );
    } else {
      turnImmediate(delta);
    }
  }

  void turnImmediate(int delta) {
    if (pages.isEmpty) return;
    autoSeconds = 0;
    final step = showingSpread ? 2 : 1;
    delta *= step;
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
      autoPaging = false;
      speaking = false;
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

  Future<void> speakPage() async {
    if (pages.isEmpty) return;
    final visible = text.substring(pages[page].start, pages[page].end);
    speechChunks = [];
    speechIndex = 0;
    var start = 0;
    while (start < visible.length) {
      var end = (start + 3500).clamp(0, visible.length);
      if (end < visible.length &&
          visible.codeUnitAt(end - 1) >= 0xd800 &&
          visible.codeUnitAt(end - 1) <= 0xdbff) {
        end--;
      }
      speechChunks.add(visible.substring(start, end));
      start = end;
    }
    if (speechChunks.isEmpty) {
      setState(() => speaking = false);
      return;
    }
    await speakChunk();
  }

  Future<void> speakChunk() async {
    try {
      await DeviceReader.call('speak', {
        'text': speechChunks[speechIndex++],
        'rate': settings.number('reader.speechRate', 1),
        'voice': settings.value('reader.voice', ''),
      });
    } catch (e) {
      if (mounted) {
        setState(() => speaking = false);
        message('听书未启动：$e');
      }
    }
  }

  Future<void> tools(String action) async {
    final quote = selected.isEmpty && pages.isNotEmpty
        ? text.substring(pages[page].start, pages[page].end)
        : selected;
    if (action == 'auto') {
      setState(() => autoPaging = !autoPaging);
      if (autoPaging) {
        speaking = false;
        await DeviceReader.call('stopSpeech');
      }
      autoSeconds = 0;
      return;
    }
    if (action == 'speech') {
      setState(() => speaking = !speaking);
      autoPaging = false;
      if (speaking) {
        await speakPage();
      } else {
        await DeviceReader.call('stopSpeech');
      }
      return;
    }
    if (action == 'shield') {
      setState(() => shield = true);
      return;
    }
    if (action == 'immersive') {
      setState(() => immersive = !immersive);
      return;
    }
    dialogOpen = true;
    try {
      if (action == 'ai') {
        await showAiAssistant(
          context,
          repo,
          settings,
          book: book,
          excerpt: quote,
        );
      }
      if (action == 'share' && mounted) {
        await showShareCard(
          context,
          quote,
          book.title,
          settings: settings,
          saveSettings: () => repo.saveSettings(settings),
        );
      }
      if (action == 'word' && mounted) {
        final data = await editFields(context, '保存生词', {
          '词语': selected,
          '释义说明': '',
          '分组': '',
        });
        if (data != null) {
          await repo.putEntry('vocabulary', data, bookId: book.id);
        }
      }
      if (action == 'images' && mounted) {
        await showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          isScrollControlled: true,
          builder: (c) => SafeArea(
            child: ListView(
              children: [
                for (final image in book.chapters[chapter].images)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: InteractiveViewer(
                      child: Image.memory(base64Decode(image)),
                    ),
                  ),
              ],
            ),
          ),
        );
      }
      if (action == 'progress' && mounted) {
        final data = await editFields(context, '全书进度跳转', {
          '百分比（0–100）': '${(book.progress * 100).round()}',
        });
        if (data != null) {
          final fraction =
              (double.tryParse(data['百分比（0–100）']!) ?? 0).clamp(0, 100) / 100;
          final total = book.chapters.fold<int>(0, (n, c) => n + c.text.length);
          var at = (total * fraction).round();
          for (var i = 0; i < book.chapters.length; i++) {
            if (at <= book.chapters[i].text.length) {
              jump(i, offset: at);
              break;
            }
            at -= book.chapters[i].text.length;
          }
        }
      }
      if (action == 'voice') {
        final voices = await DeviceReader.call<List<dynamic>>('voices') ?? [];
        if (mounted) {
          await showModalBottomSheet<void>(
            context: context,
            showDragHandle: true,
            builder: (c) => SafeArea(
              child: ListView(
                children: [
                  ListTile(
                    title: const Text('系统语音设置'),
                    onTap: () => DeviceReader.call('speechSettings'),
                  ),
                  for (final v in voices)
                    ListTile(
                      title: Text(v['name'] as String),
                      subtitle: Text(
                        '${v['language']} · ${v['network'] == true ? '联网' : '离线'}',
                      ),
                      onTap: () async {
                        settings.extra['reader.voice'] = v['name'];
                        await repo.saveSettings(settings);
                        if (c.mounted) Navigator.pop(c);
                      },
                    ),
                ],
              ),
            ),
          );
        }
      }
    } finally {
      dialogOpen = false;
    }
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
                        ? const ShuyeIcon(Icons.bookmark, size: 18)
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
                      prefixIcon: ShuyeIcon(Icons.search),
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
    final hour = DateTime.now().hour;
    final night =
        settings.flag('reader.nightSchedule') && (hour >= 20 || hour < 6);
    final base = readerSchemes[night ? 'night' : settings.theme]!;
    Color custom(String key, Color fallback) {
      final hex = settings.value(key, '');
      return RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex)
          ? Color(0xff000000 | int.parse(hex, radix: 16))
          : fallback;
    }

    final scheme = settings.flag('reader.eink')
        ? [Colors.white, Colors.black]
        : [
            night ? base[0] : custom('reader.background', base[0]),
            night ? base[1] : custom('reader.foreground', base[1]),
          ];
    final style = TextStyle(
      color: scheme[1],
      fontSize: settings.fontSize,
      height: settings.lineHeight,
      fontFamily: settings.value('reader.customFont', settings.font),
      fontFeatures: settings.flag('reader.punctuation')
          ? [const ui.FontFeature.enable('palt')]
          : null,
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
        appBar: immersive
            ? null
            : AppBar(
                title: Text(book.title, style: const TextStyle(fontSize: 14)),
                actions: [
                  PopupMenuButton<String>(
                    tooltip: '阅读工具',
                    onSelected: (v) => unawaited(tools(v)),
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'auto',
                        child: Text(autoPaging ? '停止自动翻页' : '自动翻页'),
                      ),
                      PopupMenuItem(
                        value: 'speech',
                        child: Text(speaking ? '停止听书' : '朗读本页并继续'),
                      ),
                      const PopupMenuItem(
                        value: 'voice',
                        child: Text('选择系统声音'),
                      ),
                      const PopupMenuItem(
                        value: 'progress',
                        child: Text('全书进度跳转'),
                      ),
                      const PopupMenuItem(
                        value: 'ai',
                        child: Text('AI 解读本页 / 摘录'),
                      ),
                      const PopupMenuItem(value: 'word', child: Text('保存生词')),
                      const PopupMenuItem(
                        value: 'share',
                        child: Text('生成摘录卡片'),
                      ),
                      if (book.chapters[chapter].images.isNotEmpty)
                        const PopupMenuItem(
                          value: 'images',
                          child: Text('本章插图'),
                        ),
                      const PopupMenuItem(
                        value: 'immersive',
                        child: Text('沉浸阅读（双击返回）'),
                      ),
                      const PopupMenuItem(
                        value: 'shield',
                        child: Text('临时隐藏书页'),
                      ),
                    ],
                  ),
                  IconButton(
                    tooltip: '全文搜索',
                    onPressed: search,
                    icon: const ShuyeIcon(Icons.search, size: 21),
                  ),
                  IconButton(
                    tooltip: '摘录与笔记',
                    onPressed: addNote,
                    icon: const ShuyeIcon(
                      Icons.bookmark_add_outlined,
                      size: 21,
                    ),
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
                      await DeviceReader.configure(settings);
                    },
                    icon: const ShuyeIcon(Icons.palette_outlined, size: 21),
                  ),
                ],
              ),
        body: shield
            ? GestureDetector(
                behavior: HitTestBehavior.opaque,
                onDoubleTap: () => setState(() => shield = false),
                child: const Center(
                  child: Text('暂时休息\n双击返回阅读', textAlign: TextAlign.center),
                ),
              )
            : SafeArea(
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
                        padding: EdgeInsets.symmetric(
                          horizontal: settings
                              .number('reader.margin', 28)
                              .clamp(12, 48),
                        ),
                        child: LayoutBuilder(
                          builder: (ctx, box) {
                            final key =
                                '$chapter/${box.maxWidth}/${box.maxHeight}/${settings.toJson()}/${MediaQuery.textScalerOf(ctx).scale(1)}';
                            final doublePage =
                                settings.flag('reader.doublePage') &&
                                box.maxWidth > 644;
                            showingSpread = doublePage;
                            final pageWidth = doublePage
                                ? (box.maxWidth - 32) / 2
                                : box.maxWidth;
                            if (layoutKey != key) {
                              final cached = layoutCache[key];
                              if (cached != null) {
                                text = cached.text;
                                sourceOffsets = cached.offsets;
                                pages = cached.pages;
                              } else {
                                buildText();
                                pages = paginate(
                                  text,
                                  style,
                                  pageWidth,
                                  box.maxHeight,
                                  MediaQuery.textScalerOf(ctx),
                                  settings: settings,
                                );
                                if (layoutCache.length >= 3) {
                                  layoutCache.remove(layoutCache.keys.first);
                                }
                                layoutCache[key] = ReadingLayout(
                                  text,
                                  sourceOffsets,
                                  pages,
                                );
                              }
                              selected = '';
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
                            return ReaderTapSurface(
                              canTurn: () => selected.isEmpty,
                              onDoubleTap: () =>
                                  setState(() => immersive = !immersive),
                              onTap: (location) {
                                if (selected.isNotEmpty) return;
                                if (settings.flag('reader.oneHand')) {
                                  turn(1);
                                } else if (settings.flag(
                                  'reader.tapPages',
                                  true,
                                )) {
                                  if (location.dx < box.maxWidth * .3) {
                                    turn(-1);
                                  } else if (location.dx > box.maxWidth * .7) {
                                    turn(1);
                                  }
                                }
                              },
                              onHorizontalDragEnd: (d) {
                                if ((d.primaryVelocity ?? 0).abs() > 150) {
                                  turn(d.primaryVelocity! < 0 ? 1 : -1);
                                }
                              },
                              child: PageTurnSurface(
                                key: pageSurface,
                                color: scheme[0],
                                child: Stack(
                                  children: [
                                    Align(
                                      alignment: Alignment.topLeft,
                                      child: text.isEmpty
                                          ? Text(
                                              '本章正文已被净化规则隐藏。可以在设置中修改规则。',
                                              style: style,
                                            )
                                          : Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Expanded(
                                                  child: SelectableText.rich(
                                                    readerSpan(
                                                      text.substring(
                                                        slice.start,
                                                        slice.end,
                                                      ),
                                                      style,
                                                      settings,
                                                    ),
                                                    key: ValueKey(
                                                      '$layoutKey:$page',
                                                    ),
                                                    style: style,
                                                    textScaler:
                                                        MediaQuery.textScalerOf(
                                                          ctx,
                                                        ),
                                                    textDirection:
                                                        TextDirection.ltr,
                                                    onSelectionChanged:
                                                        (s, cause) {
                                                          final visible = text
                                                              .substring(
                                                                slice.start,
                                                                slice.end,
                                                              );
                                                          selected =
                                                              s.isValid &&
                                                                  !s.isCollapsed
                                                              ? visible.substring(
                                                                  s.start.clamp(
                                                                    0,
                                                                    visible
                                                                        .length,
                                                                  ),
                                                                  s.end.clamp(
                                                                    0,
                                                                    visible
                                                                        .length,
                                                                  ),
                                                                )
                                                              : '';
                                                        },
                                                    contextMenuBuilder: (ctx, editable) => AdaptiveTextSelectionToolbar.buttonItems(
                                                      anchors: editable
                                                          .contextMenuAnchors,
                                                      buttonItems: [
                                                        ContextMenuButtonItem(
                                                          label: '复制',
                                                          onPressed: () {
                                                            Clipboard.setData(
                                                              ClipboardData(
                                                                text: selected,
                                                              ),
                                                            );
                                                            editable
                                                                .hideToolbar();
                                                          },
                                                        ),
                                                        ContextMenuButtonItem(
                                                          label: '摘录',
                                                          onPressed: () {
                                                            editable
                                                                .hideToolbar();
                                                            addNote();
                                                          },
                                                        ),
                                                        ContextMenuButtonItem(
                                                          label: 'AI 解读',
                                                          onPressed: () {
                                                            editable
                                                                .hideToolbar();
                                                            tools('ai');
                                                          },
                                                        ),
                                                        ContextMenuButtonItem(
                                                          label: '生词',
                                                          onPressed: () {
                                                            editable
                                                                .hideToolbar();
                                                            tools('word');
                                                          },
                                                        ),
                                                        ContextMenuButtonItem(
                                                          label: '分享卡片',
                                                          onPressed: () {
                                                            editable
                                                                .hideToolbar();
                                                            tools('share');
                                                          },
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                                if (doublePage) ...[
                                                  Container(
                                                    width: 32,
                                                    decoration: BoxDecoration(
                                                      gradient: LinearGradient(
                                                        colors: [
                                                          scheme[0],
                                                          scheme[1].withValues(
                                                            alpha: .12,
                                                          ),
                                                          scheme[0],
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                  Expanded(
                                                    child:
                                                        page + 1 < pages.length
                                                        ? SelectableText.rich(
                                                            readerSpan(
                                                              text.substring(
                                                                pages[page + 1]
                                                                    .start,
                                                                pages[page + 1]
                                                                    .end,
                                                              ),
                                                              style,
                                                              settings,
                                                            ),
                                                            textScaler:
                                                                MediaQuery.textScalerOf(
                                                                  ctx,
                                                                ),
                                                          )
                                                        : const SizedBox(),
                                                  ),
                                                ],
                                              ],
                                            ),
                                    ),
                                    if (!settings.flag('reader.eink') &&
                                        settings.value(
                                              'reader.atmosphere',
                                              'none',
                                            ) !=
                                            'none')
                                      Positioned.fill(
                                        child: Atmosphere(
                                          kind: settings.value(
                                            'reader.atmosphere',
                                            'none',
                                          ),
                                        ),
                                      ),
                                  ],
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
                            icon: const ShuyeIcon(
                              Icons.format_list_bulleted,
                              size: 22,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            tooltip: '上一页',
                            onPressed: () => turn(-1),
                            icon: const ShuyeIcon(Icons.chevron_left),
                          ),
                          Text(
                            '${page + 1} / ${pages.length} 页',
                            style: TextStyle(fontSize: 12, color: scheme[1]),
                          ),
                          IconButton(
                            tooltip: '下一页',
                            onPressed: () => turn(1),
                            icon: const ShuyeIcon(Icons.chevron_right),
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
