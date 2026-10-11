import 'dart:async';
import 'dart:collection';

import 'package:flutter/widgets.dart';

/// All chapter preparation shares one small UI-isolate budget. This follows
/// readest/foliate-js 5003bbbd0fd2: yield between phases, recheck idle after
/// yielding, and let required boundary content bypass the idle grace period.
/// TextPainter cannot run on a background isolate or be preempted mid-call.
enum ReaderWorkStep { more, page, complete }

class ReaderPreparationQueue {
  final _jobs = Queue<_PreparationJob>();
  bool _running = false;
  Future<bool> run(
    ReaderWorkStep Function() step, {
    required bool Function() isCurrent,
    required bool Function() shouldPause,
    bool Function()? isRequired,
  }) {
    final job = _PreparationJob(step, isCurrent, shouldPause, isRequired);
    _jobs.add(job);
    if (!_running) unawaited(_drain());
    return job.done.future;
  }

  Future<void> _drain() async {
    _running = true;
    var idleFrames = 0;
    try {
      while (_jobs.isNotEmpty) {
        await WidgetsBinding.instance.endOfFrame;
        // endOfFrame resumes in a microtask. Give queued input an event-loop
        // turn, then check the gesture again before doing spare layout work.
        WidgetsBinding.instance.scheduleFrame();
        await Future<void>.delayed(Duration.zero);
        _jobs.removeWhere((job) {
          if (job.isCurrent()) return false;
          job.done.complete(false);
          return true;
        });
        if (_jobs.isEmpty) break;
        final urgent = _jobs
            .where((job) => job.required?.call() == true && !job.shouldPause())
            .firstOrNull;
        final paused = _jobs.every((job) => job.shouldPause());
        idleFrames = paused ? 0 : idleFrames + 1;
        if (urgent == null && (paused || idleFrames < 2)) continue;
        final job = urgent ?? _jobs.firstWhere((job) => !job.shouldPause());
        _jobs.remove(job);
        final work = Stopwatch()..start();
        var complete = false;
        try {
          do {
            final result = job.step();
            if (result == ReaderWorkStep.complete) {
              complete = true;
              job.done.complete(true);
              break;
            }
            if (result == ReaderWorkStep.page) break;
          } while (work.elapsedMicroseconds < 2000);
        } catch (error, stack) {
          complete = true;
          job.done.completeError(error, stack);
        }
        if (!complete) _jobs.addLast(job);
      }
    } finally {
      _running = false;
    }
  }
}

class _PreparationJob {
  final ReaderWorkStep Function() step;
  final bool Function() isCurrent, shouldPause;
  final bool Function()? required;
  final done = Completer<bool>();
  _PreparationJob(this.step, this.isCurrent, this.shouldPause, this.required);
}
