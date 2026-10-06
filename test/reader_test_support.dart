import 'package:flutter_test/flutter_test.dart';
import 'package:shuye_reader/reader.dart';
import 'package:shuye_reader/reader_gestures.dart';

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
