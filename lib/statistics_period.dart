import 'app_icons.dart';

import 'package:flutter/material.dart';

import 'home_dashboard.dart';

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
  ReadingPeriod period = ReadingPeriod.month;
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
    final colors = Theme.of(context).colorScheme;
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
                    style: const TextStyle(fontWeight: FontWeight.w600),
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
                Text(
                  '阅读 ${total ~/ 60} 分钟',
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
            if (buckets.isNotEmpty) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final bucket in buckets)
                    Tooltip(
                      message:
                          '${period == ReadingPeriod.year ? '${bucket.$1.month} 月' : dayKey(bucket.$1)} · ${bucket.$2 ~/ 60} 分钟',
                      child: Container(
                        width: 36,
                        height: 48,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: bucket.$2 > 0
                              ? colors.primaryContainer
                              : colors.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${period == ReadingPeriod.year ? bucket.$1.month : bucket.$1.day}',
                              style: const TextStyle(fontSize: 11),
                            ),
                            Text(
                              '${bucket.$2 ~/ 60}分',
                              style: TextStyle(
                                fontSize: 9,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              const Text('长按方格查看时长，空白日期不预填数据。', style: TextStyle(fontSize: 11)),
            ],
          ],
        ),
      ),
    );
  }
}
