import 'app_icons.dart';

import 'package:flutter/material.dart';

class ToolAction {
  final IconData icon;
  final String title, subtitle;
  final VoidCallback action;
  const ToolAction(this.icon, this.title, this.subtitle, this.action);
  String get group {
    if (title.contains('AI') ||
        title.contains('助手') ||
        title.contains('提示词') ||
        title.contains('建议')) {
      return '阅读助手';
    }
    if (title.contains('识字') || title.contains('有声') || title.contains('生词')) {
      return '声音与识字';
    }
    if (title.contains('字体') || title.contains('方案')) return '外观与排版';
    if (title.contains('锁') || title.contains('MCP')) return '隐私与连接';
    return '书库与备份';
  }
}

class ToolCatalog extends StatefulWidget {
  final List<ToolAction> actions;
  final bool busy;
  const ToolCatalog({super.key, required this.actions, this.busy = false});
  @override
  State<ToolCatalog> createState() => _ToolCatalogState();
}

class _ToolCatalogState extends State<ToolCatalog> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final visible = widget.actions
        .where(
          (a) => '${a.title} ${a.subtitle}'.toLowerCase().contains(
            query.trim().toLowerCase(),
          ),
        )
        .toList();
    final groups = <String, List<ToolAction>>{};
    for (final a in visible) {
      (groups[a.group] ??= []).add(a);
    }
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (widget.busy) const LinearProgressIndicator(),
        TextField(
          onChanged: (v) => setState(() => query = v),
          decoration: const InputDecoration(
            prefixIcon: ShuyeIcon(Icons.search),
            hintText: '搜索工具，如字体、备份、AI',
          ),
        ),
        const SizedBox(height: 14),
        Text(
          '按需启用，正文不会自动上传。',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        if (visible.isEmpty)
          const Padding(
            padding: EdgeInsets.all(36),
            child: Center(child: Text('没有找到工具，试试其他关键词。')),
          ),
        for (final group in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 24, bottom: 10),
            child: Text(
              group.key,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          LayoutBuilder(
            builder: (c, constraints) {
              final columns = constraints.maxWidth > 650 ? 3 : 2;
              final width =
                  (constraints.maxWidth - (columns - 1) * 10) / columns;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final a in group.value)
                    SizedBox(
                      width: width,
                      child: Card(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: widget.busy ? null : a.action,
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ShuyeIcon(
                                  a.icon,
                                  color: Theme.of(c).colorScheme.primary,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  a.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  a.subtitle,
                                  style: TextStyle(
                                    fontSize: 11,
                                    height: 1.5,
                                    color: Theme.of(c)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ],
    );
  }
}
