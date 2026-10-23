import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:window_manager/window_manager.dart';
import 'package:stundehund/app.dart';
import 'package:stundehund/model.dart';
import 'package:stundehund/storage.dart';
import 'package:stundehund/tracker.dart';
import 'package:stundehund/window_geometry.dart';

class IsolatedStore implements TrackerStore {
  @override
  Future<void> save(TrackerData data) async {}
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native compact, expand and minimise/restore keep window position',
    (tester) async {
      await windowManager.ensureInitialized();
      await windowManager.waitUntilReadyToShow(
        const WindowOptions(
          size: Size(900, 650),
          titleBarStyle: TitleBarStyle.hidden,
        ),
        () async {
          await windowManager.show();
          await windowManager.focus();
        },
      );
      await windowManager.setBounds(const Rect.fromLTWH(40, 40, 900, 650));
      final tracker = Tracker(TrackerData.empty(), IsolatedStore());
      await tester.pumpWidget(StundehundApp(tracker: tracker, desktop: true));
      await tester.pumpAndSettle();
      final original = await windowManager.getBounds();
      Future<void> toggle() async {
        await tester.tap(find.byKey(const Key('compact')));
        await tester.pump();
        for (var i = 0; i < 100; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          if (tester
                  .widget<IconButton>(find.byKey(const Key('compact')))
                  .onPressed !=
              null) {
            return;
          }
        }
        fail('Window layout transition timed out');
      }

      void samePosition(Rect actual, Rect expected) {
        expect(actual.left, closeTo(expected.left, 1));
        expect(actual.top, closeTo(expected.top, 1));
      }

      for (var i = 0; i < 3; i++) {
        await toggle();
        final small = await windowManager.getBounds();
        samePosition(small, original);
        expect(small.height, closeTo(compactBarHeight, 1));
        await windowManager.minimize();
        await tester.pump(const Duration(milliseconds: 300));
        await windowManager.restore();
        await windowManager.focus();
        await tester.pump(const Duration(milliseconds: 300));
        samePosition(await windowManager.getBounds(), small);
        await toggle();
        final full = await windowManager.getBounds();
        samePosition(full, original);
        expect(full.height, closeTo(original.height, 1));
      }
      await tester.pumpWidget(const SizedBox());
      await windowManager.setPreventClose(false);
      tracker.dispose();
    },
  );
}
