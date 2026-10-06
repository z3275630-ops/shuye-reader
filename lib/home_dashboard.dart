import 'app_icons.dart';

import 'package:flutter/material.dart';

import 'models.dart';
import 'appearance.dart';
import 'branding.dart';

const homeSections = {
  'continue': '继续阅读',
  'goal': '今日目标',
  'overview': '阅读概览',
  'recommend': '今日选读',
};
List<String> visibleHomeSections(ReaderSettings s) {
  if (!s.extra.containsKey('home.sections')) return homeSections.keys.toList();
  return s
      .value('home.sections', '')
      .split(',')
      .where(homeSections.containsKey)
      .toSet()
      .toList();
}

String dayKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class HomeDashboard extends StatelessWidget {
  final List<Book> books;
  final Map<String, int> stats;
  final int notes;
  final ReaderSettings settings;
  final Widget Function(Book) cover;
  final Future<void> Function(Book) open;
  final VoidCallback shelf, tools, statistics, goal;
  const HomeDashboard({
    super.key,
    required this.books,
    required this.stats,
    required this.notes,
    required this.settings,
    required this.cover,
    required this.open,
    required this.shelf,
    required this.tools,
    required this.statistics,
    required this.goal,
  });
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final seconds = stats[dayKey(now)] ?? 0;
    final target = settings
        .number('stats.goalMinutes', 20)
        .round()
        .clamp(5, 240);
    final progress = (seconds / (target * 60)).clamp(0.0, 1.0);
    final recent = books.where((b) => b.lastRead > 0).firstOrNull;
    final next = recent ?? books.where((b) => b.progress < .99).firstOrNull;
    final candidates =
        books.where((b) => b.id != next?.id && b.progress < .99).toList()
          ..sort((a, b) => a.id.compareTo(b.id));
    final picks = candidates.isEmpty
        ? <Book>[]
        : List.generate(
            candidates.length.clamp(0, 3),
            (i) => candidates[(now.day + i) % candidates.length],
          );
    Widget panel(String title, Widget content, {Widget? action}) => Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                ?action,
              ],
            ),
            const SizedBox(height: 14),
            content,
          ],
        ),
      ),
    );
    Widget bookRow(Book b, String label) => InkWell(
      onTap: () => open(b),
      child: Row(
        children: [
          SizedBox(width: 64, height: 92, child: cover(b)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  b.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w400,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${b.author} · ${(b.progress * 100).round()}%',
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                LinearProgressIndicator(value: b.progress),
                const SizedBox(height: 8),
                Text(
                  label,
                  style: TextStyle(color: colors.primary, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const ShuyeIcon(Icons.chevron_right),
        ],
      ),
    );
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (settings.flag('home.banner', true))
          ShuyeWelcomeCard(subtitle: '${now.month} 月 ${now.day} 日 · 留一点时间给阅读')
        else ...[
          Text('给自己，一页安静。', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 6),
          Text(
            '${now.month} 月 ${now.day} 日 · 今天也留一点时间给阅读',
            style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
          ),
        ],
        const SizedBox(height: 18),
        for (final section in visibleHomeSections(settings)) ...[
          switch (section) {
            'continue' => panel(
              recent == null ? '准备开始' : '继续上次的故事',
              next == null
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('还没有书籍，先把喜欢的故事放进来。'),
                        const SizedBox(height: 10),
                        FilledButton(
                          onPressed: shelf,
                          child: const Text('前往书架导入'),
                        ),
                      ],
                    )
                  : bookRow(next, '打开阅读'),
            ),
            'goal' => panel(
              '今日目标',
              Column(
                children: [
                  if (settings.value('home.goalStyle', 'ring') == 'ring')
                    SizedBox(
                      width: 132,
                      height: 132,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox.expand(
                            child: CircularProgressIndicator(
                              value: progress,
                              strokeWidth: 9,
                              backgroundColor: colors.surfaceContainerHighest,
                            ),
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${seconds ~/ 60}',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineLarge,
                              ),
                              Text(
                                '/ $target 分钟',
                                style: TextStyle(
                                  color: colors.onSurfaceVariant,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    )
                  else ...[
                    LinearProgressIndicator(
                      value: progress,
                      minHeight: 10,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    const SizedBox(height: 12),
                    Text('已读 ${seconds ~/ 60} / $target 分钟'),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    progress >= 1
                        ? '今天的目标已完成。'
                        : '还差 ${((target * 60 - seconds) / 60).ceil()} 分钟，慢慢读。',
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: next == null ? shelf : () => open(next),
                    child: const Text('开始阅读'),
                  ),
                ],
              ),
              action: IconButton(
                tooltip: '设置每日目标',
                onPressed: goal,
                icon: const ShuyeIcon(Icons.edit_outlined),
              ),
            ),
            'overview' => panel(
              '阅读概览',
              Wrap(
                spacing: 24,
                runSpacing: 14,
                children: [
                  for (final metric in [
                    ('藏书', '${books.length} 本'),
                    (
                      '累计阅读',
                      '${stats.values.fold<int>(0, (a, b) => a + b) ~/ 60} 分钟',
                    ),
                    ('摘录', '$notes 条'),
                    ('阅读天数', '${stats.values.where((v) => v > 0).length} 天'),
                  ])
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          metric.$1,
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          metric.$2,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              action: IconButton(
                tooltip: '查看阅读统计',
                onPressed: statistics,
                icon: const ShuyeIcon(Icons.chevron_right),
              ),
            ),
            _ => panel(
              '今日选读',
              picks.isEmpty
                  ? const Text('未读完的书都会在这里等你。')
                  : Column(
                      children: [
                        for (var i = 0; i < picks.length; i++) ...[
                          if (i > 0) const Divider(height: 24),
                          bookRow(picks[i], '读一会儿'),
                        ],
                      ],
                    ),
              action: IconButton(
                tooltip: '查看全部书籍',
                onPressed: shelf,
                icon: const ShuyeIcon(Icons.chevron_right),
              ),
            ),
          },
          const SizedBox(height: 14),
        ],
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            OutlinedButton.icon(
              onPressed: shelf,
              icon: const ShuyeIcon(Icons.auto_stories_outlined),
              label: const Text('我的书架'),
            ),
            OutlinedButton.icon(
              onPressed: tools,
              icon: const ShuyeIcon(Icons.handyman_outlined),
              label: const Text('阅读工具箱'),
            ),
          ],
        ),
      ],
    );
  }
}

Future<void> configureHome(
  BuildContext context,
  ReaderSettings s,
  Future<void> Function() save,
) async {
  final order = visibleHomeSections(s);
  String? error;
  await showModalBottomSheet<void>(
    context: context,
    sheetAnimationStyle: applicationMotion(context),
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => StatefulBuilder(
      builder: (c, set) {
        Future<void> persist() async {
          s.extra['home.sections'] = order.join(',');
          try {
            await save();
          } catch (_) {
            if (c.mounted) set(() => error = '保存失败，请重试。');
          }
        }

        return SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(c).height * .82,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text('首页布局', style: ShuyeStyle.panelTitle),
                const SizedBox(height: 8),
                const Text('长按拖动卡片排序，点击显示或隐藏。调整会自动保存。'),
                ReorderableListView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  onReorderItem: (old, next) {
                    set(() {
                      order.insert(next, order.removeAt(old));
                    });
                    persist();
                  },
                  children: [
                    for (final key in order)
                      ListTile(
                        key: ValueKey(key),
                        leading: const ShuyeIcon(Icons.drag_handle),
                        title: Text(homeSections[key]!),
                        trailing: IconButton(
                          tooltip: '隐藏${homeSections[key]}',
                          onPressed: () {
                            set(() => order.remove(key));
                            persist();
                          },
                          icon: const ShuyeIcon(Icons.visibility_off_outlined),
                        ),
                      ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final key in homeSections.keys.where(
                      (key) => !order.contains(key),
                    ))
                      ActionChip(
                        label: Text('显示${homeSections[key]}'),
                        onPressed: () {
                          set(() => order.add(key));
                          persist();
                        },
                      ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('显示阅读横幅'),
                  value: s.flag('home.banner', true),
                  onChanged: (v) {
                    set(() => s.extra['home.banner'] = v);
                    persist();
                  },
                ),
                const Text('目标卡片样式'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final e in {'ring': '圆环', 'bar': '进度条'}.entries)
                      ChoiceChip(
                        label: Text(e.value),
                        selected: s.value('home.goalStyle', 'ring') == e.key,
                        onSelected: (_) {
                          set(() => s.extra['home.goalStyle'] = e.key);
                          persist();
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(color: Theme.of(c).colorScheme.error),
                  ),
                TextButton(
                  onPressed: () {
                    set(() {
                      order
                        ..clear()
                        ..addAll(homeSections.keys);
                      s.extra['home.banner'] = true;
                      s.extra['home.goalStyle'] = 'ring';
                    });
                    persist();
                  },
                  child: const Text('恢复默认布局'),
                ),
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
