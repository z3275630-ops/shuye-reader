import 'form_field.dart';
import 'appearance.dart';

import 'dart:math';

import 'package:flutter/material.dart';

import 'models.dart';
import 'services.dart';
import 'workbench.dart';

TextSpan readerSpan(String text, TextStyle style, ReaderSettings? settings) {
  if (settings == null ||
      (!settings.flag('reader.bionic') &&
          settings.value('reader.highlights', '').isEmpty)) {
    return TextSpan(text: text, style: style);
  }
  final keywords = settings
      .value('reader.highlights', '')
      .split('\n')
      .where((s) => s.isNotEmpty)
      .take(30)
      .toList();
  final spans = <TextSpan>[];
  var at = 0;
  final regex = RegExp(
    r'[a-zA-Z]{2,}|' +
        (keywords.isEmpty ? r'(?!)' : keywords.map(RegExp.escape).join('|')),
  );
  for (final m in regex.allMatches(text)) {
    if (m.start > at) spans.add(TextSpan(text: text.substring(at, m.start)));
    final word = m[0]!;
    if (keywords.contains(word)) {
      spans.add(
        TextSpan(
          text: word,
          style: const TextStyle(backgroundColor: Color(0x668aac73)),
        ),
      );
    } else if (settings.flag('reader.bionic')) {
      final n = (word.length * .45).ceil();
      spans.add(
        TextSpan(
          text: word.substring(0, n),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      );
      spans.add(TextSpan(text: word.substring(n)));
    } else {
      spans.add(TextSpan(text: word));
    }
    at = m.end;
  }
  if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
  return TextSpan(style: style, children: spans);
}

Future<void> advancedReaderSettings(
  BuildContext context,
  ReaderSettings s,
  VoidCallback changed,
) async {
  await showModalBottomSheet<void>(
    context: context,
    sheetAnimationStyle: applicationMotion(context),
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => StatefulBuilder(
      builder: (c, set) {
        void update(String key, dynamic value) {
          set(() => s.extra[key] = value);
          changed();
          unawaitedConfigure(s);
        }

        Widget toggle(String key, String title, {bool fallback = false}) =>
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(title),
              subtitle: switch (key) {
                'reader.hyphenation' => const Text('英文长词在行尾按音节换行'),
                'reader.bionic' => const Text('突出英文单词开头，帮助快速扫读'),
                'reader.punctuation' => const Text('字体支持时，缩小标点占用的空间'),
                'reader.eink' => const Text('适用于墨水屏；纸色与文字使用黑白'),
                'reader.doublePage' => const Text('宽屏时并排显示两页'),
                _ => null,
              },
              value: s.flag(key, fallback),
              onChanged: (v) => update(key, v),
            );
        Widget slider(
          String key,
          String title,
          double low,
          double high,
          double fallback,
        ) => SettingSlider(
          title: title,
          displayValue: s.number(key, fallback).toStringAsFixed(1),
          value: s.number(key, fallback).clamp(low, high),
          min: low,
          max: high,
          onChanged: (v) => update(key, v),
        );
        Widget menu(
          String key,
          String title,
          Map<String, String> values,
          String fallback,
        ) => LabeledField(
          label: title,
          child: DropdownButtonFormField<String>(
            initialValue: values.containsKey(s.value(key, fallback))
                ? s.value(key, fallback)
                : fallback,
            decoration: InputDecoration(),
            items: [
              for (final e in values.entries)
                DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
            onChanged: (v) => update(key, v),
          ),
        );
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(c).height * .82,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [
                const Text('阅读控制', style: ShuyeStyle.panelTitle),
                SettingsSection(
                  title: '翻页与屏幕',
                  children: [
                    menu('reader.animation', '翻页效果', {
                      'none': '即时',
                      'slide': '平移翻页',
                      'fade': '淡入翻页',
                      'curl': '纸张卷页',
                    }, 'slide'),
                    const SizedBox(height: 12),
                    menu('reader.orientation', '屏幕方向', {
                      'auto': '跟随系统',
                      'portrait': '竖屏',
                      'landscape': '横屏',
                    }, 'auto'),
                    toggle('reader.keepOn', '阅读时保持屏幕亮起', fallback: true),
                    toggle('reader.volumeKeys', '音量键翻页'),
                    toggle(
                      'reader.physicalKeys',
                      '键盘方向键、空格与翻页键',
                      fallback: true,
                    ),
                    toggle('reader.sound', '翻页时播放系统点击声'),
                    toggle('reader.oneHand', '单手点击：点正文即可下一页'),
                    toggle('reader.tapPages', '点击正文左右侧翻页', fallback: true),
                    toggle('reader.doublePage', '宽屏双页阅读'),
                    toggle('reader.eink', '墨水屏：高对比度、关闭动画'),
                  ],
                ),
                SettingsSection(
                  title: '排版与纸色',
                  children: [
                    toggle('reader.ignoreBlank', '忽略空段'),
                    toggle('reader.bionic', '英文首字母加粗'),
                    toggle('reader.hyphenation', '英文按音节断词'),
                    menu('reader.chinese', '中文显示', {
                      'none': '保留原文',
                      'simplified': '简体',
                      'traditional': '繁體',
                    }, 'none'),
                    toggle('reader.punctuation', '字体支持时压缩标点'),
                    toggle('reader.nightSchedule', '每日 20:00–06:00 自动夜读'),
                    slider('reader.margin', '左右页边距', 12, 48, 28),
                    slider('reader.brightness', '阅读亮度（负值跟随系统）', -1, 1, -1),
                  ],
                ),
                SettingsSection(
                  title: '自动阅读与提醒',
                  children: [
                    slider('reader.autoInterval', '自动翻页间隔（秒）', 3, 120, 15),
                    menu('reader.autoMode', '自动翻页计算方式', {
                      'interval': '固定间隔',
                      'speed': '按本页字数',
                    }, 'interval'),
                    slider('reader.charsPerSecond', '每秒阅读字数', 3, 30, 10),
                    slider(
                      'reader.reminderMinutes',
                      '阅读休息提醒（分钟；0 为关闭）',
                      0,
                      90,
                      30,
                    ),
                    slider('reader.speechRate', '听书语速', .5, 2, 1),
                  ],
                ),
                SettingsSection(
                  title: '氛围与个性设置',
                  children: [
                    menu('reader.atmosphere', '阅读氛围', {
                      'none': '关闭',
                      'rain': '细雨',
                      'snow': '轻雪',
                    }, 'none'),
                    ListTile(
                      title: const Text('自动高亮词语'),
                      subtitle: const Text('每行一个词，最多 30 个'),
                      onTap: () async {
                        final data = await editFields(c, '高亮词语', {
                          '正文': s.value('reader.highlights', ''),
                        });
                        if (c.mounted && data != null) {
                          update('reader.highlights', data['正文']);
                        }
                      },
                    ),
                    ListTile(
                      title: const Text('自定义纸色与文字颜色'),
                      subtitle: const Text('十六进制颜色，例如 F4EDDF、3F392E'),
                      onTap: () async {
                        String? validateColor(String value) =>
                            value.isEmpty ||
                                RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(value)
                            ? null
                            : '请输入 6 位颜色，例如 F4EDDF；留空恢复默认。';
                        final data = await editFields(
                          c,
                          '自定义主题',
                          {
                            '纸色': s.value('reader.background', ''),
                            '文字': s.value('reader.foreground', ''),
                          },
                          validators: {
                            '纸色': validateColor,
                            '文字': validateColor,
                          },
                        );
                        if (!c.mounted || data == null) return;
                        update('reader.background', data['纸色']);
                        update('reader.foreground', data['文字']);
                      },
                    ),
                    ListTile(
                      title: const Text('使用系统字体'),
                      onTap: () {
                        s.extra.remove('reader.customFont');
                        changed();
                        set(() {});
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => Navigator.pop(c),
                  child: const Text('完成'),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

void unawaitedConfigure(ReaderSettings s) {
  if (DeviceReader.reading) DeviceReader.configure(s);
}

class Atmosphere extends StatefulWidget {
  final String kind;
  const Atmosphere({super.key, required this.kind});
  @override
  State<Atmosphere> createState() => _AtmosphereState();
}

class _AtmosphereState extends State<Atmosphere>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  )..repeat();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: AnimatedBuilder(
      animation: controller,
      builder: (c, w) => CustomPaint(
        painter: WeatherPainter(controller.value, widget.kind),
        size: Size.infinite,
      ),
    ),
  );
}

class WeatherPainter extends CustomPainter {
  final double time;
  final String kind;
  WeatherPainter(this.time, this.kind);
  @override
  void paint(Canvas c, Size size) {
    final random = Random(21);
    final paint = Paint()
      ..color = const Color(0x22697773)
      ..strokeWidth = .7;
    for (var i = 0; i < 45; i++) {
      final x = random.nextDouble() * size.width;
      final y = (random.nextDouble() + time) % 1 * size.height;
      if (kind == 'rain') {
        c.drawLine(Offset(x, y), Offset(x - 2, y + 12), paint);
      } else {
        c.drawCircle(Offset(x + sin(time * 6 + i) * 5, y), 1.5, paint);
      }
    }
  }

  @override
  bool shouldRepaint(WeatherPainter old) =>
      old.time != time || old.kind != kind;
}
