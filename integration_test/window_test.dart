import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:window_manager/window_manager.dart';
import 'package:stundehund/app.dart';
import 'package:stundehund/model.dart';
import 'package:stundehund/storage.dart';
import 'package:stundehund/tracker.dart';
import 'package:stundehund/window_geometry.dart';
import 'package:stundehund/power_events.dart';

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
        expect(await windowManager.isResizable(), isTrue);
        final wider = small.width + 60;
        await windowManager.setSize(Size(wider, compactBarHeight));
        await tester.pump(const Duration(milliseconds: 300));
        final resized = await windowManager.getBounds();
        expect(resized.width, closeTo(wider, 1));
        expect(resized.height, closeTo(compactBarHeight, 1));
        samePosition(resized, small);
        expect(tester.takeException(), isNull);
        await windowManager.minimize();
        await tester.pump(const Duration(milliseconds: 300));
        await windowManager.restore();
        await windowManager.focus();
        await tester.pump(const Duration(milliseconds: 300));
        samePosition(await windowManager.getBounds(), small);
        expect(tester.takeException(), isNull);
        await toggle();
        final full = await windowManager.getBounds();
        samePosition(full, original);
        expect(full.height, closeTo(original.height, 1));
        expect(full.width, closeTo(wider, 1));
        expect(await windowManager.isResizable(), isTrue);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
      await windowManager.setPreventClose(false);
      tracker.dispose();
    },
  );

  testWidgets(
    'native Windows lid and sleep messages stop and persist the timer',
    (tester) async {
      final directory = await Directory.systemTemp.createTemp(
        'stundehund-power-',
      );
      final store = FileStore(directory);
      final tracker = Tracker(await store.load(), store);
      PowerEvents.listen(tracker);
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));

      Future<void> emit(String event) async {
        await PowerEvents.channel.invokeMethod<void>(
          'simulatePowerEvent',
          event,
        );
        // Allow the native-to-Dart message and durable disk write to complete.
        for (var i = 0; i < 40; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(tracker.busy, isFalse);
        expect(tracker.error, isNull);
      }

      try {
        await tracker.start();
        await emit('lidOpened');
        expect(tracker.data.active, isNotNull);
        await emit('unrelated');
        expect(tracker.data.active, isNotNull);
        final beforeClose = DateTime.now().subtract(
          const Duration(milliseconds: 1),
        );
        await emit('lidClosed');
        final afterClose = DateTime.now();
        expect(tracker.data.active, isNull);
        final end = tracker.data.entries.single.end!;
        expect(end.isBefore(beforeClose), isFalse);
        expect(end.isAfter(afterClose), isFalse);
        expect(tracker.data.notice, contains('automatisch gestoppt'));

        await emit('lidClosed'); // Duplicate delivery is harmless.
        await emit('lidOpened');
        await emit('resume');
        await tracker.pulse();
        expect(tracker.data.active, isNull);
        expect(tracker.data.entries.single.end, end);

        // Also stop a running break, not just working time.
        await tracker.start();
        await tracker.pauseOrResume();
        expect(tracker.data.active!.isBreak, isTrue);
        await emit('suspend');
        expect(tracker.data.active, isNull);
        expect(tracker.data.entries.last.isBreak, isTrue);
        await emit('resume');
        expect(tracker.data.active, isNull);

        final expected = tracker.data.toJson();
        await store.close();
        final reopened = FileStore(directory);
        try {
          final loaded = await reopened.load();
          expect(loaded.toJson(), expected);
          expect(loaded.active, isNull);
        } finally {
          await reopened.close();
        }
      } finally {
        PowerEvents.stopListening();
        tracker.dispose();
        await store.close();
        await directory.delete(recursive: true);
        await tester.pumpWidget(const SizedBox());
      }
    },
    skip: !Platform.isWindows,
  );
}
