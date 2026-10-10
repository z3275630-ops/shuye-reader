import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'reader_scroller.dart';

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
  // Mounted and painted outside the clip before dragging. The framework keeps
  // their display lists; movement only composites the prepared sheet layers.
  final Widget? previous, next;
  final ReaderNeighborState? previousState, nextState;
  final Future<void> Function(int direction)? prepareAdjacent;
  final Object? pageIdentity, previousIdentity, nextIdentity;
  final bool enabled;
  const PageTurnSurface({
    super.key,
    required this.child,
    required this.color,
    this.adjacent,
    this.previous,
    this.next,
    this.previousState,
    this.nextState,
    this.prepareAdjacent,
    this.pageIdentity,
    this.previousIdentity,
    this.nextIdentity,
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

enum _SheetRole { current, previous, next }

/// A missing prepared sheet is either a book edge or work still in flight.
enum ReaderNeighborState { ready, loading, boundary }

class _DeferredRelease {
  final double velocity;
  final ValueChanged<int> commit;
  final done = Completer<void>();
  _DeferredRelease(this.velocity, this.commit);
}

class PageTurnSurfaceState extends State<PageTurnSurface>
    with SingleTickerProviderStateMixin {
  final _sheetKeys = <Object, GlobalKey>{};
  Object _identity(int d) => switch (d) {
    -1 => widget.previousIdentity ?? _SheetRole.previous,
    1 => widget.nextIdentity ?? _SheetRole.next,
    _ => widget.pageIdentity ?? _SheetRole.current,
  };
  GlobalKey _sheetKey(Object identity) =>
      _sheetKeys.putIfAbsent(identity, GlobalKey.new);
  GlobalKey get boundary => _sheetKey(_identity(0));
  ui.Image? snapshot;
  ui.FragmentShader? shader;
  bool busy = false;
  final _pendingTurns = <_TurnRequest>[];
  String mode = 'none';
  int direction = 1;
  Widget? _incoming;
  bool _dragging = false, _settling = false, _committing = false;
  bool _handoff = false;
  double _width = 0, _dragOffset = 0, _rawDrag = 0, _from = 0, _to = 0;
  bool _pagerSettling = false, _waitingForSheet = false;
  double _queuedTravel = 0;
  double _initialMotion = 0;
  Future<void>? _preparingNeighbor;
  int? _preparingDirection;
  int _preparationEpoch = 0;
  bool get waitingForNeighbor => _preparingNeighbor != null;
  _DeferredRelease? _queuedRelease;
  VoidCallback? _settleCommit;
  double _slideProgress(double t) => _pagerSettling
      ? const ReaderPagerCurve().transform(t)
      : Curves.easeOutCubic.transform(t);

  Widget? _neighbor(int d) =>
      (d > 0 ? widget.next : widget.previous) ?? widget.adjacent?.call(d);
  ReaderNeighborState _neighborState(int d) =>
      (d > 0 ? widget.nextState : widget.previousState) ??
      (_neighbor(d) == null
          ? ReaderNeighborState.boundary
          : ReaderNeighborState.ready);

  Future<void> _prepareNeighbor(int d) {
    if (_preparingDirection == d && _preparingNeighbor != null) {
      return _preparingNeighbor!;
    }
    final prepare = widget.prepareAdjacent;
    if (prepare == null) return Future<void>.value();
    final epoch = _epoch;
    final preparationEpoch = ++_preparationEpoch;
    _preparingDirection = d;
    final ready = () async {
      try {
        await prepare(d);
        if (!mounted ||
            epoch != _epoch ||
            preparationEpoch != _preparationEpoch ||
            !widget.enabled) {
          return;
        }
        // The reader must bind and paint its prepared sheet before a release
        // animation can use it. Loading never commits a different chapter.
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted ||
            epoch != _epoch ||
            preparationEpoch != _preparationEpoch ||
            !widget.enabled) {
          return;
        }
        if (_dragging && direction == d) updateDrag(0);
      } finally {
        if (epoch == _epoch &&
            preparationEpoch == _preparationEpoch &&
            _preparingDirection == d) {
          _preparingNeighbor = null;
          _preparingDirection = null;
        }
      }
    }();
    _preparingNeighbor = ready;
    return ready;
  }

  int _epoch = 0;
  double get displacement => _handoff
      ? 0
      : _settling
      ? ui.lerpDouble(_from, _to, _slideProgress(controller.value))!
      : _dragOffset;
  late final AnimationController controller = AnimationController.unbounded(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );

  bool beginDrag() {
    if (!widget.enabled || _waitingForSheet || waitingForNeighbor) return false;
    _initialMotion = 0;
    if (busy) {
      if (mode != 'slide' || (!_settling && !_committing)) return false;
      // A new gesture belongs to the next sheet, not the unfinished old turn.
      // Finish an accepted turn once, then buffer motion until Flutter binds
      // its prepared sheet. A restoring turn completes without a commit.
      _epoch++;
      final epoch = _epoch;
      controller.stop(canceled: true);
      final complete = _settleCommit;
      _settleCommit = null;
      _dragOffset = _to;
      _settling = false;
      _committing = _waitingForSheet = true;
      _queuedTravel = 0;
      complete?.call();
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || epoch != _epoch || !widget.enabled) return;
        final travel = _queuedTravel;
        final release = _queuedRelease;
        _queuedRelease = null;
        _waitingForSheet = _committing = _handoff = false;
        _incoming = null;
        _rawDrag = _dragOffset = 0;
        _dragging = true;
        updateDrag(travel);
        if (release != null) {
          unawaited(
            endDrag(release.velocity, release.commit).whenComplete(() {
              if (!release.done.isCompleted) release.done.complete();
            }),
          );
        }
      });
      return true;
    }
    _rawDrag = _dragOffset = 0;
    busy = true;
    _dragging = true;
    mode = 'slide';
    return true;
  }

  void updateDrag(double dx) {
    if (_waitingForSheet) {
      _queuedTravel += dx;
      return;
    }
    if (!_dragging || !widget.enabled || _width <= 0) return;
    if (_initialMotion == 0 && dx != 0) _initialMotion = dx;
    _rawDrag += dx;
    final nextDirection = _rawDrag <= 0 ? 1 : -1;
    final oldIncoming = _incoming;
    final oldDirection = direction;
    if (_incoming == null || direction != nextDirection) {
      direction = nextDirection;
      _incoming = _neighbor(direction);
      if (_incoming == null &&
          _neighborState(direction) == ReaderNeighborState.loading) {
        unawaited(_prepareNeighbor(direction));
      }
    }
    final offset = _incoming == null ? 0.0 : _rawDrag.clamp(-_width, _width);
    // At a book edge, native pagers stop before requesting another draw.
    if (offset == _dragOffset &&
        identical(oldIncoming, _incoming) &&
        (_incoming == null || direction == oldDirection)) {
      return;
    }
    setState(() => _dragOffset = offset);
  }

  Future<void> endDrag(double velocity, ValueChanged<int> commit) async {
    if (_waitingForSheet) {
      _queuedRelease?.done.complete();
      final release = _DeferredRelease(velocity, commit);
      _queuedRelease = release;
      await release.done.future;
      return;
    }
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
    // Readium compares initial and release velocity signs. Here the first
    // nonzero drag delta supplies the initial direction; retain distance-based
    // slow dragging and zero-velocity release instead of its fling-only gate.
    final reversing = _initialMotion * velocity < 0;
    final accept =
        widget.enabled &&
        !reversing &&
        (travel.abs() >= _width * .22 ||
            velocity * direction <= -650 ||
            (projected * direction < 0 && projected.abs() >= _width * .3));
    // At a book boundary there is no fictional page to animate.
    if (_incoming == null) {
      if (accept && _neighborState(direction) == ReaderNeighborState.loading) {
        final epoch = _epoch;
        await _prepareNeighbor(direction);
        if (!mounted || epoch != _epoch || !widget.enabled) return;
        _incoming = _neighbor(direction);
        if (_incoming != null) {
          setState(() => _dragOffset = travel.clamp(-_width, _width));
          await WidgetsBinding.instance.endOfFrame;
          if (!mounted || epoch != _epoch || !widget.enabled) return;
        }
      }
      if (_incoming == null) {
        if (accept &&
            _neighborState(direction) == ReaderNeighborState.boundary) {
          commit(direction);
        }
        _reset();
        _drain();
        return;
      }
    }
    final target = accept ? -direction * _width : 0.0;
    await _settle(
      target,
      accept ? () => commit(direction) : null,
      velocity: velocity,
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
      _incoming = _neighbor(direction);
      if (_incoming == null &&
          _neighborState(direction) == ReaderNeighborState.loading) {
        await _prepareNeighbor(direction);
        if (!mounted || epoch != _epoch || !widget.enabled) return;
        _incoming = _neighbor(direction);
      }
      if (_incoming == null) {
        if (_neighborState(direction) == ReaderNeighborState.boundary) {
          request.action();
        }
        return;
      }
      if (mode == 'none' || MediaQuery.disableAnimationsOf(context)) {
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
    _pagerSettling = mode == 'slide';
    _settling = true;
    _settleCommit = commit;
    final settleDuration = _pagerSettling
        ? readerPagerDuration(distance, _width, velocity ?? 0)
        : duration;
    controller.duration = settleDuration;
    setState(() {});
    try {
      if ((_to - _from).abs() >= .01 &&
          !MediaQuery.disableAnimationsOf(context)) {
        await controller.animateTo(1, duration: settleDuration).orCancel;
      } else {
        controller.value = 1;
      }
      if (!mounted || epoch != _epoch || !widget.enabled) return;
      if (commit != null) {
        _settleCommit = null;
        _committing = true;
        commit();
        // Keep the completed incoming page until the new child has painted.
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted || epoch != _epoch) return;
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
    // Invalidates a loading callback after a short/cancelled gesture as well
    // as animations. Its eventual result must not drive a later gesture.
    _preparationEpoch++;
    final visualChange =
        snapshot != null ||
        _incoming != null ||
        _dragOffset != 0 ||
        _settling ||
        _committing ||
        _handoff;
    void clear() {
      snapshot?.dispose();
      snapshot = null;
      _incoming = null;
      _settleCommit = null;
      _queuedRelease?.done.complete();
      _queuedRelease = null;
      _waitingForSheet = false;
      _queuedTravel = 0;
      _initialMotion = 0;
      _preparingNeighbor = null;
      _preparingDirection = null;
      _dragging = _settling = _committing = busy = false;
      _handoff = false;
      _dragOffset = _rawDrag = 0;
    }

    if (visualChange) {
      setState(clear);
    } else {
      clear();
    }
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
    if (_committing && oldWidget.pageIdentity != widget.pageIdentity) {
      // The incoming sheet has become current. Keep its existing subtree at
      // zero instead of painting a second paragraph for the committed page.
      _handoff = true;
    }
    if (!widget.enabled ||
        (!_committing && oldWidget.pageIdentity != widget.pageIdentity)) {
      cancel();
    }
  }

  @override
  void dispose() {
    _epoch++;
    _queuedRelease?.done.complete();
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
            final identities = {_identity(0), _identity(-1), _identity(1)};
            _sheetKeys.removeWhere((id, _) => !identities.contains(id));
            Widget sheet(
              int d,
              Widget child, {
              required bool visible,
            }) => Transform.translate(
              key: ValueKey(('reader-sheet', _identity(d))),
              offset: Offset(imageEffect ? 0 : dx + d * _width, 0),
              child: Offstage(
                // For slide, even clipped neighbors record their whole
                // display list at rest. They still cannot receive input or
                // semantics. Snapshot effects retain their visibility rules.
                offstage: imageEffect && !visible,
                child: ExcludeSemantics(
                  excluding: d != 0,
                  child: IgnorePointer(
                    ignoring: d != 0,
                    child: RepaintBoundary(
                      key: _sheetKey(_identity(d)),
                      child: ColoredBox(color: widget.color, child: child),
                    ),
                  ),
                ),
              ),
            );
            return Stack(
              fit: StackFit.expand,
              children: [
                sheet(0, widget.child, visible: !imageEffect || _handoff),
                for (final d in [-1, 1])
                  // Promote the prepared sheet first. Bind the new far-side
                  // paragraph after handoff, so its first layout/paint cannot
                  // share the landing frame with the visible page.
                  if ((!_committing || _sheetKeys.containsKey(_identity(d))) &&
                      ((d > 0 ? widget.next : widget.previous) != null ||
                          (!_handoff && direction == d && _incoming != null)))
                    sheet(
                      d,
                      !_handoff && direction == d && _incoming != null
                          ? _incoming!
                          : (d > 0 ? widget.next : widget.previous) ??
                                _incoming!,
                      visible: !_handoff && direction == d && _incoming != null,
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
