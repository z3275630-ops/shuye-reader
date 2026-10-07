import 'app_icons.dart';
import 'appearance.dart';

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
import 'reader_viewport.dart';
import 'privacy.dart';

const readerSchemes = {
  'paper': [Color(0xfff4eddf), Color(0xff3f392e)],
  'white': [Color(0xfffafafa), Color(0xff303330)],
  'sage': [Color(0xffe4ebdf), Color(0xff344333)],
  'night': [Color(0xff212121), Color(0xfff5f5f3)],
  'claude': [Color(0xfffaf9f5), Color(0xff22221f)],
  'mist': [Color(0xfff7fafc), Color(0xff253447)],
};
const readerNames = {
  'paper': '暖纸',
  'white': '纸白',
  'sage': '青竹',
  'night': '夜读',
  'claude': 'Claude',
  'mist': '海雾',
};

TextSelectionThemeData readerSelectionTheme(List<Color> scheme) {
  final paper = scheme[0], ink = scheme[1];
  double contrast(Color a, Color b) {
    final x = a.computeLuminance(), y = b.computeLuminance();
    return (math.max(x, y) + .05) / (math.min(x, y) + .05);
  }

  final dark = paper.computeLuminance() < .2;
  final clay = applicationTheme(dark ? Brightness.dark : Brightness.light)
      .colorScheme
      .primary;
  final handle = contrast(clay, paper) >= 3
      ? clay
      : contrast(ink, paper) >= 3
      ? ink
      : paper.computeLuminance() > .179
      ? Colors.black
      : Colors.white;
  // Highlight the actual paper without sacrificing foreground readability.
  // The translucent range and the opaque handles have different roles.
  var alpha = dark ? .28 : .18;
  if (contrast(ink, paper) >= 4.5) {
    while (contrast(
          ink,
          Color.alphaBlend(ink.withValues(alpha: alpha), paper),
        ) <
        4.5) {
      alpha *= .8;
    }
  }
  return TextSelectionThemeData(
    cursorColor: handle,
    selectionHandleColor: handle,
    selectionColor: ink.withValues(alpha: alpha),
  );
}

// Only typography and text transformations belong to pagination identity.
String readerLayoutSettingsKey(ReaderSettings s) => jsonEncode({
  'font': readerFont(s),
  'size': s.fontSize,
  'height': s.lineHeight,
  'cjk': s.cjkSpacing,
  'rules': s.purifyLines,
  'highlightGeometry': s.flag('reader.bionic')
      ? s.value('reader.highlights', '')
      : '',
  for (final key in [
    'reader.margin',
    'reader.alignment',
    'reader.punctuation',
    'reader.chinese',
    'reader.ignoreBlank',
    'reader.hyphenation',
    'reader.bionic',
    'reader.doublePage',
  ])
    key: s.extra[key],
});

String readerFont(ReaderSettings settings) {
  final custom = settings.value('reader.customFont', '');
  if (custom.isNotEmpty) return custom;
  return settings.font == 'sans'
      ? ShuyeStyle.fontFamily
      : ShuyeStyle.readerFontFamily;
}

List<Color> readerColors(ReaderSettings settings, {DateTime? at}) {
  if (settings.flag('reader.eink')) return [Colors.white, Colors.black];
  final hour = (at ?? DateTime.now()).hour;
  final night =
      settings.flag('reader.nightSchedule') && (hour >= 20 || hour < 6);
  final appearance = AppAppearance.fromSettings(settings);
  final dark =
      appearance.mode == 'dark' ||
      (appearance.mode == 'system' &&
          ui.PlatformDispatcher.instance.platformBrightness == Brightness.dark);
  final shared = applicationTheme(
    dark ? Brightness.dark : Brightness.light,
    palette: appearance.theme,
  ).colorScheme;
  final base = night
      ? readerSchemes['night']!
      : settings.theme == 'follow'
      ? [shared.surface, shared.onSurface]
      : readerSchemes[settings.theme] ?? readerSchemes['claude']!;
  Color custom(String key, Color fallback) {
    final hex = settings.value(key, '');
    return RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex)
        ? Color(0xff000000 | int.parse(hex, radix: 16))
        : fallback;
  }

  return night
      ? base
      : [
          custom('reader.background', base[0]),
          custom('reader.foreground', base[1]),
        ];
}

Future<void> showReaderSettings(
  BuildContext context,
  ReaderSettings s,
  Future<void> Function() save, {
  VoidCallback? changed,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    sheetAnimationStyle: applicationMotion(context),
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
                  Text('让文字，刚刚好。', style: ShuyeStyle.panelTitle),
                  const SizedBox(height: 22),
                  Container(
                    key: const ValueKey('reader-settings-preview'),
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: readerColors(s)[0],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text.rich(
                      readerSpan(
                        '风翻过书页，文字慢慢清晰。\nA quiet page, a little time.',
                        TextStyle(
                          color: readerColors(s)[1],
                          fontSize: s.fontSize,
                          height: s.lineHeight,
                          fontFamily: readerFont(s),
                        ),
                        s,
                      ),
                      textAlign: readerTextAlign(s),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SettingSlider(
                    title: '字号',
                    displayValue: '${s.fontSize.round()}',
                    value: s.fontSize,
                    min: 14,
                    max: 32,
                    divisions: 18,
                    onChanged: (v) => change(() => s.fontSize = v),
                  ),
                  SettingSlider(
                    title: '行距',
                    displayValue: s.lineHeight.toStringAsFixed(2),
                    value: s.lineHeight,
                    min: 1.3,
                    max: 2.4,
                    divisions: 22,
                    onChanged: (v) => change(() => s.lineHeight = v),
                  ),
                  Wrap(
                    spacing: 10,
                    children: readerSchemes.entries
                        .where((e) => e.key != 'paper')
                        .map(
                          (e) => ChoiceChip(
                            label: Text(readerNames[e.key]!),
                            selected: s.theme == 'follow'
                                ? (e.key == 'night'
                                      ? s.value('app.themeMode', 'system') ==
                                            'dark'
                                      : s.value('app.themeMode', 'system') !=
                                                'dark' &&
                                            AppAppearance.fromSettings(s)
                                                    .theme ==
                                                e.key)
                                : s.theme == e.key,
                            avatar: CircleAvatar(
                              backgroundColor: e.value[0],
                              radius: 8,
                            ),
                            onSelected: (_) => change(
                              () => selectAppPalette(
                                s,
                                e.key == 'night' ? 'claude' : e.key,
                                mode: e.key == 'night' ? 'dark' : 'light',
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '配色同步应用到首页、书架、设置与正文。',
                    style: TextStyle(fontSize: 12),
                  ),
                  TextButton(
                    onPressed: () => change(() {
                      s.fontSize = 18;
                      s.lineHeight = 1.65;
                      s.extra['reader.ignoreBlank'] = true;
                    }),
                    child: const Text('使用 Claude 正文间距'),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    children: [
                      for (final option in {
                        'justify': '两端对齐',
                        'left': '自然左对齐',
                      }.entries)
                        ChoiceChip(
                          label: Text(option.value),
                          selected:
                              s.value('reader.alignment', 'justify') ==
                              option.key,
                          onSelected: (_) => change(
                            () => s.extra['reader.alignment'] = option.key,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text('正文字体', style: Theme.of(ctx).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      for (final option in {
                        'sans': '清晰黑体',
                        'serif': '书页宋体',
                      }.entries)
                        ChoiceChip(
                          label: Text(option.value),
                          selected:
                              s.value('reader.customFont', '').isEmpty &&
                              s.font == option.key,
                          onSelected: (_) => change(() {
                            s.font = option.key;
                            s.extra.remove('reader.customFont');
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('中西文自动留空'),
                    subtitle: const Text('让中文与 English、数字之间更舒展'),
                    value: s.cjkSpacing,
                    onChanged: (v) => change(() => s.cjkSpacing = v),
                  ),
                  Text(
                    '界面字体与正文独立；也可以在字体工具中使用已导入的字体。',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
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

/// In-reader controls use the real page above the dock as their preview.
/// The complete editor remains available from settings and the More button.
class ReaderQuickSettings extends StatelessWidget {
  final ReaderSettings settings;
  final VoidCallback changed, close, more;
  const ReaderQuickSettings({
    super.key,
    required this.settings,
    required this.changed,
    required this.close,
    required this.more,
  });
  @override
  Widget build(BuildContext context) {
    void change(VoidCallback action) {
      action();
      changed();
    }

    return SafeArea(
      top: false,
      child: Column(
        children: [
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '阅读设置',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: '完整阅读设置',
                  onPressed: more,
                  icon: const ShuyeIcon(Icons.more_horiz),
                ),
                TextButton(onPressed: close, child: const Text('开始阅读')),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SettingSlider(
                    title: '字号',
                    compact: true,
                    displayValue: '${settings.fontSize.round()}',
                    value: settings.fontSize,
                    min: 14,
                    max: 32,
                    divisions: 18,
                    onChanged: (v) => change(() => settings.fontSize = v),
                  ),
                  SettingSlider(
                    title: '行距',
                    compact: true,
                    displayValue: settings.lineHeight.toStringAsFixed(2),
                    value: settings.lineHeight,
                    min: 1.3,
                    max: 2.4,
                    divisions: 22,
                    onChanged: (v) => change(() => settings.lineHeight = v),
                  ),
                  Wrap(
                    spacing: 10,
                    children: [
                      for (final option in {
                        'sans': '清晰黑体',
                        'serif': '书页宋体',
                      }.entries)
                        ChoiceChip(
                          label: Text(option.value),
                          selected:
                              settings.value('reader.customFont', '').isEmpty &&
                              settings.font == option.key,
                          onSelected: (_) => change(() {
                            settings.font = option.key;
                            settings.extra.remove('reader.customFont');
                          }),
                        ),
                    ],
                  ),
                  Wrap(
                    spacing: 10,
                    children: [
                      for (final option in readerSchemes.entries.where(
                        (e) => e.key != 'paper',
                      ))
                        ChoiceChip(
                          label: Text(readerNames[option.key]!),
                          avatar: CircleAvatar(
                            backgroundColor: option.value[0],
                            radius: 8,
                          ),
                          selected: settings.theme == 'follow'
                              ? (option.key == 'night'
                                    ? AppAppearance.fromSettings(settings)
                                              .mode ==
                                          'dark'
                                    : AppAppearance.fromSettings(settings)
                                                  .mode !=
                                              'dark' &&
                                          AppAppearance.fromSettings(settings)
                                                  .theme ==
                                              option.key)
                              : settings.theme == option.key,
                          onSelected: (_) => change(
                            () => selectAppPalette(
                              settings,
                              option.key == 'night' ? 'claude' : option.key,
                              mode: option.key == 'night' ? 'dark' : 'light',
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ],
      ),
    );
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
      textAlign: readerTextAlign(settings),
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
  bool autoPaging = false, speaking = false, shield = false, immersive = true;
  bool settingsOpen = false;
  int? settingsAnchor;
  late final int libraryGeneration;
  bool? routeCurrent;
  bool get staleLibrary => libraryGeneration != repo.libraryGeneration;
  bool showingSpread = false;
  bool endNotified = false;
  void toggleChrome() {
    if (!mounted) return;
    if (settingsOpen) {
      toggleSettings();
      return;
    }
    setState(() => immersive = !immersive);
  }

  void toggleSettings() {
    pageSurface.currentState?.cancel();
    if (!settingsOpen) {
      settingsAnchor = pages.isEmpty
          ? book.offset
          : sourceOffset(pages[page].start);
    }
    initialOffset = settingsAnchor ?? book.offset;
    setState(() {
      settingsOpen = !settingsOpen;
      dialogOpen = settingsOpen;
      immersive = !settingsOpen;
    });
    if (!settingsOpen) unawaited(saveReadingSettings());
  }

  Future<void> saveReadingSettings() async {
    try {
      await repo.saveSettings(settings);
      await DeviceReader.configure(settings);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('设置保存失败：$e')));
      }
    }
  }

  int autoSeconds = 0, reminderSeconds = 0;
  DateTime recordAt = DateTime.now();
  List<String> speechChunks = [];
  int speechIndex = 0;
  final pageSurface = GlobalKey<PageTurnSurfaceState>();
  final layoutCache = <String, ReadingLayout>{};
  final pendingLayouts = <String>{};
  StreamSubscription<MethodCall>? deviceEvents;
  Book get book => widget.book;
  ReaderSettings get settings => widget.settings;
  ReaderRepository get repo => widget.repository;
  @override
  void initState() {
    super.initState();
    libraryGeneration = repo.libraryGeneration;
    repo.readingFlushers.add(flushTime);
    privacyLocked.addListener(privacyChanged);
    chapter = book.chapter;
    initialOffset = book.offset;
    book.lastRead = DateTime.now().millisecondsSinceEpoch;
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(handlePhysicalKey);
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!staleLibrary &&
          !repo.libraryChanging &&
          active &&
          !privacyLocked.value &&
          !dialogOpen &&
          !shield &&
          (ModalRoute.of(context)?.isCurrent ?? true)) {
        final now = DateTime.now();
        if (now.hour != recordAt.hour ||
            now.day != recordAt.day ||
            now.month != recordAt.month ||
            now.year != recordAt.year) {
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
      if (!mounted) return;
      if (call.method == 'deviceError') message('屏幕设置未完成：${call.arguments}');
      if (call.method == 'turn' &&
          active &&
          !privacyLocked.value &&
          !dialogOpen &&
          !shield &&
          (ModalRoute.of(context)?.isCurrent ?? true)) {
        turn(call.arguments as int);
      }
      if (call.method == 'ttsDone' &&
          speaking &&
          active &&
          !privacyLocked.value &&
          !dialogOpen) {
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = ModalRoute.of(context)?.isCurrent ?? true;
    if (routeCurrent == current) return;
    routeCurrent = current;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(
          DeviceReader.setFullscreen(
            !privacyLocked.value && (ModalRoute.of(context)?.isCurrent ?? true),
          ),
        );
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    active = state == AppLifecycleState.resumed;
    if (active &&
        !privacyLocked.value &&
        ModalRoute.of(context)?.isCurrent == true) {
      unawaited(DeviceReader.setFullscreen(true));
    }
    if (!active) {
      pageSurface.currentState?.cancel();
      speaking = false;
      unawaited(DeviceReader.stopSpeech());
      unawaited(flushTime());
      unawaited(persist());
    }
  }

  void privacyChanged() {
    if (privacyLocked.value) {
      pageSurface.currentState?.cancel();
      unawaited(flushTime());
      unawaited(persist());
      speaking = false;
      autoSeconds = 0;
      unawaited(DeviceReader.stopSpeech());
    }
    final reading =
        !privacyLocked.value &&
        active &&
        (ModalRoute.of(context)?.isCurrent ?? true);
    unawaited(DeviceReader.configure(settings, reading: reading));
    unawaited(DeviceReader.setFullscreen(reading));
  }

  Future<void> flushTime() async {
    if (staleLibrary || repo.libraryChanging) {
      seconds = 0;
      return;
    }
    final elapsed = seconds;
    seconds = 0;
    try {
      await repo.record(book.id, elapsed, at: recordAt);
    } catch (e) {
      if (mounted) message('阅读时长暂未保存，下次保存时重试：$e');
    }
  }

  Future<void> persist() async {
    if (staleLibrary || repo.libraryChanging) return;
    try {
      await repo.saveProgress(book);
    } catch (e) {
      if (mounted) message('进度保存失败：$e');
    }
  }

  @override
  void dispose() {
    privacyLocked.removeListener(privacyChanged);
    repo.readingFlushers.remove(flushTime);
    HardwareKeyboard.instance.removeHandler(handlePhysicalKey);
    timer?.cancel();
    unawaited(deviceEvents?.cancel());
    unawaited(DeviceReader.stopSpeech());
    unawaited(DeviceReader.configure(settings, reading: false));
    unawaited(DeviceReader.setFullscreen(false));
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
        privacyLocked.value ||
        !(ModalRoute.of(context)?.isCurrent ?? true) ||
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
    if (privacyLocked.value) return;
    if (!mounted || staleLibrary || pages.isEmpty) return;
    final step = showingSpread ? 2 : 1;
    if (pageSurface.currentState?.busy != true &&
        ((delta < 0 && chapter == 0 && page - step < 0) ||
            (delta > 0 &&
                chapter == book.chapters.length - 1 &&
                page + step >= pages.length))) {
      turnImmediate(delta);
      return;
    }
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
    if (staleLibrary || !mounted || privacyLocked.value) return;
    if (pages.isEmpty) return;
    autoSeconds = 0;
    final step = showingSpread ? 2 : 1;
    delta *= step;
    selected = '';
    if (page + delta >= 0 && page + delta < pages.length) {
      endNotified = false;
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
      if (delta > 0 && !endNotified && mounted) {
        endNotified = true;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('已读到全书末页'),
            duration: Duration(milliseconds: 900),
            showCloseIcon: true,
            persist: false,
          ),
        );
      }
    }
  }

  void jump(int to, {int offset = 0}) {
    endNotified = false;
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
    if (privacyLocked.value) return;
    if (action == 'search') {
      await search();
      return;
    }
    if (action == 'note') {
      await addNote();
      return;
    }
    try {
      await toolAction(action);
    } catch (e) {
      message('阅读操作未完成：$e');
    }
  }

  Future<void> toolAction(String action) async {
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
      toggleChrome();
      return;
    }
    pageSurface.currentState?.cancel();
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
                    onTap: () async {
                      try {
                        await DeviceReader.call('speechSettings');
                      } catch (e) {
                        if (context.mounted) message('无法打开语音设置：$e');
                      }
                    },
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
    pageSurface.currentState?.cancel();
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
                          fontFamily: ShuyeStyle.fontFamily,
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
    pageSurface.currentState?.cancel();
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
    pageSurface.currentState?.cancel();
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
    if (staleLibrary) {
      return Scaffold(
        appBar: AppBar(title: const Text('书库已恢复')),
        body: Center(
          child: FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('返回后重新打开书籍'),
          ),
        ),
      );
    }
    final scheme = readerColors(settings);
    final style = TextStyle(
      inherit: false,
      textBaseline: TextBaseline.alphabetic,
      color: scheme[1],
      fontSize: settings.fontSize,
      height: settings.lineHeight,
      fontFamily: readerFont(settings),
      fontFeatures: settings.flag('reader.punctuation')
          ? [const ui.FontFeature.enable('palt')]
          : null,
      letterSpacing: 0,
    );
    final topControls = AppBar(
      primary: false,
      title: Text(
        book.title,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
      ),
      actions: [
        PopupMenuButton<String>(
          tooltip: '阅读工具',
          icon: const ShuyeIcon(Icons.more_vert, size: 21),
          onSelected: (v) => unawaited(tools(v)),
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'search', child: Text('全文搜索')),
            const PopupMenuItem(value: 'note', child: Text('摘录与笔记')),
            PopupMenuItem(
              value: 'auto',
              child: Text(autoPaging ? '停止自动翻页' : '自动翻页'),
            ),
            PopupMenuItem(
              value: 'speech',
              child: Text(speaking ? '停止听书' : '朗读本页并继续'),
            ),
            const PopupMenuItem(value: 'voice', child: Text('选择系统声音')),
            const PopupMenuItem(value: 'progress', child: Text('全书进度跳转')),
            const PopupMenuItem(value: 'ai', child: Text('AI 解读本页 / 摘录')),
            const PopupMenuItem(value: 'word', child: Text('保存生词')),
            const PopupMenuItem(value: 'share', child: Text('生成摘录卡片')),
            if (book.chapters[chapter].images.isNotEmpty)
              const PopupMenuItem(value: 'images', child: Text('本章插图')),
            const PopupMenuItem(
              value: 'immersive',
              child: Text('全屏阅读（点中间恢复工具栏）'),
            ),
            const PopupMenuItem(value: 'shield', child: Text('临时隐藏书页')),
          ],
        ),

        IconButton(
          tooltip: '阅读设置',
          onPressed: toggleSettings,
          icon: const ShuyeIcon(Icons.palette_outlined, size: 21),
        ),
      ],
    );
    return Theme(
      data:
          applicationTheme(
            scheme[0].computeLuminance() < .5
                ? Brightness.dark
                : Brightness.light,
            palette: AppAppearance.fromSettings(settings).theme,
          ).copyWith(
            scaffoldBackgroundColor: scheme[0],
            appBarTheme: AppBarTheme(
              backgroundColor: scheme[0],
              foregroundColor: scheme[1],
              surfaceTintColor: Colors.transparent,
            ),
            iconTheme: IconThemeData(color: scheme[1]),
            textSelectionTheme: readerSelectionTheme(scheme),
          ),
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: shield
            ? GestureDetector(
                behavior: HitTestBehavior.opaque,
                onDoubleTap: () => setState(() => shield = false),
                child: Center(
                  child: Text(
                    '暂时休息\n双击返回阅读',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme[1]),
                  ),
                ),
              )
            : ReaderViewport(
                immersive: immersive,
                closePanel: toggleSettings,
                topControls: topControls,
                bottomPanel: settingsOpen
                    ? ReaderQuickSettings(
                        settings: settings,
                        changed: () {
                          initialOffset = settingsAnchor ?? book.offset;
                          setState(() {});
                        },
                        close: toggleSettings,
                        more: () async {
                          await showReaderSettings(
                            context,
                            settings,
                            () => repo.saveSettings(settings),
                            changed: () {
                              if (mounted) {
                                initialOffset = settingsAnchor ?? book.offset;
                                setState(() {});
                              }
                            },
                          );
                          if (mounted) await DeviceReader.configure(settings);
                        },
                      )
                    : null,
                bottomControls: ReaderFooter(
                  page: page + 1,
                  pages: pages.length,
                  progress: book.progress,
                  ink: scheme[1],
                  outline: outline,
                  previous: () => turn(-1),
                  next: () => turn(1),
                ),
                child: LayoutBuilder(
                  builder: (ctx, box) {
                    final bodyHeight =
                        box.maxHeight -
                        ReaderViewport.headerExtent -
                        ReaderViewport.footerExtent(ctx);
                    final margin = settings
                        .number('reader.margin', 28)
                        .clamp(12.0, 48.0);
                    final contentWidth = box.maxWidth - margin * 2;
                    final doublePage =
                        settings.flag('reader.doublePage') &&
                        contentWidth > 644;
                    Widget header(int c) => SizedBox(
                      height: ReaderViewport.headerExtent,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                book.chapters[c].title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: scheme[1].withValues(alpha: .65),
                                ),
                              ),
                            ),
                            Text(
                              '${c + 1} / ${book.chapters.length} 章',
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme[1].withValues(alpha: .65),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                    Widget footer(int c, int p, ReadingLayout layout) {
                      final end =
                          p + (doublePage ? 1 : 0) >= layout.pages.length - 1;
                      final source =
                          layout.offsets[(end
                                  ? layout.pages.last.end
                                  : layout.pages[p].start)
                              .clamp(0, layout.offsets.length - 1)];
                      final progress =
                          book.chapters
                              .take(c)
                              .fold<int>(0, (sum, ch) => sum + ch.text.length) +
                          source;
                      final total = book.chapters.fold<int>(
                        0,
                        (sum, ch) => sum + ch.text.length,
                      );
                      return SizedBox(
                        height: ReaderViewport.footerExtent(ctx),
                        child: Center(
                          child: Text(
                            '${p + 1} / ${layout.pages.length} 页 · ${total == 0 ? 0 : (progress * 100 / total).clamp(0, 100).round()}%',
                            style: TextStyle(
                              fontSize: 11,
                              color: scheme[1].withValues(alpha: .7),
                            ),
                          ),
                        ),
                      );
                    }

                    final key =
                        '$chapter/${box.maxWidth}/$bodyHeight/${readerLayoutSettingsKey(settings)}/${MediaQuery.textScalerOf(ctx).scale(settings.fontSize)}';
                    showingSpread = doublePage;
                    final pageWidth = doublePage
                        ? (contentWidth - 32) / 2
                        : contentWidth;
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
                          bodyHeight,
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
                    Widget? adjacent(int delta) {
                      final step = doublePage ? 2 : 1;
                      var targetChapter = chapter;
                      var targetPage = page + delta * step;
                      ReadingLayout target = ReadingLayout(
                        text,
                        sourceOffsets,
                        pages,
                      );
                      if (targetPage < 0 || targetPage >= pages.length) {
                        targetChapter += delta;
                        if (targetChapter < 0 ||
                            targetChapter >= book.chapters.length) {
                          return null;
                        }
                        final targetKey =
                            '$targetChapter/${box.maxWidth}/$bodyHeight/${readerLayoutSettingsKey(settings)}/${MediaQuery.textScalerOf(ctx).scale(settings.fontSize)}';
                        final cached = layoutCache[targetKey];
                        if (cached == null) {
                          if (pendingLayouts.add(targetKey)) {
                            final activeKey = layoutKey;
                            final targetText =
                                book.chapters[targetChapter].text;
                            final capturedSettings = ReaderSettings.fromJson(
                              settings.toJson(),
                            );
                            final scaler = MediaQuery.textScalerOf(ctx);
                            void prepareNeighbor(Duration _) {
                              if (mounted &&
                                  pageSurface.currentState?.busy == true) {
                                WidgetsBinding.instance.addPostFrameCallback(
                                  prepareNeighbor,
                                );
                                return;
                              }
                              pendingLayouts.remove(targetKey);
                              if (!mounted ||
                                  staleLibrary ||
                                  layoutKey != activeKey) {
                                return;
                              }
                              final prepared = prepareText(
                                targetText,
                                capturedSettings,
                              );
                              final preparedLayout = ReadingLayout(
                                prepared.text,
                                prepared.offsets,
                                paginate(
                                  prepared.text,
                                  style,
                                  pageWidth,
                                  bodyHeight,
                                  scaler,
                                  settings: capturedSettings,
                                ),
                              );
                              if (layoutCache.length >= 3) {
                                layoutCache.remove(
                                  layoutCache.keys.firstWhere(
                                    (k) => k != layoutKey,
                                  ),
                                );
                              }
                              setState(
                                () => layoutCache[targetKey] = preparedLayout,
                              );
                            }

                            WidgetsBinding.instance.addPostFrameCallback(
                              prepareNeighbor,
                            );
                          }
                          return null;
                        }
                        target = cached;
                        targetPage = delta > 0 ? 0 : target.pages.length - 1;
                      }
                      Widget column(int index) {
                        if (index >= target.pages.length) {
                          return const SizedBox();
                        }
                        final slice = target.pages[index];
                        return SelectableText.rich(
                          readerSpan(
                            target.text.substring(slice.start, slice.end),
                            style,
                            settings,
                          ),
                          style: style,
                          cursorWidth: 0,
                          enableInteractiveSelection: false,
                          textDirection: TextDirection.ltr,
                          textScaler: MediaQuery.textScalerOf(ctx),
                          textAlign: readerTextAlign(settings),
                        );
                      }

                      return ReaderPage(
                        color: scheme[0],
                        margin: margin,
                        header: header(targetChapter),
                        footer: footer(targetChapter, targetPage, target),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: column(targetPage)),
                            if (doublePage) ...[
                              const SizedBox(width: 32),
                              Expanded(child: column(targetPage + 1)),
                            ],
                          ],
                        ),
                      );
                    }

                    final previousPage = adjacent(-1);
                    final nextPage = adjacent(1);
                    final slice = pages[page];
                    return ReaderTapSurface(
                      canTurn: () =>
                          selected.isEmpty &&
                          !privacyLocked.value &&
                          (!dialogOpen || settingsOpen) &&
                          !shield,
                      onTap: (location) {
                        if (settingsOpen) {
                          toggleSettings();
                          return;
                        }
                        if (selected.isNotEmpty) return;
                        if (location.dx >= box.maxWidth * .3 &&
                            location.dx <= box.maxWidth * .7) {
                          toggleChrome();
                          return;
                        }
                        if (settings.flag('reader.oneHand')) {
                          turn(1);
                        } else if (settings.flag('reader.tapPages', true)) {
                          if (location.dx < box.maxWidth * .3) {
                            turn(-1);
                          } else if (location.dx > box.maxWidth * .7) {
                            turn(1);
                          }
                        }
                      },
                      onHorizontalDragStart: (_) {
                        if (settings.value('reader.animation', 'slide') ==
                                'slide' &&
                            !settings.flag('reader.eink')) {
                          pageSurface.currentState?.beginDrag();
                        }
                      },
                      onHorizontalDragUpdate: (d) => pageSurface.currentState
                          ?.updateDrag(d.primaryDelta ?? 0),
                      onHorizontalDragCancel: () =>
                          pageSurface.currentState?.cancel(),
                      onHorizontalDragEnd: (d) {
                        final surface = pageSurface.currentState;
                        if (settings.value('reader.animation', 'slide') ==
                                'slide' &&
                            !settings.flag('reader.eink')) {
                          unawaited(
                            surface?.endDrag(
                              d.primaryVelocity ?? 0,
                              turnImmediate,
                            ),
                          );
                        } else if ((d.primaryVelocity ?? 0).abs() > 150) {
                          turn(d.primaryVelocity! < 0 ? 1 : -1);
                        }
                      },
                      child: PageTurnSurface(
                        key: pageSurface,
                        color: scheme[0],
                        previous: previousPage,
                        next: nextPage,
                        pageIdentity: '$layoutKey:$page',
                        enabled:
                            !privacyLocked.value &&
                            active &&
                            !shield &&
                            !dialogOpen,
                        child: ReaderPage(
                          color: scheme[0],
                          margin: margin,
                          header: header(chapter),
                          footer: footer(
                            chapter,
                            page,
                            ReadingLayout(text, sourceOffsets, pages),
                          ),
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
                                              key: ValueKey('$layoutKey:$page'),
                                              style: style,
                                              cursorWidth: 0,
                                              textScaler:
                                                  MediaQuery.textScalerOf(ctx),
                                              textDirection: TextDirection.ltr,
                                              textAlign: readerTextAlign(
                                                settings,
                                              ),
                                              onSelectionChanged: (s, cause) {
                                                final visible = text.substring(
                                                  slice.start,
                                                  slice.end,
                                                );
                                                selected =
                                                    s.isValid && !s.isCollapsed
                                                    ? visible.substring(
                                                        s.start.clamp(
                                                          0,
                                                          visible.length,
                                                        ),
                                                        s.end.clamp(
                                                          0,
                                                          visible.length,
                                                        ),
                                                      )
                                                    : '';
                                              },
                                              contextMenuBuilder: (ctx, editable) =>
                                                  AdaptiveTextSelectionToolbar.buttonItems(
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
                                            const SizedBox(width: 32),
                                            Expanded(
                                              child: page + 1 < pages.length
                                                  ? SelectableText.rich(
                                                      readerSpan(
                                                        text.substring(
                                                          pages[page + 1].start,
                                                          pages[page + 1].end,
                                                        ),
                                                        style,
                                                        settings,
                                                      ),
                                                      style: style,
                                                      cursorWidth: 0,
                                                      textDirection:
                                                          TextDirection.ltr,
                                                      textScaler:
                                                          MediaQuery.textScalerOf(
                                                            ctx,
                                                          ),
                                                      textAlign:
                                                          readerTextAlign(
                                                            settings,
                                                          ),
                                                    )
                                                  : const SizedBox(),
                                            ),
                                          ],
                                        ],
                                      ),
                              ),
                              if (!settings.flag('reader.eink') &&
                                  !MediaQuery.disableAnimationsOf(ctx) &&
                                  settings.value('reader.atmosphere', 'none') !=
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
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }
}

/// Fixed touch targets with wrapping labels for small screens and large text.
class ReaderFooter extends StatelessWidget {
  final int page, pages;
  final double progress;
  final Color ink;
  final VoidCallback outline, previous, next;
  const ReaderFooter({
    super.key,
    required this.page,
    required this.pages,
    required this.progress,
    required this.ink,
    required this.outline,
    required this.previous,
    required this.next,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
    child: Row(
      children: [
        IconButton(
          tooltip: '章节目录',
          onPressed: outline,
          icon: const ShuyeIcon(Icons.format_list_bulleted, size: 22),
        ),
        Expanded(
          child: Row(
            children: [
              IconButton(
                tooltip: '上一页',
                onPressed: previous,
                icon: const ShuyeIcon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  '$page / $pages 页',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: ink),
                ),
              ),
              IconButton(
                tooltip: '下一页',
                onPressed: next,
                icon: const ShuyeIcon(Icons.chevron_right),
              ),
            ],
          ),
        ),
        SizedBox(
          width: 48,
          child: Text(
            '${(progress * 100).round()}%',
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 11, color: ink),
          ),
        ),
      ],
    ),
  );
}
