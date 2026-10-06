import 'dart:async';

/// One write in flight, with newer column values replacing pending ones.
/// A failed snapshot stays available for retry or backup/exit flush.
class ProgressQueue {
  final Future<void> Function(Map<String, Object?>) write;
  Map<String, Object?>? _pending;
  Future<void>? _saving;
  ProgressQueue(this.write);

  Future<void> save(Map<String, Object?> values) {
    _pending = Map.unmodifiable({...?_pending, ...values});
    return flush();
  }

  Future<void> flush() {
    if (_saving != null) return _saving!;
    if (_pending == null) return Future.value();
    return _saving = _drain();
  }

  Future<void> _drain() async {
    try {
      while (_pending != null) {
        final snapshot = _pending!;
        await Future<void>.sync(() => write(snapshot));
        if (identical(_pending, snapshot)) _pending = null;
      }
    } finally {
      _saving = null;
    }
  }
}
