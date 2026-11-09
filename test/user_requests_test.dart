import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stundehund/app.dart';
import 'package:stundehund/dialogs.dart';
import 'package:stundehund/entry_times.dart';
import 'package:stundehund/model.dart';
import 'package:stundehund/power_events.dart';
import 'package:stundehund/storage.dart';
import 'package:stundehund/tracker.dart';
import 'package:stundehund/window_geometry.dart';

class RequestStore implements TrackerStore {
  TrackerData? saved;
  Completer<void>? gate;
  bool fail = false;
  @override
  Future<void> save(TrackerData data) async {
    await gate?.future;
    if (fail) throw StateError('disk full');
    saved = TrackerData.fromJson(data.toJson());
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DateTime now;
  late RequestStore store;
  late Tracker tracker;
  setUp(() {
    now = DateTime(2026, 11, 9, 10, 15, 12, 345);
    store = RequestStore();
    tracker = Tracker(TrackerData.empty(), store, clock: () => now);
  });
  tearDown(() => tracker.dispose());

  test(
    'order persists, skips archived projects and survives project editing',
    () async {
      await tracker.saveProject(const Project(id: 'a', name: 'A', color: 0));
      await tracker.saveProject(
        const Project(id: 'hidden', name: 'Hidden', color: 0, archived: true),
      );
      await tracker.saveProject(const Project(id: 'b', name: 'B', color: 0));
      await tracker.reorderProjects(2, 0);
      expect(tracker.data.projects.map((p) => p.id), [
        'b',
        otherId,
        'hidden',
        'a',
      ]);
      await tracker.saveProject(
        const Project(id: 'b', name: 'Renamed', color: 1),
      );
      expect(store.saved!.projects.map((p) => p.id), [
        'b',
        otherId,
        'hidden',
        'a',
      ]);
      store.fail = true;
      expect(await tracker.reorderProjects(0, 3), false);
      expect(tracker.data.projects.first.id, 'b');
    },
  );

  test(
    'short sleep uses native event time, stops breaks and never restarts',
    () async {
      await tracker.start();
      now = now.add(const Duration(minutes: 2));
      await tracker.pauseOrResume();
      final cutoff = now.add(const Duration(seconds: 5));
      now = cutoff.add(const Duration(seconds: 20));
      PowerEvents.listen(tracker);
      addTearDown(PowerEvents.stopListening);
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            'stundehund/power',
            const StandardMethodCodec().encodeMethodCall(
              MethodCall('suspend', cutoff.millisecondsSinceEpoch),
            ),
            (_) {},
          );
      expect(tracker.data.active, isNull);
      expect(store.saved!.entries.last.end, cutoff);
      expect(store.saved!.notice, contains('automatisch gestoppt'));
      await tracker.pulse();
      expect(tracker.data.active, isNull);
      await tracker.start();
      await tracker.suspend(
        cutoff,
      ); // Delayed duplicate must not stop new work.
      expect(tracker.data.active, isNotNull);
    },
  );

  test('sleep during a pending save is not dropped', () async {
    await tracker.start();
    now = now.add(const Duration(minutes: 1));
    store.gate = Completer<void>();
    final saving = tracker.saveAnimal('owl');
    await tracker.suspend(now);
    final cutoff = now;
    now = now.add(const Duration(hours: 1));
    store.gate!.complete();
    await saving;
    expect(store.saved!.animal, 'owl');
    expect(store.saved!.active, isNull);
    expect(store.saved!.entries.single.end, cutoff);
  });

  test('failed sleep save retries with the original cutoff', () async {
    await tracker.start();
    now = now.add(const Duration(minutes: 1));
    final cutoff = now;
    store.fail = true;
    await tracker.suspend(cutoff);
    expect(tracker.error, isNotNull);
    store.fail = false;
    now = now.add(const Duration(hours: 1));
    await tracker.pulse();
    expect(store.saved!.entries.single.end, cutoff);
    expect(tracker.data.active, isNull);
  });

  test(
    'running start can be moved earlier, but not across another entry',
    () async {
      final previous = TimeEntry(
        id: 'previous',
        start: DateTime(2026, 11, 9, 8),
        end: DateTime(2026, 11, 9, 9),
        projectId: otherId,
      );
      await tracker.saveEntry(previous);
      await tracker.start();
      final id = tracker.data.active!.id;
      expect(
        await tracker.saveEntry(
          TimeEntry(id: id, start: previous.end!, projectId: otherId),
        ),
        true,
      );
      expect(tracker.data.active!.start, previous.end);
      expect(
        tracker.validateEntry(
          TimeEntry(id: id, start: previous.start, projectId: otherId),
        ),
        contains('Anderes'),
      );
      expect(
        tracker.validateEntry(
          TimeEntry(id: 'new', start: previous.start, projectId: otherId),
        ),
        contains('nicht mehr'),
      );
      await tracker.stop();
      expect(
        await tracker.saveEntry(
          TimeEntry(id: id, start: previous.end!, projectId: otherId),
        ),
        false,
      );
      expect(tracker.data.active, isNull);
    },
  );

  test('Swiss and ISO dates, short times and invalid calendar dates', () {
    expect(parseEntryTime('9.11.2026', '8:30'), DateTime(2026, 11, 9, 8, 30));
    expect(parseEntryTime('2026-11-09', '08.30'), DateTime(2026, 11, 9, 8, 30));
    expect(
      parseEntryTime('09.11.2026', '08:30:45'),
      DateTime(2026, 11, 9, 8, 30, 45),
    );
    for (final (date, time) in [
      ('31.02.2026', '08:30'),
      ('9.11.2026', '24:00'),
      ('9.11.2026', '8:60'),
    ]) {
      expect(parseEntryTime(date, time), isNull);
    }
    expect(displayDay(now), 'Mo, 09.11.2026');
    expect(displayDay(now.add(const Duration(days: 1))), 'Di, 10.11.2026');
  });

  test(
    'suggested backfill fits before active interval with exact boundary',
    () async {
      await tracker.start();
      now = now.add(const Duration(minutes: 20));
      final proposed = suggestedEntry(tracker, now);
      expect(proposed.end, tracker.data.active!.start);
      expect(tracker.validateEntry(proposed), isNull);
      expect(proposed.duration(now), const Duration(hours: 1));
    },
  );

  test(
    'compact width survives expansion without changing height or position',
    () {
      final geometry = WindowGeometry();
      geometry.forMode(const Rect.fromLTWH(-900, 40, 900, 700), compact: true);
      expect(
        geometry.forMode(
          const Rect.fromLTWH(-900, 40, 1200, compactBarHeight),
          compact: false,
        ),
        const Rect.fromLTWH(-900, 40, 1200, 700),
      );
    },
  );

  testWidgets(
    'dragging projects changes shortcut order without starting timer',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1120, 820));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tracker.saveProject(
        const Project(id: 'a', name: 'Alpha', color: 0xFF123456),
      );
      await tracker.saveProject(
        const Project(id: 'b', name: 'Beta', color: 0xFF654321),
      );
      await tester.pumpWidget(StundehundApp(tracker: tracker));
      await tester.pumpAndSettle();
      final first = tester.getCenter(
        find.byType(ReorderableDragStartListener).first,
      );
      final last = tester.getCenter(find.byKey(const Key('project-b')));
      final gesture = await tester.startGesture(first);
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
      await gesture.moveTo(last + const Offset(220, 0));
      await tester.pumpAndSettle();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tracker.data.projects.map((p) => p.id), ['a', 'b', otherId]);
      expect(tracker.data.active, isNull);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(tracker.data.active!.projectId, 'a');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'correct a running start and preserve fractional boundaries when editing notes',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1120, 950));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tracker.start();
      final id = tracker.data.active!.id;
      now = now.add(const Duration(seconds: 20));
      await tester.pumpWidget(StundehundApp(tracker: tracker));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(Key('entry-$id')));
      await tester.tap(find.byKey(Key('entry-$id')));
      await tester.pumpAndSettle();
      expect(find.text('Laufenden Eintrag korrigieren'), findsOneWidget);
      await tester.enterText(find.byType(TextField).at(1), '8:30');
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();
      expect(tracker.data.active!.start, DateTime(2026, 11, 9, 8, 30));
      expect(tracker.data.active!.id, id);
      await tracker.stop();
      final boundary = now;
      await tracker.start();
      now = now.add(const Duration(minutes: 5));
      await tracker.stop();
      await tester.pumpAndSettle();
      final second = tracker.data.entries.last;
      await tester.ensureVisible(find.byKey(Key('entry-${second.id}')));
      await tester.tap(find.byKey(Key('entry-${second.id}')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).last,
        'Korrigierte Bemerkung',
      );
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();
      expect(find.byType(EntryDialog), findsNothing);
      expect(tracker.data.entries.last.start, boundary);
      expect(tracker.data.entries.last.note, 'Korrigierte Bemerkung');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
