import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shuye_reader/page_turn.dart';
import 'package:shuye_reader/reader.dart';
import 'package:shuye_reader/reader_gestures.dart';

/// Neighbors are painted outside the clip so their display lists are ready.
/// Scope user-visible assertions to the actual current sheet.
Finder currentReaderSheet(WidgetTester tester) {
  final surface = tester.widget<PageTurnSurface>(find.byType(PageTurnSurface));
  return find.byKey(ValueKey(('reader-sheet', surface.pageIdentity!)));
}

Finder currentReaderText(WidgetTester tester) => find.descendant(
  of: currentReaderSheet(tester),
  matching: find.byType(SelectableText),
);

Future<void> revealReaderControls(WidgetTester tester) async {
  if (find
      .descendant(
        of: find.byType(ReaderScreen),
        matching: find.byTooltip('阅读设置'),
      )
      .evaluate()
      .isNotEmpty) {
    return;
  }
  final surface = find.byType(ReaderTapSurface).first;
  await tester.tapAt(tester.getCenter(surface));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}
