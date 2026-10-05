import 'app_icons.dart';

import 'package:flutter/material.dart';

import 'home_dashboard.dart';

// Construct natural dates rather than subtracting 24-hour durations (DST).
List<(DateTime, int)> recentReadingDays(Map<String, int> stats, DateTime now) =>
    List.generate(7, (i) {
      final date = DateTime(now.year, now.month, now.day - 6 + i);
      return (date, (stats[dayKey(date)] ?? 0).clamp(0, 1 << 53));
    });

class RecentReadingTrend extends StatefulWidget {
  final Map<String, int> stats;
  final DateTime? today;
  const RecentReadingTrend({super.key, required this.stats, this.today});
  @override
  State<RecentReadingTrend> createState() => _RecentReadingTrendState();
}

class _RecentReadingTrendState extends State<RecentReadingTrend> {
  String? selected;
  String duration(int seconds) => seconds == 0
      ? '无阅读记录'
      : seconds < 60
      ? '$seconds 秒'
      : '${seconds ~/ 60} 分钟';
  @override
  Widget build(BuildContext context) {
    final days = recentReadingDays(
      widget.stats,
      widget.today ?? DateTime.now(),
    );
    final maximum = days.fold<int>(
      0,
      (value, day) => value > day.$2 ? value : day.$2,
    );
    final chosen =
        days.where((d) => dayKey(d.$1) == selected).firstOrNull ?? days.last;
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('近七天', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              '柱高表示阅读时长，点按查看当天记录。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                for (final day in days)
                  Expanded(
                    child: Semantics(
                      button: true,
                      selected: day == chosen,
                      label: '${dayKey(day.$1)}，${duration(day.$2)}',
                      child: InkWell(
                        key: ValueKey('recent-day-${dayKey(day.$1)}'),
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => setState(() => selected = dayKey(day.$1)),
                        child: ExcludeSemantics(
                          child: Column(
                            children: [
                              SizedBox(
                                height: 72,
                                child: Align(
                                  alignment: Alignment.bottomCenter,
                                  child: FractionallySizedBox(
                                    widthFactor: .5,
                                    child: Container(
                                      height: day.$2 == 0
                                          ? 3
                                          : (72 * day.$2 / maximum).clamp(
                                              3,
                                              72,
                                            ),
                                      decoration: BoxDecoration(
                                        color: day.$2 == 0
                                            ? colors.outlineVariant
                                            : day == chosen
                                            ? colors.primary
                                            : colors.onSurfaceVariant,
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                day == days.last
                                    ? '今'
                                    : '一二三四五六日'[day.$1.weekday - 1],
                                style: TextStyle(
                                  fontSize: 12,
                                  color: day == chosen
                                      ? colors.primary
                                      : colors.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${dayKey(chosen.$1)} · ${duration(chosen.$2)}',
              key: const ValueKey('recent-day-detail'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

enum ReadingPeriod { day, week, month, year, all }

(DateTime, DateTime) periodBounds(ReadingPeriod period, DateTime anchor) {
  final day = DateTime(anchor.year, anchor.month, anchor.day);
  return switch (period) {
    ReadingPeriod.day => (day, DateTime(day.year, day.month, day.day + 1)),
    ReadingPeriod.week => (
      DateTime(day.year, day.month, day.day - day.weekday + 1),
      DateTime(day.year, day.month, day.day + 8 - day.weekday),
    ),
    ReadingPeriod.month => (
      DateTime(day.year, day.month),
      DateTime(day.year, day.month + 1),
    ),
    ReadingPeriod.year => (DateTime(day.year), DateTime(day.year + 1)),
    ReadingPeriod.all => (DateTime(1970), DateTime(9999)),
  };
}

Map<String, int> statsInPeriod(
  Map<String, int> stats,
  ReadingPeriod period,
  DateTime anchor,
) {
  if (period == ReadingPeriod.all) return Map.of(stats);
  final (start, end) = periodBounds(period, anchor);
  return {
    for (final entry in stats.entries)
      if (entry.key.compareTo(dayKey(start)) >= 0 &&
          entry.key.compareTo(dayKey(end)) < 0)
        entry.key: entry.value,
  };
}

class PeriodStatistics extends StatefulWidget {
  final Map<String, int> stats;
  const PeriodStatistics({super.key, required this.stats});
  @override
  State<PeriodStatistics> createState() => _PeriodStatisticsState();
}

class _PeriodStatisticsState extends State<PeriodStatistics> {
  ReadingPeriod period = ReadingPeriod.week;
  DateTime anchor = DateTime.now();
  DateTime shift(int direction) => switch (period) {
    ReadingPeriod.day => DateTime(
      anchor.year,
      anchor.month,
      anchor.day + direction,
    ),
    ReadingPeriod.week => DateTime(
      anchor.year,
      anchor.month,
      anchor.day + 7 * direction,
    ),
    ReadingPeriod.month => DateTime(anchor.year, anchor.month + direction),
    ReadingPeriod.year => DateTime(anchor.year + direction),
    _ => anchor,
  };
  @override
  Widget build(BuildContext context) {
    final (start, end) = periodBounds(period, anchor);
    final selected = statsInPeriod(widget.stats, period, anchor);
    final total = selected.values.fold<int>(0, (a, b) => a + b);
    final active = selected.values.where((v) => v > 0).length;
    final now = DateTime.now();
    final forward = periodBounds(period, shift(1)).$1.isAfter(now);
    final label = switch (period) {
      ReadingPeriod.day => dayKey(start),
      ReadingPeriod.week =>
        '${dayKey(start)} — ${dayKey(DateTime(end.year, end.month, end.day - 1))}',
      ReadingPeriod.month => '${anchor.year} 年 ${anchor.month} 月',
      ReadingPeriod.year => '${anchor.year} 年',
      _ => '全部阅读记录',
    };
    final bucketCount = period == ReadingPeriod.year
        ? 12
        : period == ReadingPeriod.week
        ? 7
        : period == ReadingPeriod.month
        ? DateTime(anchor.year, anchor.month + 1, 0).day
        : 0;
    final buckets = List.generate(bucketCount, (i) {
      final date = period == ReadingPeriod.year
          ? DateTime(anchor.year, i + 1)
          : DateTime(start.year, start.month, start.day + i);
      final rows = period == ReadingPeriod.year
          ? statsInPeriod(widget.stats, ReadingPeriod.month, date)
          : {dayKey(date): widget.stats[dayKey(date)] ?? 0};
      return (date, rows.values.fold<int>(0, (a, b) => a + b));
    });
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('阅读时长', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final p in ReadingPeriod.values)
                  ChoiceChip(
                    label: Text(['日', '周', '月', '年', '全部'][p.index]),
                    selected: period == p,
                    onSelected: (_) => setState(() {
                      period = p;
                      anchor = DateTime.now();
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (period != ReadingPeriod.all)
                  IconButton(
                    tooltip: '上一时段',
                    onPressed: () => setState(() => anchor = shift(-1)),
                    icon: const ShuyeIcon(Icons.chevron_left),
                  ),
                Expanded(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w400),
                  ),
                ),
                if (period != ReadingPeriod.all)
                  IconButton(
                    tooltip: '下一时段',
                    onPressed: forward
                        ? null
                        : () => setState(() => anchor = shift(1)),
                    icon: const ShuyeIcon(Icons.chevron_right),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 24,
              runSpacing: 12,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: total > 0 && total < 60
                            ? '少于1'
                            : '${total ~/ 60}',
                        style: Theme.of(context).textTheme.headlineLarge,
                      ),
                      const TextSpan(text: ' 分钟'),
                    ],
                  ),
                  key: const ValueKey('period-total'),
                ),
                Text('阅读 $active 天', key: const ValueKey('period-days')),
              ],
            ),
            if (total == 0)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('这个时段还没有阅读记录。'),
              ),
            if (buckets.isNotEmpty && total > 0) ...[
              const SizedBox(height: 16),
              ReadingDurationChart(
                values: [for (final b in buckets) b.$2],
                labels: [
                  for (final b in buckets)
                    period == ReadingPeriod.week
                        ? [
                            '周一',
                            '周二',
                            '周三',
                            '周四',
                            '周五',
                            '周六',
                            '周日',
                          ][b.$1.weekday - 1]
                        : period == ReadingPeriod.year
                        ? '${b.$1.month}月'
                        : '${b.$1.day}日',
                ],
                details: [
                  for (final b in buckets)
                    period == ReadingPeriod.year
                        ? '${b.$1.year}年${b.$1.month}月'
                        : dayKey(b.$1),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Actual seconds only; zeros stay on the baseline, never fabricated bars.
class ReadingDurationChart extends StatefulWidget {
  final List<int> values;
  final List<String> labels, details;
  const ReadingDurationChart({
    super.key,
    required this.values,
    required this.labels,
    required this.details,
  });
  @override
  State<ReadingDurationChart> createState() => _ReadingDurationChartState();
}

class _ReadingDurationChartState extends State<ReadingDurationChart> {
  int? selected;
  @override
  void didUpdateWidget(ReadingDurationChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.details.join() != widget.details.join()) selected = null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final maximum = widget.values.fold<int>(1, (a, b) => a > b ? a : b);
    String duration(int seconds) =>
        seconds < 60 ? '$seconds 秒' : '${seconds ~/ 60} 分钟';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '单位：分钟 · 最高 ${duration(maximum)}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: (widget.values.length * 32.0).clamp(
                box.maxWidth,
                double.infinity,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < widget.values.length; i++)
                    Expanded(
                      child: Semantics(
                        button: true,
                        selected: selected == i,
                        label:
                            '${widget.details[i]}，${duration(widget.values[i])}',
                        child: InkWell(
                          key: ValueKey('duration-bar-$i'),
                          onTap: () => setState(() => selected = i),
                          child: Column(
                            children: [
                              SizedBox(
                                height: 100,
                                child: Align(
                                  alignment: Alignment.bottomCenter,
                                  child: FractionallySizedBox(
                                    widthFactor: .55,
                                    child: Container(
                                      height: widget.values[i] == 0
                                          ? 1
                                          : (100.0 * widget.values[i] / maximum)
                                                .clamp(3, 100),
                                      decoration: BoxDecoration(
                                        color: widget.values[i] == 0
                                            ? colors.outlineVariant
                                            : colors.primary,
                                        borderRadius:
                                            const BorderRadius.vertical(
                                              top: Radius.circular(3),
                                            ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                widget.labels[i],
                                style: Theme.of(context).textTheme.bodySmall,
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          selected == null
              ? '点按柱形查看时长；左右滑动查看完整日期。'
              : '${widget.details[selected!]} · ${duration(widget.values[selected!])}',
          key: const ValueKey('duration-detail'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
