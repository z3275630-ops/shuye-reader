import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Shared Lucide functional icons; the custom brand leaf stays native.
/// No network resources, SVG runtime or animation.
class ShuyeIcon extends StatelessWidget {
  final IconData? icon;
  final double? size;
  final Color? color;
  final String? semanticLabel;
  const ShuyeIcon(
    this.icon, {
    super.key,
    this.size,
    this.color,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final mapped = _lucide[icon];
    if (mapped != null) {
      final widget = Icon(
        mapped,
        size: size,
        color: color,
        semanticLabel: semanticLabel,
      );
      return icon!.matchTextDirection &&
              Directionality.of(context) == TextDirection.rtl
          ? Transform.flip(flipX: true, child: widget)
          : widget;
    }
    final geometry = _geometry[icon];
    if (geometry == null) {
      return Icon(icon, size: size, color: color, semanticLabel: semanticLabel);
    }
    final theme = IconTheme.of(context);
    final extent = size ?? theme.size ?? 24;
    final ink = color ?? theme.color ?? Colors.black;
    return Semantics(
      label: semanticLabel,
      child: ExcludeSemantics(
        child: Center(
          widthFactor: 1,
          heightFactor: 1,
          child: SizedBox.square(
            dimension: extent,
            child: CustomPaint(
              painter: _StrokeIcon(
                _cache.putIfAbsent(geometry, () => _path(geometry)),
                ink.withValues(alpha: ink.a * (theme.opacity ?? 1)),
                icon!.matchTextDirection &&
                    Directionality.of(context) == TextDirection.rtl,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StrokeIcon extends CustomPainter {
  final Path path;
  final Color color;
  final bool mirror;
  const _StrokeIcon(this.path, this.color, this.mirror);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    if (mirror) {
      canvas.translate(24, 0);
      canvas.scale(-1, 1);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.9
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_StrokeIcon old) =>
      path != old.path || color != old.color || mirror != old.mirror;
}

final _cache = <String, Path>{};
final _tokens = RegExp(r'[MLCQZ]|-?\d+(?:\.\d+)?');
Path _path(String geometry) {
  final tokens = _tokens.allMatches(geometry).map((m) => m[0]!).toList();
  final path = Path();
  var i = 0;
  double n() => double.parse(tokens[i++]);
  while (i < tokens.length) {
    switch (tokens[i++]) {
      case 'M':
        path.moveTo(n(), n());
      case 'L':
        path.lineTo(n(), n());
      case 'C':
        path.cubicTo(n(), n(), n(), n(), n(), n());
      case 'Q':
        path.quadraticBezierTo(n(), n(), n(), n());
      case 'Z':
        path.close();
    }
  }
  return path;
}

const _leaf = 'M5 19 C0 9 9 3 21 3 C21 15 15 22 5 19 Z M5 19 L15 9';
final _geometry = {Icons.eco_outlined: _leaf};
final _lucide = <IconData, IconData>{
  Icons.arrow_upward: LucideIcons.arrowUp,
  Icons.account_tree_outlined: LucideIcons.gitFork,
  Icons.add: LucideIcons.plus,
  Icons.add_photo_alternate_outlined: LucideIcons.imagePlus,
  Icons.arrow_back: LucideIcons.arrowLeft,
  Icons.arrow_forward_rounded: LucideIcons.arrowRight,
  Icons.auto_awesome: LucideIcons.sparkles,
  Icons.auto_stories: LucideIcons.bookOpen,
  Icons.auto_stories_outlined: LucideIcons.bookOpen,
  Icons.bar_chart: LucideIcons.chartNoAxesColumn,
  Icons.bar_chart_outlined: LucideIcons.chartNoAxesColumn,
  Icons.bookmark: LucideIcons.bookmark,
  Icons.bookmark_add_outlined: LucideIcons.bookmarkPlus,
  Icons.bookmark_border: LucideIcons.bookmark,
  Icons.bookmarks: LucideIcons.notebookPen,
  Icons.bookmarks_outlined: LucideIcons.notebookPen,
  Icons.chat_bubble_outline: LucideIcons.messageCircle,
  Icons.chevron_left: LucideIcons.chevronLeft,
  Icons.chevron_right: LucideIcons.chevronRight,
  Icons.close: LucideIcons.x,
  Icons.cloud_download_outlined: LucideIcons.cloudDownload,
  Icons.cloud_outlined: LucideIcons.cloud,
  Icons.cloud_upload_outlined: LucideIcons.cloudUpload,
  Icons.dashboard_customize_outlined: LucideIcons.layoutGrid,
  Icons.delete_outline: LucideIcons.trash2,
  Icons.document_scanner_outlined: LucideIcons.scanText,
  Icons.download: LucideIcons.download,
  Icons.drag_handle: LucideIcons.gripHorizontal,
  Icons.edit: LucideIcons.pencil,
  Icons.edit_note: LucideIcons.notebookPen,
  Icons.edit_outlined: LucideIcons.pencil,
  Icons.equalizer: LucideIcons.slidersHorizontal,
  Icons.fact_check_outlined: LucideIcons.listChecks,
  Icons.file_download_outlined: LucideIcons.download,
  Icons.file_open_outlined: LucideIcons.fileText,
  Icons.filter_alt_outlined: LucideIcons.funnel,
  Icons.fingerprint: LucideIcons.fingerprint,
  Icons.folder_outlined: LucideIcons.folder,
  Icons.font_download_outlined: LucideIcons.type,
  Icons.format_list_bulleted: LucideIcons.list,
  Icons.format_quote: LucideIcons.quote,
  Icons.grid_view_rounded: LucideIcons.layoutGrid,
  Icons.handyman_outlined: LucideIcons.wrench,
  Icons.headphones: LucideIcons.headphones,
  Icons.headphones_outlined: LucideIcons.headphones,
  Icons.history: LucideIcons.history,
  Icons.home: LucideIcons.house,
  Icons.home_outlined: LucideIcons.house,
  Icons.hub_outlined: LucideIcons.gitFork,
  Icons.info_outline: LucideIcons.info,
  Icons.ios_share: LucideIcons.share2,
  Icons.ios_share_outlined: LucideIcons.share2,
  Icons.keyboard_arrow_down: LucideIcons.chevronDown,
  Icons.keyboard_arrow_up: LucideIcons.chevronUp,
  Icons.language: LucideIcons.globe,
  Icons.lock_open_outlined: LucideIcons.lockKeyholeOpen,
  Icons.lock_outline: LucideIcons.lockKeyhole,
  Icons.menu_book_outlined: LucideIcons.bookOpen,
  Icons.more_horiz: LucideIcons.ellipsis,
  Icons.more_vert: LucideIcons.ellipsisVertical,
  Icons.notifications_outlined: LucideIcons.bell,
  Icons.palette_outlined: LucideIcons.palette,
  Icons.pause_circle: LucideIcons.circlePause,
  Icons.people_outline: LucideIcons.users,
  Icons.photo_outlined: LucideIcons.image,
  Icons.play_circle: LucideIcons.circlePlay,
  Icons.receipt_long: LucideIcons.fileText,
  Icons.restart_alt: LucideIcons.rotateCcw,
  Icons.restore: LucideIcons.rotateCcw,
  Icons.save_alt: LucideIcons.download,
  Icons.search: LucideIcons.search,
  Icons.style_outlined: LucideIcons.layers,
  Icons.text_snippet_outlined: LucideIcons.fileText,
  Icons.translate: LucideIcons.languages,
  Icons.tune: LucideIcons.slidersHorizontal,
  Icons.visibility_off_outlined: LucideIcons.eyeOff,
  Icons.visibility_outlined: LucideIcons.eye,
};
