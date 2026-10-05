import 'app_icons.dart';

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'home_dashboard.dart';

enum HeatmapSpan { month, halfYear, year }

const heatmapWeekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
const heatmapLevels = [
  '未阅读',
  '不足 5 分钟',
  '5–15 分钟',
  '15–30 分钟',
  '30–60 分钟',
  '1–2 小时',
  '2 小时及以上',
];

int readingHeatLevel(int seconds) {
  if (seconds <= 0) return 0;
  if (seconds < 300) return 1;
  if (seconds < 900) return 2;
  if (seconds < 1800) return 3;
  if (seconds < 3600) return 4;
  if (seconds < 7200) return 5;
  return 6;
}

String readingDuration(int seconds) {
  if (seconds <= 0) return '未阅读';
  if (seconds < 60) return '$seconds 秒';
  final minutes = seconds ~/ 60;
  return minutes < 60
      ? '$minutes 分钟'
      : '${minutes ~/ 60} 小时${minutes % 60 == 0 ? '' : ' ${minutes % 60} 分钟'}';
}

String compactReadingDuration(int seconds) {
  if (seconds < 60) return seconds > 0 ? '$seconds 秒' : '0 分钟';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '$minutes 分钟';
  return '${minutes ~/ 60}时${minutes % 60}分';
}

DateTime _date(DateTime d) => DateTime(d.year, d.month, d.day);
int _daysBetween(DateTime a, DateTime b) => DateTime.utc(
  b.year,
  b.month,
  b.day,
).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

class ReadingHeatmapData {
  final DateTime start, end, today, gridStart;
  final Map<String, int> stats;
  ReadingHeatmapData({
    required DateTime start,
    required DateTime end,
    required DateTime today,
    required this.stats,
  }) : start = _date(start),
       end = _date(end),
       today = _date(today),
       gridStart = DateTime(
         start.year,
         start.month,
         start.day - start.weekday + 1,
       );

  factory ReadingHeatmapData.forSpan(
    HeatmapSpan span,
    DateTime now,
    Map<String, int> stats, {
    int? year,
    int? month,
  }) {
    final day = _date(now);
    return ReadingHeatmapData(
      start: switch (span) {
        HeatmapSpan.month => DateTime(year ?? day.year, month ?? day.month),
        HeatmapSpan.year => DateTime(year ?? day.year),
        HeatmapSpan.halfYear => DateTime(day.year, day.month, day.day - 181),
      },
      end: switch (span) {
        HeatmapSpan.month => DateTime(
          year ?? day.year,
          (month ?? day.month) + 1,
        ),
        HeatmapSpan.year => DateTime((year ?? day.year) + 1),
        HeatmapSpan.halfYear => DateTime(day.year, day.month, day.day + 1),
      },
      today: day,
      stats: stats,
    );
  }
  int get columns => (_daysBetween(gridStart, end) / 7).ceil();
  DateTime dateAt(int column, int row) => DateTime(
    gridStart.year,
    gridStart.month,
    gridStart.day + column * 7 + row,
  );
  bool contains(DateTime d) => !d.isBefore(start) && d.isBefore(end);
  bool isFuture(DateTime d) => d.isAfter(today);
  int seconds(DateTime d) =>
      contains(d) && !isFuture(d) ? math.max(0, stats[dayKey(d)] ?? 0) : 0;
  Iterable<DateTime> get elapsedDays sync* {
    for (
      var d = start;
      d.isBefore(end) && !isFuture(d);
      d = DateTime(d.year, d.month, d.day + 1)
    ) {
      yield d;
    }
  }

  ({int total, int active, int longest}) get summary {
    var total = 0, active = 0, longest = 0, streak = 0;
    for (final day in elapsedDays) {
      final value = seconds(day);
      total += value;
      if (value > 0) {
        active++;
        streak++;
        longest = math.max(longest, streak);
      } else {
        streak = 0;
      }
    }
    return (total: total, active: active, longest: longest);
  }
}

class ReadingHeatmap extends StatefulWidget {
  final Map<String, int> stats;
  final DateTime? now;
  const ReadingHeatmap({super.key, required this.stats, this.now});
  @override
  State<ReadingHeatmap> createState() => _ReadingHeatmapState();
}

class _ReadingHeatmapState extends State<ReadingHeatmap> {
  final scroll = ScrollController();
  HeatmapSpan span = HeatmapSpan.month;
  late int year, month;
  late DateTime selected;
  bool positionChart = true;
  bool snapping = false;
  double? lastPitch;
  DateTime get now => _date(widget.now ?? DateTime.now());
  @override
  void initState() {
    super.initState();
    year = now.year;
    month = now.month;
    selected = now;
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  void change(HeatmapSpan next, [int? nextYear, int? nextMonth]) {
    setState(() {
      span = next;
      year = nextYear ?? now.year;
      month = nextMonth ?? now.month;
      final last = next == HeatmapSpan.year
          ? DateTime(year, 12, 31)
          : DateTime(year, month + 1, 0);
      selected = next == HeatmapSpan.halfYear || last.isAfter(now) ? now : last;
      positionChart = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final palette = dark
        ? const [
            Color(0xff303c36),
            Color(0xff3b5745),
            Color(0xff4f7758),
            Color(0xff659364),
            Color(0xff82b476),
            Color(0xffa2ce8e),
            Color(0xffc5e7ab),
          ]
        : const [
            Color(0xffeaf0e9),
            Color(0xffd2e5bc),
            Color(0xffafcf8f),
            Color(0xff80ac65),
            Color(0xff598946),
            Color(0xff396a35),
            Color(0xff214b29),
          ];
    final data = ReadingHeatmapData.forSpan(
      span,
      now,
      widget.stats,
      year: year,
      month: month,
    );
    final summary = data.summary;
    final scale = MediaQuery.textScalerOf(context);
    final labelScale = TextScaler.linear(scale.scale(1).clamp(1, 1.5));
    final range = switch (span) {
      HeatmapSpan.month => '$year 年 $month 月',
      HeatmapSpan.year => '$year 年',
      HeatmapSpan.halfYear =>
        '${data.start.year}.${data.start.month}.${data.start.day} — ${now.year}.${now.month}.${now.day}',
    };
    final previous = span == HeatmapSpan.month
        ? DateTime(year, month - 1)
        : DateTime(year - 1, month);
    final next = span == HeatmapSpan.month
        ? DateTime(year, month + 1)
        : DateTime(year + 1, month);
    final canGoBack = !previous.isBefore(DateTime(1970));
    final canGoForward = span == HeatmapSpan.month
        ? !next.isAfter(DateTime(now.year, now.month))
        : next.year <= now.year;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ShuyeIcon(
                  Icons.grid_view_rounded,
                  size: 20,
                  color: colors.primary,
                ),
                const SizedBox(width: 9),
                Flexible(
                  child: Text(
                    '阅读热力图',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Center(
              child: Text(
                '让每一天的阅读，都留下颜色。',
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
              ),
            ),
            const SizedBox(height: 14),
            Center(
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final option in {
                    HeatmapSpan.month: '本月',
                    HeatmapSpan.halfYear: '半年',
                    HeatmapSpan.year: '全年',
                  }.entries)
                    ChoiceChip(
                      label: Text(option.value),
                      selected: span == option.key,
                      onSelected: (_) => change(option.key),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                if (span != HeatmapSpan.halfYear)
                  IconButton(
                    tooltip: span == HeatmapSpan.month ? '上一月' : '上一年',
                    onPressed: canGoBack
                        ? () => change(span, previous.year, previous.month)
                        : null,
                    icon: const ShuyeIcon(Icons.chevron_left),
                  ),
                Expanded(
                  child: Text(
                    range,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
                if (span != HeatmapSpan.halfYear)
                  IconButton(
                    tooltip: span == HeatmapSpan.month ? '下一月' : '下一年',
                    onPressed: canGoForward
                        ? () => change(span, next.year, next.month)
                        : null,
                    icon: const ShuyeIcon(Icons.chevron_right),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (span == HeatmapSpan.month)
              _monthChart(data, palette, labelScale, colors)
            else
              _weekChart(data, palette, labelScale, colors),
            const SizedBox(height: 14),
            Center(
              child: Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 4,
                runSpacing: 6,
                children: [
                  Text(
                    '少',
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  for (var i = 0; i < palette.length; i++)
                    Tooltip(
                      message: heatmapLevels[i],
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: palette[i],
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  Text(
                    '多',
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  IconButton(
                    tooltip: '颜色说明',
                    visualDensity: VisualDensity.compact,
                    icon: const ShuyeIcon(Icons.info_outline, size: 16),
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text('颜色与阅读时长'),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (var i = 0; i < palette.length; i++)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 5,
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 16,
                                      height: 16,
                                      decoration: BoxDecoration(
                                        color: palette[i],
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(child: Text(heatmapLevels[i])),
                                  ],
                                ),
                              ),
                            const SizedBox(height: 10),
                            const Text(
                              '本月的浅淡格、全年的斜线空心格表示未来日期，不计入统计。',
                              style: TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(c),
                            child: const Text('知道了'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Semantics(
                liveRegion: true,
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    Text(
                      '${selected.year}.${selected.month}.${selected.day} ${heatmapWeekdays[selected.weekday - 1]}',
                      key: const ValueKey('heatmap-selected-date'),
                      style: const TextStyle(fontSize: 13),
                    ),
                    Text(
                      readingDuration(data.seconds(selected)),
                      key: const ValueKey('heatmap-selected-duration'),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) => Wrap(
                spacing: 10,
                runSpacing: 12,
                children: [
                  for (final item in [
                    ('阅读时长', compactReadingDuration(summary.total)),
                    ('阅读天数', '${summary.active} 天'),
                    ('最长连续', '${summary.longest} 天'),
                  ])
                    SizedBox(
                      width: (constraints.maxWidth - 20) / 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            item.$2,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            item.$1,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: colors.onSurfaceVariant,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                summary.active == 0
                    ? '开始阅读后，方格会逐渐亮起来。'
                    : span == HeatmapSpan.month
                    ? '点按方格查看日期与时长，用箭头查看往月。'
                    : '点按或长按查看时长，左右滑动查看月份。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: colors.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _monthChart(
    ReadingHeatmapData data,
    List<Color> palette,
    TextScaler labelScale,
    ColorScheme colors,
  ) => Column(
    key: const ValueKey('reading-heatmap-month'),
    children: [
      Row(
        children: [
          for (final weekday in heatmapWeekdays)
            Expanded(
              child: Text(
                weekday,
                textAlign: TextAlign.center,
                textScaler: labelScale,
                style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
              ),
            ),
        ],
      ),
      const SizedBox(height: 8),
      for (var week = 0; week < data.columns; week++)
        Row(
          children: [
            for (var weekday = 0; weekday < 7; weekday++)
              Expanded(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: _monthDay(
                      data.dateAt(week, weekday),
                      data,
                      palette,
                      colors,
                    ),
                  ),
                ),
              ),
          ],
        ),
    ],
  );

  Widget _monthDay(
    DateTime day,
    ReadingHeatmapData data,
    List<Color> palette,
    ColorScheme colors,
  ) {
    if (!data.contains(day)) return const SizedBox.shrink();
    final future = data.isFuture(day);
    final picked = day == selected;
    final fill = palette[readingHeatLevel(data.seconds(day))];
    final foreground = future
        ? colors.onSurfaceVariant.withValues(alpha: .5)
        : fill.computeLuminance() > .45
        ? const Color(0xff203426)
        : Colors.white;
    final description =
        '${dayKey(day)} ${heatmapWeekdays[day.weekday - 1]}，${future ? '未来日期' : readingDuration(data.seconds(day))}';
    return Semantics(
      key: ValueKey('heatmap-day-${dayKey(day)}'),
      label: description,
      button: !future,
      enabled: !future,
      selected: picked,
      child: ExcludeSemantics(
        child: Tooltip(
          message: description,
          excludeFromSemantics: true,
          child: Material(
            color: future ? palette.first.withValues(alpha: .4) : fill,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: picked
                  ? BorderSide(color: colors.onSurface, width: 2)
                  : BorderSide.none,
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: future ? null : () => setState(() => selected = day),
              onLongPress: future ? null : () => setState(() => selected = day),
              child: Stack(
                children: [
                  if (day == data.today)
                    Positioned(
                      bottom: 3,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          width: 3,
                          height: 3,
                          decoration: BoxDecoration(
                            color: foreground,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _weekChart(
    ReadingHeatmapData data,
    List<Color> palette,
    TextScaler labelScale,
    ColorScheme colors,
  ) => LayoutBuilder(
    builder: (context, constraints) {
      final axis = math.max(38.0, labelScale.scale(11) * 2 + 10);
      const gap = 4.0, top = 28.0;
      final viewport = math.max(1.0, constraints.maxWidth - axis);
      final visibleWeeks = math.min(
        data.columns,
        math.max(1, (viewport / 24).floor()),
      );
      final pitch = viewport / visibleWeeks;
      final chartWidth = pitch * data.columns;
      final chartHeight = top + pitch * 7;
      if (positionChart || lastPitch != pitch) {
        positionChart = false;
        lastPitch = pitch;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !scroll.hasClients) return;
          final column = _daysBetween(data.gridStart, selected) ~/ 7;
          scroll.jumpTo(
            ((column - visibleWeeks + 2) * pitch).clamp(
              0.0,
              scroll.position.maxScrollExtent,
            ),
          );
        });
      }
      void pick(Offset point) {
        final column = (point.dx / pitch).floor();
        final row = ((point.dy - top) / pitch).floor();
        if (column < 0 ||
            column >= data.columns ||
            row < 0 ||
            row >= 7 ||
            point.dy < top) {
          return;
        }
        final day = data.dateAt(column, row);
        if (data.contains(day) && !data.isFuture(day)) {
          setState(() => selected = day);
        }
      }

      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: axis,
            child: Column(
              children: [
                const SizedBox(height: top),
                for (final weekday in heatmapWeekdays)
                  SizedBox(
                    height: pitch,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        weekday,
                        textScaler: labelScale,
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: NotificationListener<ScrollEndNotification>(
              onNotification: (notice) {
                if (notice.depth == 0 && !snapping) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted || !scroll.hasClients) return;
                    final target = ((scroll.offset / pitch).round() * pitch)
                        .clamp(0.0, scroll.position.maxScrollExtent);
                    if ((target - scroll.offset).abs() < .1) return;
                    snapping = true;
                    if (MediaQuery.disableAnimationsOf(context)) {
                      scroll.jumpTo(target);
                      snapping = false;
                    } else {
                      scroll
                          .animateTo(
                            target,
                            duration: const Duration(milliseconds: 120),
                            curve: Curves.easeOut,
                          )
                          .whenComplete(() => snapping = false);
                    }
                  });
                }
                return false;
              },
              child: SingleChildScrollView(
                controller: scroll,
                scrollDirection: Axis.horizontal,
                child: GestureDetector(
                  key: const ValueKey('reading-heatmap-chart'),
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) => pick(d.localPosition),
                  onLongPressStart: (d) => pick(d.localPosition),
                  onLongPressMoveUpdate: (d) => pick(d.localPosition),
                  child: CustomPaint(
                    size: Size(chartWidth, chartHeight),
                    painter: ReadingHeatmapPainter(
                      data: data,
                      controller: scroll,
                      viewportWidth: viewport,
                      selected: selected,
                      pitch: pitch,
                      rowPitch: pitch,
                      top: top,
                      gap: gap,
                      palette: palette,
                      foreground: colors.onSurface,
                      muted: colors.onSurfaceVariant,
                      future: colors.outlineVariant,
                      textScaler: labelScale,
                      select: (d) => setState(() => selected = d),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

class ReadingHeatmapPainter extends CustomPainter {
  final ReadingHeatmapData data;
  final DateTime selected;
  final double pitch, rowPitch, top, gap;
  final List<Color> palette;
  final Color foreground, muted, future;
  final TextScaler textScaler;
  final ScrollController controller;
  final double viewportWidth;
  final ValueChanged<DateTime> select;
  ReadingHeatmapPainter({
    required this.data,
    required this.controller,
    required this.viewportWidth,
    required this.selected,
    required this.pitch,
    required this.rowPitch,
    required this.top,
    required this.gap,
    required this.palette,
    required this.foreground,
    required this.muted,
    required this.future,
    required this.textScaler,
    required this.select,
  }) : super(repaint: controller);

  Rect cell(int c, int r) => Rect.fromLTWH(
    c * pitch + gap / 2,
    top + r * rowPitch + (rowPitch - pitch + gap) / 2,
    pitch - gap,
    pitch - gap,
  );

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint();
    var previousMonth = -1;
    final offset = controller.hasClients ? controller.offset : 0.0;
    final firstVisible = (offset / pitch).ceil();
    var lastLabelRight = offset;
    for (var c = 0; c < data.columns; c++) {
      final dates = [for (var r = 0; r < 7; r++) data.dateAt(c, r)]
          .where(data.contains)
          .toList();
      if (dates.isNotEmpty) {
        final month = dates.last.month;
        if (month != previousMonth || c == firstVisible) {
          previousMonth = month;
          final label = TextPainter(
            text: TextSpan(
              text: '$month月',
              style: TextStyle(
                fontSize: 11,
                color: muted,
                fontFamily: 'Roboto',
              ),
            ),
            textDirection: TextDirection.ltr,
            textScaler: textScaler,
          )..layout();
          final x = math.min(
            math.max(c * pitch + gap / 2, offset + gap / 2),
            offset + viewportWidth - label.width - gap / 2,
          );
          // Never display a clipped half-character at either viewport edge.
          if (c >= firstVisible &&
              c * pitch < offset + viewportWidth &&
              x >= lastLabelRight &&
              x + label.width <= offset + viewportWidth) {
            label.paint(canvas, Offset(x, 0));
            lastLabelRight = x + label.width + 8;
          }
          label.dispose();
        }
      }
      for (var r = 0; r < 7; r++) {
        final day = data.dateAt(c, r);
        if (!data.contains(day)) continue;
        final rect = cell(c, r);
        // During dragging, omit edge fragments; settled positions snap to weeks.
        if (rect.left < offset - .1 ||
            rect.right > offset + viewportWidth + .1) {
          continue;
        }
        final rounded = RRect.fromRectAndRadius(
          rect,
          const Radius.circular(2.5),
        );
        if (data.isFuture(day)) {
          // An outlined, unfilled cell separates future days from elapsed zeros.
          final pen = Paint()
            ..color = future
            ..style = PaintingStyle.stroke
            ..strokeWidth = .8;
          canvas.drawRRect(rounded, pen);
          canvas.drawLine(
            rect.topLeft + const Offset(2, 2),
            rect.bottomRight - const Offset(2, 2),
            pen,
          );
        } else {
          fill.color = palette[readingHeatLevel(data.seconds(day))];
          canvas.drawRRect(rounded, fill);
          if (day == selected || day == data.today) {
            canvas.drawRRect(
              rounded.inflate(1),
              Paint()
                ..color = foreground.withValues(
                  alpha: day == selected ? .9 : .45,
                )
                ..style = PaintingStyle.stroke
                ..strokeWidth = day == selected ? 1.5 : .8,
            );
          }
        }
      }
    }
  }

  @override
  SemanticsBuilderCallback get semanticsBuilder =>
      (size) => [
        for (var c = 0; c < data.columns; c++)
          for (var r = 0; r < 7; r++)
            if (data.contains(data.dateAt(c, r)) &&
                !data.isFuture(data.dateAt(c, r)))
              CustomPainterSemantics(
                rect: cell(c, r),
                properties: SemanticsProperties(
                  label:
                      '${dayKey(data.dateAt(c, r))} ${heatmapWeekdays[r]}，${readingDuration(data.seconds(data.dateAt(c, r)))}',
                  textDirection: TextDirection.ltr,
                  button: true,
                  selected: data.dateAt(c, r) == selected,
                  onTap: () => select(data.dateAt(c, r)),
                ),
              ),
      ];
  @override
  bool shouldRepaint(covariant ReadingHeatmapPainter oldDelegate) => true;
  @override
  bool shouldRebuildSemantics(covariant ReadingHeatmapPainter oldDelegate) =>
      true;
}
