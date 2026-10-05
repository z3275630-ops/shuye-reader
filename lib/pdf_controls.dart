import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'app_icons.dart';

/// Builds only visible pages and nearby thumbnails, rather than the full PDF.
class PdfContentsPanel extends StatefulWidget {
  final int pageCount;
  final int currentPage;
  final List<PdfOutlineNode> outline;
  final Widget Function(BuildContext, int) thumbnail;
  final ValueChanged<int> onSelected;
  const PdfContentsPanel({
    super.key,
    required this.pageCount,
    required this.currentPage,
    required this.outline,
    required this.thumbnail,
    required this.onSelected,
  });

  @override
  State<PdfContentsPanel> createState() => _PdfContentsPanelState();
}

class _PdfContentsPanelState extends State<PdfContentsPanel> {
  late final scrollController = ScrollController(
    initialScrollOffset:
        (widget.currentPage.clamp(1, widget.pageCount) - 1) * 132.0,
  );

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pageCount = widget.pageCount;
    final currentPage = widget.currentPage;
    final onSelected = widget.onSelected;
    final entries = <({PdfOutlineNode node, int depth})>[];
    void flatten(List<PdfOutlineNode> nodes, int depth) {
      for (final node in nodes) {
        entries.add((node: node, depth: depth));
        flatten(node.children, depth + 1);
      }
    }

    flatten(widget.outline, 0);
    return DefaultTabController(
      length: 2,
      initialIndex: entries.isEmpty ? 1 : 0,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(
              'PDF 目录与缩略图',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          const TabBar(
            tabs: [
              Tab(text: '目录'),
              Tab(text: '缩略图'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                entries.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('文件未提供目录，可查看缩略图或点按底部页码跳转。'),
                        ),
                      )
                    : ListView.builder(
                        itemCount: entries.length,
                        itemBuilder: (context, index) {
                          final entry = entries[index];
                          final page = entry.node.dest?.pageNumber;
                          final enabled =
                              page != null && page >= 1 && page <= pageCount;
                          return ListTile(
                            contentPadding: EdgeInsets.only(
                              left: 20 + entry.depth.clamp(0, 3) * 12,
                              right: 20,
                            ),
                            title: Text(entry.node.title),
                            trailing: enabled ? Text('$page') : null,
                            enabled: enabled,
                            selected: enabled && page == currentPage,
                            onTap: enabled ? () => onSelected(page) : null,
                          );
                        },
                      ),
                ListView.builder(
                  key: const PageStorageKey('pdf-thumbnails'),
                  controller: scrollController,
                  itemExtent: 132,
                  itemCount: pageCount,
                  itemBuilder: (context, index) {
                    final page = index + 1;
                    return Semantics(
                      label: '第 $page 页',
                      selected: page == currentPage,
                      button: true,
                      child: InkWell(
                        onTap: () => onSelected(page),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              ExcludeSemantics(
                                child: SizedBox(
                                  width: 78,
                                  height: 108,
                                  child: widget.thumbnail(context, page),
                                ),
                              ),
                              const SizedBox(width: 20),
                              Expanded(
                                child: Text(
                                  '第 $page 页${page == currentPage ? ' · 当前页' : ''}',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class PdfPageNavigation extends StatelessWidget {
  final int page;
  final int? pageCount;
  final VoidCallback? previous;
  final VoidCallback? next;
  final VoidCallback? jump;
  const PdfPageNavigation({
    super.key,
    required this.page,
    required this.pageCount,
    this.previous,
    this.next,
    this.jump,
  });

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      IconButton(
        tooltip: '上一页',
        onPressed: page > 1 ? previous : null,
        icon: const ShuyeIcon(Icons.chevron_left),
      ),
      Flexible(
        child: TextButton(
          onPressed: jump,
          child: Text(
            '$page / ${pageCount ?? '…'} 页',
            textAlign: TextAlign.center,
            semanticsLabel: '第 $page 页，共 ${pageCount ?? '未知'} 页，跳转页码',
          ),
        ),
      ),
      IconButton(
        tooltip: '下一页',
        onPressed: pageCount != null && page < pageCount! ? next : null,
        icon: const ShuyeIcon(Icons.chevron_right),
      ),
    ],
  );
}

class PdfSearchResults extends StatelessWidget {
  final PdfTextSearcher searcher;
  const PdfSearchResults({super.key, required this.searcher});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: searcher,
    builder: (context, _) {
      if (searcher.pattern == null) return const SizedBox.shrink();
      final index = searcher.currentIndex;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          children: [
            if (searcher.isSearching)
              LinearProgressIndicator(value: searcher.searchProgress),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.center,
              children: [
                Text(
                  searcher.isSearching
                      ? '搜索中 · 已找到 ${searcher.matches.length} 处'
                      : searcher.matches.isEmpty
                      ? '未找到匹配文字'
                      : '${index == null ? 1 : index + 1} / ${searcher.matches.length} 处',
                ),
                IconButton(
                  tooltip: '上个搜索结果',
                  onPressed: index != null && index > 0
                      ? () async {
                          await searcher.goToPrevMatch();
                          searcher.notifyListeners();
                        }
                      : null,
                  icon: const ShuyeIcon(Icons.keyboard_arrow_up),
                ),
                IconButton(
                  tooltip: '下个搜索结果',
                  onPressed:
                      searcher.matches.isNotEmpty &&
                          (index == null || index + 1 < searcher.matches.length)
                      ? () async {
                          await searcher.goToNextMatch();
                          searcher.notifyListeners();
                        }
                      : null,
                  icon: const ShuyeIcon(Icons.keyboard_arrow_down),
                ),
                IconButton(
                  tooltip: '关闭 PDF 搜索',
                  onPressed: searcher.resetTextSearch,
                  icon: const ShuyeIcon(Icons.close),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}
