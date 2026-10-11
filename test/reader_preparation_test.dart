import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shuye_reader/reader_preparation.dart';

void main() {
  testWidgets(
    'both adjacent chapters share one page per frame and take turns',
    (tester) async {
      await tester.pumpWidget(const SizedBox());
      final queue = ReaderPreparationQueue();
      final supplied = <String>[];
      var first = 0, second = 0;
      final a = queue.run(
        () {
          if (first++ == 3) return ReaderWorkStep.complete;
          supplied.add('previous');
          return ReaderWorkStep.page;
        },
        isCurrent: () => true,
        shouldPause: () => false,
      );
      final b = queue.run(
        () {
          if (second++ == 3) return ReaderWorkStep.complete;
          supplied.add('next');
          return ReaderWorkStep.page;
        },
        isCurrent: () => true,
        shouldPause: () => false,
      );
      for (var i = 0; i < 12; i++) {
        final before = supplied.length;
        await tester.pump(const Duration(milliseconds: 16));
        expect(supplied.length - before, lessThanOrEqualTo(1));
      }
      expect(await a, true);
      expect(await b, true);
      expect(supplied, [
        'previous',
        'next',
        'previous',
        'next',
        'previous',
        'next',
      ]);
    },
  );
  testWidgets(
    'spare work waits across gestures; required page takes precedence',
    (tester) async {
      await tester.pumpWidget(const SizedBox());
      final queue = ReaderPreparationQueue();
      var dragging = true, valid = true, required = false;
      final supplied = <String>[];
      final spare = queue.run(
        () {
          supplied.add('spare');
          return ReaderWorkStep.complete;
        },
        isCurrent: () => valid,
        shouldPause: () => dragging,
      );
      final needed = queue.run(
        () {
          supplied.add('required');
          return ReaderWorkStep.complete;
        },
        isCurrent: () => valid,
        shouldPause: () => !required,
        isRequired: () => required,
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(supplied, isEmpty);
      required = true;
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      expect(supplied, ['required']);
      expect(await needed, true);
      dragging = false;
      await tester.pumpAndSettle(const Duration(milliseconds: 16));
      expect(await spare, true);
      expect(supplied, ['required', 'spare']);
      final stale = queue.run(
        () => fail('stale layout must not execute'),
        isCurrent: () => valid,
        shouldPause: () => false,
      );
      valid = false;
      await tester.pumpAndSettle();
      expect(await stale, false);
    },
  );
}
