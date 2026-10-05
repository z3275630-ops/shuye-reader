import 'dart:async';

typedef ReadingTimeWriter = Future<void> Function(
  String bookId,
  int seconds,
  DateTime at,
);

// Keep failed batches at their original date/hour. A repository owns this queue,
// so leaving a reader does not discard a batch awaiting the next save attempt.
class ReadingTimeQueue {
  final ReadingTimeWriter write;
  final _pending = <(String, int, DateTime)>[];
  Future<void>? _saving;
  ReadingTimeQueue(this.write);

  Future<void> record(String bookId, int seconds, DateTime at) {
    if (seconds > 0) _pending.add((bookId, seconds, at));
    return flush();
  }

  Future<void> flush() {
    if (_saving != null) return _saving!;
    if (_pending.isEmpty) return Future.value();
    return _saving = _drain();
  }

  Future<void> _drain() async {
    try {
      while (_pending.isNotEmpty) {
        final batch = _pending.first;
        await write(batch.$1, batch.$2, batch.$3);
        _pending.removeAt(0);
      }
    } finally {
      _saving = null;
    }
  }
}
