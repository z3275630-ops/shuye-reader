import 'package:flutter/material.dart';

/// Small, shared stroke icons. Paths are cached once, with no asset decoding,
/// bundled icon package, animation controller, or background work.
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
        ..strokeWidth = 1.65
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

const _home =
    'M3 10.5 L12 3 L21 10.5 M5 9 L5 20 L10 20 L10 14 L14 14 L14 20 L19 20 L19 9';
const _book =
    'M12 6 C9 4 5 4 3 5 L3 19 C6 18 9 18 12 20 C15 18 18 18 21 19 L21 5 C18 4 15 4 12 6 L12 20';
const _note = 'M6 3 L17 3 Q19 3 19 5 L19 21 L12 17 L5 21 L5 5 Q5 3 6 3';
const _chart = 'M4 4 L4 20 L21 20 M8 15 L8 11 M13 15 L13 6 M18 15 L18 9';
const _tune =
    'M4 6 L9 6 M13 6 L20 6 M4 12 L14 12 M18 12 L20 12 M4 18 L6 18 M10 18 L20 18 M9 4 L13 4 L13 8 L9 8 Z M14 10 L18 10 L18 14 L14 14 Z M6 16 L10 16 L10 20 L6 20 Z';
const _search =
    'M10 4 C13.3 4 16 6.7 16 10 C16 13.3 13.3 16 10 16 C6.7 16 4 13.3 4 10 C4 6.7 6.7 4 10 4 Z M15 15 L21 21';
const _grid =
    'M4 4 L9 4 L9 9 L4 9 Z M15 4 L20 4 L20 9 L15 9 Z M4 15 L9 15 L9 20 L4 20 Z M15 15 L20 15 L20 20 L15 20 Z';
const _leaf = 'M5 19 C0 9 9 3 21 3 C21 15 15 22 5 19 Z M5 19 L15 9';
const _edit =
    'M4 16 L16 4 Q17 3 18 4 L20 6 Q21 7 20 8 L8 20 L3 21 Z M14 6 L18 10';
const _download = 'M12 3 L12 15 M7 10 L12 15 L17 10 M4 16 L4 20 L20 20 L20 16';
const _share = 'M12 16 L12 3 M7 8 L12 3 L17 8 M5 11 L5 20 L19 20 L19 11';
const _folder = 'M3 7 Q3 5 5 5 L9 5 L11 8 L19 8 Q21 8 21 10 L21 19 L3 19 Z';
const _image =
    'M3 4 L21 4 L21 20 L3 20 Z M3 16 L9 10 L16 17 L19 14 L21 16 M15 8 L16 8';
const _info =
    'M12 3 C17 3 21 7 21 12 C21 17 17 21 12 21 C7 21 3 17 3 12 C3 7 7 3 12 3 Z M12 10 L12 16 M12 7 L12 7.1';
const _headphones =
    'M4 14 L4 12 C4 1 20 1 20 12 L20 14 M4 12 L7 12 L7 20 L4 20 Z M17 12 L20 12 L20 20 L17 20 Z';
const _document =
    'M5 3 L14 3 L19 8 L19 21 L5 21 Z M14 3 L14 8 L19 8 M8 12 L16 12 M8 16 L14 16';
const _clock =
    'M12 3 C17 3 21 7 21 12 C21 17 17 21 12 21 C7 21 3 17 3 12 C3 7 7 3 12 3 Z M12 7 L12 12 L16 14';
const _refresh =
    'M4 11 C4 3 16 1 20 9 M16 9 L20 9 L20 5 M20 13 C20 21 8 23 4 15 M8 15 L4 15 L4 19';
const _cloud = 'M7 18 C0 18 1 9 7 9 C8 1 19 3 19 11 C24 12 22 18 18 18 Z';
const _people =
    'M9 4 C13 4 13 10 9 10 C5 10 5 4 9 4 Z M3 20 L3 17 C3 11 15 11 15 17 L15 20 M17 5 C21 5 21 10 17 10 M18 13 C22 13 22 17 22 20';
const _lock =
    'M6 10 L18 10 L18 21 L6 21 Z M8 10 L8 7 C8 1 16 1 16 7 L16 10 M12 14 L12 17';
const _spark =
    'M12 3 L14 9 L20 12 L14 15 L12 21 L10 15 L4 12 L10 9 Z M20 2 L20 6 M18 4 L22 4';
const _palette =
    'M12 3 C2 3 0 17 8 20 C12 23 14 18 11 17 C9 15 12 14 15 15 C24 17 24 3 12 3 Z M7 8 L7 8.1 M12 6 L12 6.1 M17 8 L17 8.1 M6 13 L6 13.1';
const _globe =
    'M12 3 C17 3 21 7 21 12 C21 17 17 21 12 21 C7 21 3 17 3 12 C3 7 7 3 12 3 Z M3 12 L21 12 M12 3 C6 8 6 16 12 21 C18 16 18 8 12 3';
const _tools =
    'M4 4 L9 9 M15 15 L20 20 M21 3 L18 6 L15 5 L14 2 C9 7 12 11 15 11 L4 22 L2 20 L13 9';
const _tree =
    'M9 3 L15 3 L15 9 L9 9 Z M12 9 L12 13 M5 13 L19 13 M5 13 L5 16 M19 13 L19 16 M2 16 L8 16 L8 22 L2 22 Z M16 16 L22 16 L22 22 L16 22 Z';
final _geometry = <IconData, String>{
  Icons.home: _home,
  Icons.home_outlined: _home,
  Icons.auto_stories: _book,
  Icons.auto_stories_outlined: _book,
  Icons.menu_book_outlined: _book,
  Icons.bookmarks: _note,
  Icons.bookmarks_outlined: _note,
  Icons.bookmark: _note,
  Icons.bookmark_border: _note,
  Icons.bookmark_add_outlined: '$_note M10 8 L14 8 M12 6 L12 10',
  Icons.bar_chart: _chart,
  Icons.bar_chart_outlined: _chart,
  Icons.tune: _tune,
  Icons.equalizer: _tune,
  Icons.search: _search,
  Icons.grid_view_rounded: _grid,
  Icons.dashboard_customize_outlined: _grid,
  Icons.eco_outlined: _leaf,
  Icons.edit_outlined: _edit,
  Icons.edit_note: _edit,
  Icons.add: 'M12 4 L12 20 M4 12 L20 12',
  Icons.close: 'M6 6 L18 18 M18 6 L6 18',
  Icons.chevron_left: 'M15 5 L8 12 L15 19',
  Icons.chevron_right: 'M9 5 L16 12 L9 19',
  Icons.keyboard_arrow_up: 'M5 15 L12 8 L19 15',
  Icons.keyboard_arrow_down: 'M5 9 L12 16 L19 9',
  Icons.arrow_back: 'M20 12 L4 12 M11 5 L4 12 L11 19',
  Icons.arrow_forward_rounded: 'M4 12 L20 12 M13 5 L20 12 L13 19',
  Icons.more_horiz: 'M5 12 L5 12.1 M12 12 L12 12.1 M19 12 L19 12.1',
  Icons.drag_handle: 'M5 9 L19 9 M5 15 L19 15',
  Icons.download: _download,
  Icons.file_download_outlined: _download,
  Icons.save_alt: _download,
  Icons.ios_share: _share,
  Icons.ios_share_outlined: _share,
  Icons.folder_outlined: _folder,
  Icons.photo_outlined: _image,
  Icons.add_photo_alternate_outlined: '$_image M17 7 L21 7 M19 5 L19 9',
  Icons.info_outline: _info,
  Icons.headphones: _headphones,
  Icons.headphones_outlined: _headphones,
  Icons.text_snippet_outlined: _document,
  Icons.receipt_long: _document,
  Icons.file_open_outlined: _document,
  Icons.history: _clock,
  Icons.restore: _refresh,
  Icons.restart_alt: _refresh,
  Icons.cloud_outlined: _cloud,
  Icons.cloud_download_outlined: '$_cloud M12 10 L12 16 M9 13 L12 16 L15 13',
  Icons.cloud_upload_outlined: '$_cloud M12 16 L12 10 M9 13 L12 10 L15 13',
  Icons.people_outline: _people,
  Icons.lock_outline: _lock,
  Icons.lock_open_outlined:
      'M6 10 L18 10 L18 21 L6 21 Z M8 10 L8 7 C8 1 16 1 16 7 M12 14 L12 17',
  Icons.auto_awesome: _spark,
  Icons.palette_outlined: _palette,
  Icons.language: _globe,
  Icons.handyman_outlined: _tools,
  Icons.account_tree_outlined: _tree,
  Icons.hub_outlined: _tree,
  Icons.delete_outline: 'M4 6 L20 6 M9 6 L9 3 L15 3 L15 6 M6 6 L7 21 L17 21 L18 6 M10 10 L10 17 M14 10 L14 17',
  Icons.filter_alt_outlined: 'M3 4 L21 4 L14 12 L14 20 L10 18 L10 12 Z',
  Icons.format_list_bulleted: 'M8 6 L21 6 M8 12 L21 12 M8 18 L21 18 M3 6 L3 6.1 M3 12 L3 12.1 M3 18 L3 18.1',
  Icons.notifications_outlined:
      'M5 17 L7 14 L7 9 C7 2 17 2 17 9 L17 14 L19 17 Z M10 21 L14 21',
  Icons.document_scanner_outlined: 'M3 8 L3 3 L8 3 M16 3 L21 3 L21 8 M21 16 L21 21 L16 21 M8 21 L3 21 L3 16 M7 8 L17 8 M7 12 L17 12 M7 16 L14 16',
  Icons.chat_bubble_outline: 'M3 4 L21 4 L21 17 L8 17 L3 21 Z',
  Icons.fact_check_outlined: 'M4 3 L20 3 L20 21 L4 21 Z M8 8 L9 9 L11 7 M14 8 L17 8 M8 15 L9 16 L11 14 M14 15 L17 15',
  Icons.style_outlined: 'M8 3 L20 3 L20 17 L8 17 Z M4 7 L4 21 L16 21',
  Icons.font_download_outlined:
      'M3 3 L21 3 L21 21 L3 21 Z M7 17 L12 7 L17 17 M9 13 L15 13',
  Icons.translate: 'M3 5 L15 5 M9 3 L9 5 M12 5 C11 10 7 13 3 15 M5 8 C7 12 10 14 13 15 M13 21 L18 11 L23 21 M15 17 L21 17',
  Icons.fingerprint: 'M5 9 C5 1 19 1 19 9 M3 15 L3 11 M21 11 L21 15 M8 20 C9 17 7 12 8 9 C10 5 16 6 16 10 L16 16 M11 21 L12 11 M19 20 L19 18',
  Icons.visibility_off_outlined: 'M3 3 L21 21 M9 5 C15 3 19 7 22 12 L18 16 M15 19 C9 21 5 17 2 12 L6 8 M10 10 L14 14',
  Icons.visibility_outlined: 'M2 12 C7 3 17 3 22 12 C17 21 7 21 2 12 Z M15 12 C15 16 9 16 9 12 C9 8 15 8 15 12 Z',
  Icons.play_circle: 'M12 3 C17 3 21 7 21 12 C21 17 17 21 12 21 C7 21 3 17 3 12 C3 7 7 3 12 3 Z M10 8 L16 12 L10 16 Z',
  Icons.pause_circle: 'M12 3 C17 3 21 7 21 12 C21 17 17 21 12 21 C7 21 3 17 3 12 C3 7 7 3 12 3 Z M9 8 L9 16 M15 8 L15 16',
  Icons.format_quote: 'M4 6 L10 6 L10 14 L7 18 M4 6 L4 12 L10 12 M14 6 L20 6 L20 14 L17 18 M14 6 L14 12 L20 12',
};
