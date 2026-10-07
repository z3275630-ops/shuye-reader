import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Margins belong to each moving sheet, not to the stationary viewport.
class ReaderPage extends StatelessWidget {
  final Widget child;
  final Color color;
  final double margin;
  final Widget? header, footer;
  const ReaderPage({
    super.key,
    required this.child,
    required this.color,
    required this.margin,
    this.header,
    this.footer,
  });
  @override
  Widget build(BuildContext context) => ClipRect(
    child: ColoredBox(
      color: color,
      child: Column(
        children: [
          ?header,
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: margin),
              child: child,
            ),
          ),
          ?footer,
        ],
      ),
    ),
  );
}

class PageTurnSurface extends StatefulWidget {
  final Widget child;
  final Color color;
  // Fallback for callers that do not supply prepared neighboring sheets.
  final Widget? Function(int direction)? adjacent;
  // Mounted offstage at rest so text layout precedes the first drag frame.
  final Widget? previous, next;
  final Object? pageIdentity;
  final bool enabled;
  const PageTurnSurface({
    super.key,
    required this.child,
    required this.color,
    this.adjacent,
    this.previous,
    this.next,
    this.pageIdentity,
    this.enabled = true,
  });
  @override
  State<PageTurnSurface> createState() => PageTurnSurfaceState();
}

class _TurnRequest {
  final VoidCallback action;
  final String effect;
  final int direction;
  final done = Completer<void>();
  _TurnRequest(this.action, this.effect, this.direction);
}

class PageTurnSurfaceState extends State<PageTurnSurface>
    with SingleTickerProviderStateMixin {
  final boundary = GlobalKey();
  ui.Image? snapshot;
  ui.FragmentShader? shader;
  bool busy = false;
  final _pendingTurns = <_TurnRequest>[];
  String mode = 'none';
  int direction = 1;
  Widget? _incoming;
  bool _dragging = false, _settling = false, _committing = false;
  double _width = 0, _dragOffset = 0, _rawDrag = 0, _from = 0, _to = 0;
  double? _releaseSlope;
  double _slideProgress(double t) {
    final slope = _releaseSlope;
    if (slope == null) return Curves.easeOutCubic.transform(t);
    // Hermite settlement preserves release velocity and ends at rest.
    // Limiting the slope to [0, 3] keeps the movement monotonic.
    return ((slope - 2) * t + (3 - 2 * slope)) * t * t + slope * t;
  }

  Widget? _neighbor(int d) =>
      (d > 0 ? widget.next : widget.previous) ?? widget.adjacent?.call(d);
  int _epoch = 0;
  double get displacement => _settling
      ? ui.lerpDouble(_from, _to, _slideProgress(controller.value))!
      : _dragOffset;
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );

  bool beginDrag() {
    if (!widget.enabled || _committing) return false;
    if (busy) {
      if (!_settling || mode != 'slide') return false;
      final offset = displacement;
      _epoch++;
      controller.stop(canceled: true);
      _settling = false;
      _rawDrag = _dragOffset = offset;
    } else {
      _rawDrag = _dragOffset = 0;
    }
    busy = true;
    _dragging = true;
    mode = 'slide';
    return true;
  }

  void updateDrag(double dx) {
    if (!_dragging || !widget.enabled || _width <= 0) return;
    _rawDrag += dx;
    final nextDirection = _rawDrag <= 0 ? 1 : -1;
    if (_incoming == null || direction != nextDirection) {
      direction = nextDirection;
      _incoming = _neighbor(direction);
    }
    setState(() {
      _dragOffset = _incoming == null ? 0 : _rawDrag.clamp(-_width, _width);
    });
  }

  Future<void> endDrag(double velocity, ValueChanged<int> commit) async {
    if (!_dragging) return;
    _dragging = false;
    final travel = _rawDrag;
    if (travel == 0 && velocity == 0) {
      _reset();
      _drain();
      return;
    }
    direction = travel == 0 ? (velocity < 0 ? 1 : -1) : (travel < 0 ? 1 : -1);
    _incoming ??= _neighbor(direction);
    final projected = travel + velocity * .14;
    final reversing = velocity.abs() >= 450 && velocity * direction > 0;
    final accept =
        widget.enabled &&
        !reversing &&
        (travel.abs() >= _width * .22 ||
            velocity * direction <= -650 ||
            (projected * direction < 0 && projected.abs() >= _width * .3));
    // At a book boundary there is no fictional page to animate.
    if (_incoming == null) {
      if (accept) commit(direction);
      _reset();
      _drain();
      return;
    }
    final target = accept ? -direction * _width : 0.0;
    final remaining = ((target - displacement).abs() / _width).clamp(0.0, 1.0);
    final fast = velocity.abs() >= 450;
    await _settle(
      target,
      accept ? () => commit(direction) : null,
      velocity: velocity,
      duration: Duration(
        milliseconds: ((accept ? 90 : 80) + remaining * (fast ? 85 : 125))
            .round(),
      ),
    );
    _drain();
  }

  Future<void> turn(VoidCallback action, String effect, {int direction = 1}) {
    final request = _TurnRequest(action, effect, direction >= 0 ? 1 : -1);
    if (!widget.enabled) {
      request.done.complete();
    } else if (busy) {
      _pendingTurns.add(request);
    } else {
      unawaited(_run(request));
    }
    return request.done.future;
  }

  Future<void> _run(_TurnRequest request) async {
    busy = true;
    final epoch = _epoch;
    mode = request.effect;
    direction = request.direction;
    try {
      if (mode == 'none' || MediaQuery.disableAnimationsOf(context)) {
        request.action();
        return;
      }
      _incoming = _neighbor(direction);
      if (_incoming == null) {
        request.action();
        return;
      }
      if (mode == 'curl' || mode == 'fade') {
        try {
          if (mode == 'curl') {
            shader ??= (await ui.FragmentProgram.fromAsset(
              'shaders/page_curl.frag',
            )).fragmentShader();
          }
          if (!mounted || epoch != _epoch) return;
          final render = boundary.currentContext?.findRenderObject();
          if (render is RenderRepaintBoundary && !render.debugNeedsPaint) {
            final image = await render.toImage(pixelRatio: 1.5);
            if (!mounted || epoch != _epoch) {
              image.dispose();
              return;
            }
            snapshot = image;
          } else {
            mode = 'slide';
          }
        } catch (_) {
          // A shader or snapshot failure must not discard the requested turn.
          if (!mounted || epoch != _epoch) return;
          mode = 'slide';
        }
      }
      if (!mounted || epoch != _epoch) return;
      await _settle(-direction * _width, request.action);
    } finally {
      if (!request.done.isCompleted) request.done.complete();
      if (mounted && epoch == _epoch) {
        _reset();
        _drain();
      }
    }
  }

  Future<void> _settle(
    double target,
    VoidCallback? commit, {
    Duration duration = const Duration(milliseconds: 240),
    double? velocity,
  }) async {
    final epoch = _epoch;
    _from = displacement;
    // Reset the old completed animation before exposing the new settlement.
    // This keeps consecutive drags from briefly using the previous endpoint.
    controller.value = 0;
    _to = target;
    final distance = _to - _from;
    _releaseSlope = velocity == null || distance.abs() < .01
        ? null
        : (velocity * duration.inMicroseconds / 1000000 / distance).clamp(
            0.0,
            3.0,
          );
    _settling = true;
    controller.duration = duration;
    setState(() {});
    try {
      if ((_to - _from).abs() >= .01 &&
          !MediaQuery.disableAnimationsOf(context)) {
        await controller.forward(from: 0).orCancel;
      } else {
        controller.value = 1;
      }
      if (!mounted || epoch != _epoch || !widget.enabled) return;
      if (commit != null) {
        _committing = true;
        commit();
        // Keep the completed incoming page until the new child has painted.
        await WidgetsBinding.instance.endOfFrame;
        _committing = false;
      }
    } on TickerCanceled {
      // Leaving the page or locking the library abandons the pending turn.
    } finally {
      if (mounted && epoch == _epoch) _reset();
    }
  }

  void _reset() {
    if (!mounted) return;
    setState(() {
      snapshot?.dispose();
      snapshot = null;
      _incoming = null;
      _dragging = _settling = _committing = busy = false;
      _dragOffset = _rawDrag = 0;
    });
  }

  void _drain() {
    if (!mounted || busy || _pendingTurns.isEmpty) return;
    unawaited(_run(_pendingTurns.removeAt(0)));
  }

  void cancel() {
    _epoch++;
    controller.stop(canceled: true);
    for (final request in _pendingTurns) {
      if (!request.done.isCompleted) request.done.complete();
    }
    _pendingTurns.clear();
    _reset();
  }

  @override
  void didUpdateWidget(PageTurnSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled ||
        (!_committing && oldWidget.pageIdentity != widget.pageIdentity)) {
      cancel();
    }
  }

  @override
  void dispose() {
    _epoch++;
    for (final request in _pendingTurns) {
      if (!request.done.isCompleted) request.done.complete();
    }
    controller.dispose();
    snapshot?.dispose();
    shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      _width = box.maxWidth;
      return ClipRect(
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final dx = displacement;
            final imageEffect =
                snapshot != null && (mode == 'fade' || mode == 'curl');
            return Stack(
              fit: StackFit.expand,
              children: [
                Transform.translate(
                  key: const ValueKey('reader-page-translation'),
                  offset: imageEffect ? Offset.zero : Offset(dx, 0),
                  child: Offstage(
                    offstage: imageEffect,
                    child: RepaintBoundary(
                      key: boundary,
                      child: ColoredBox(
                        color: widget.color,
                        child: widget.child,
                      ),
                    ),
                  ),
                ),
                for (final d in [-1, 1])
                  if ((d > 0 ? widget.next : widget.previous) != null ||
                      (direction == d && _incoming != null))
                    Transform.translate(
                      key: ValueKey('reader-neighbor-$d'),
                      offset: Offset(imageEffect ? 0 : dx + d * _width, 0),
                      child: Offstage(
                        offstage: direction != d || _incoming == null,
                        child: ExcludeSemantics(
                          child: IgnorePointer(
                            child: RepaintBoundary(
                              child: direction == d && _incoming != null
                                  ? _incoming!
                                  : (d > 0 ? widget.next : widget.previous)!,
                            ),
                          ),
                        ),
                      ),
                    ),
                if (imageEffect)
                  IgnorePointer(
                    child: CustomPaint(
                      painter: TurnPainter(
                        snapshot!,
                        controller.value,
                        mode == 'curl' ? shader : null,
                        mode: mode,
                        direction: direction,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      );
    },
  );
}

class TurnPainter extends CustomPainter {
  final ui.Image image;
  final double progress;
  final ui.FragmentShader? shader;
  final String mode;
  final int direction;
  TurnPainter(
    this.image,
    this.progress,
    this.shader, {
    this.mode = 'slide',
    this.direction = 1,
  });
  @override
  void paint(Canvas c, Size size) {
    c.save();
    c.clipRect(Offset.zero & size);
    final src = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    final dst = Offset.zero & size;
    if (shader != null) {
      shader!.setFloat(0, size.width);
      shader!.setFloat(1, size.height);
      shader!.setFloat(2, progress);
      shader!.setImageSampler(0, image);
      c.drawRect(Offset.zero & size, Paint()..shader = shader);
    } else if (mode == 'fade') {
      // Image paint uses the color's alpha; its RGB does not tint the image.
      c.drawImageRect(
        image,
        src,
        dst,
        Paint()..color = Colors.white.withValues(alpha: 1 - progress),
      );
    } else {
      // Horizontal slide: the outgoing page glides away in the reading
      // direction and reveals the incoming page with no decorative effects.
      final dx = -progress * size.width * (direction >= 0 ? 1 : -1);
      c.save();
      c.translate(dx, 0);
      c.drawImageRect(image, src, dst, Paint());
      c.restore();
    }
    c.restore();
  }

  @override
  bool shouldRepaint(TurnPainter old) =>
      old.progress != progress ||
      old.image != image ||
      old.mode != mode ||
      old.direction != direction;
}
