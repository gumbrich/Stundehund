import 'dart:ui' as ui;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stundehund/app.dart';
import 'package:stundehund/model.dart';
import 'package:stundehund/storage.dart';
import 'package:stundehund/tracker.dart';

class MemoryStore implements TrackerStore {
  @override
  Future<void> save(TrackerData data) async {}
}

void main() {
  testWidgets('workday controls, project creation and compact mode', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1120, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var now = DateTime(2026, 10, 11, 8);
    final tracker = Tracker(
      TrackerData.empty(),
      MemoryStore(),
      clock: () => now,
    );
    await tester.pumpWidget(StundehundApp(tracker: tracker));
    expect(find.text('Dein Tag im Blick.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('start-stop')));
    await tester.pumpAndSettle();
    expect(tracker.data.active?.projectId, otherId);
    now = now.add(const Duration(minutes: 30));
    await tester.tap(find.byKey(const Key('pause')));
    await tester.pumpAndSettle();
    expect(tracker.data.active?.isBreak, true);
    await tester.tap(find.byKey(const Key('start-stop')));
    await tester.pumpAndSettle();
    expect(tracker.data.active, null);
    await tester.tap(find.text('Projekte'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Projekt hinzufügen'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'Brückenbau');
    await tester.enterText(find.byType(TextFormField).at(1), 'P-102');
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(tracker.data.projects.last.name, 'Brückenbau');
    await tester.tap(find.byKey(const Key('compact')));
    await tester.pumpAndSettle();
    await tester.binding.setSurfaceSize(const Size(760, 202));
    await tester.pumpAndSettle();
    expect(find.text('Dein Tag im Blick.'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    tracker.dispose();
  });
  testWidgets('dashboard and export settings render with real records', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1120, 820));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime(2026, 10, 11, 14, 30);
    final projects = [
      ...TrackerData.empty().projects,
      const Project(
        id: 'a',
        name: 'Projekt Alpenblick',
        code: 'P-2401',
        color: 0xFF496CE8,
      ),
      const Project(
        id: 'b',
        name: 'Website Relaunch',
        code: 'P-2402',
        color: 0xFF2A9576,
      ),
      const Project(
        id: 'c',
        name: 'Team & Planung',
        code: 'P-2403',
        color: 0xFFCC8750,
      ),
    ];
    final entries = [
      TimeEntry(
        id: '1',
        start: DateTime(2026, 10, 11, 8),
        end: DateTime(2026, 10, 11, 10, 15),
        projectId: 'a',
      ),
      TimeEntry(
        id: '2',
        start: DateTime(2026, 10, 11, 10, 15),
        end: DateTime(2026, 10, 11, 10, 30),
      ),
      TimeEntry(
        id: '3',
        start: DateTime(2026, 10, 11, 10, 30),
        end: DateTime(2026, 10, 11, 12),
        projectId: 'b',
      ),
      TimeEntry(
        id: '4',
        start: DateTime(2026, 10, 11, 12),
        end: DateTime(2026, 10, 11, 12, 45),
      ),
      TimeEntry(
        id: '5',
        start: DateTime(2026, 10, 11, 12, 45),
        end: DateTime(2026, 10, 11, 13, 30),
        projectId: 'c',
      ),
      TimeEntry(id: '6', start: DateTime(2026, 10, 11, 13, 30), projectId: 'a'),
    ];
    final tracker = Tracker(
      TrackerData(projects: projects, entries: entries, lastProject: 'a'),
      MemoryStore(),
      clock: () => now,
    );
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: StundehundApp(tracker: tracker),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    if (Platform.environment['STUNDEHUND_SCREENSHOT'] == '1') {
      await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('build').create(recursive: true);
        await File(
          'build/dashboard.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.tap(find.text('Exportprofil'));
    await tester.pumpAndSettle();
    expect(find.text('Spalten & Reihenfolge'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.binding.setSurfaceSize(const Size(760, 600));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    tracker.dispose();
  });
  testWidgets(
    'previous days can be edited without changing the active project',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1120, 950));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final now = DateTime(2026, 10, 23, 12);
      final tracker = Tracker(
        TrackerData.empty().copy(
          entries: [
            TimeEntry(
              id: 'yesterday',
              start: DateTime(2026, 10, 22, 9),
              end: DateTime(2026, 10, 22, 10),
              projectId: otherId,
            ),
            TimeEntry(
              id: 'today',
              start: DateTime(2026, 10, 23, 10),
              end: DateTime(2026, 10, 23, 11),
              projectId: otherId,
            ),
          ],
        ),
        MemoryStore(),
        clock: () => now,
      );
      await tracker.start();
      final activeId = tracker.data.active!.id;
      await tester.pumpWidget(StundehundApp(tracker: tracker));
      await tester.pumpAndSettle();
      expect(find.text('AKTIV · Anderes'), findsOneWidget);
      await tester.tap(find.byKey(const Key('previous-day')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('entry-yesterday')));
      await tester.tap(find.byKey(const Key('entry-yesterday')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(3), '10:15:00');
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();
      expect(
        tracker.data.entries
            .firstWhere((e) => e.id == 'yesterday')
            .duration(now)
            .inMinutes,
        75,
      );
      expect(tracker.data.active!.id, activeId);
      await tester.ensureVisible(find.text('F9-Texte für diesen Tag'));
      await tester.tap(find.text('F9-Texte für diesen Tag'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Projektkoordination'));
      await tester.enterText(
        find.byKey(const Key('day-note-other')),
        'Projektkoordination; eigene Ergänzung',
      );
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();
      expect(
        tracker.data.notesForDay(DateTime(2026, 10, 22), otherId, now),
        'Projektkoordination; eigene Ergänzung',
      );
      expect(tracker.data.notesForDay(now, otherId, now), '');
      await tester.ensureVisible(find.byKey(const Key('today')));
      await tester.tap(find.byKey(const Key('today')));
      await tester.pumpAndSettle();
      expect(find.text('Dein Tag im Blick.'), findsOneWidget);
      await tester.tap(find.text('Einstellungen'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('animal-owl')));
      await tester.pumpAndSettle();
      expect(tracker.data.animal, 'owl');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      tracker.dispose();
    },
  );

  testWidgets('day deletion requires confirmation and can be restored', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1120, 950));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final now = DateTime(2026, 10, 23, 12);
    final tracker = Tracker(
      TrackerData.empty().copy(
        entries: [
          TimeEntry(
            id: 'today',
            start: DateTime(2026, 10, 23, 10),
            end: DateTime(2026, 10, 23, 11),
            projectId: otherId,
          ),
        ],
      ),
      MemoryStore(),
      clock: () => now,
    );
    await tester.pumpWidget(StundehundApp(tracker: tracker));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tag löschen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(tracker.data.entries.length, 1);
    await tester.tap(find.text('Tag löschen'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Tag löschen'));
    await tester.pumpAndSettle();
    expect(tracker.data.entries, isEmpty);
    await tester.tap(find.text('Einstellungen'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Wiederherstellen'));
    await tester.tap(find.text('Wiederherstellen'));
    await tester.pumpAndSettle();
    expect(tracker.data.entries.single.duration(now).inHours, 1);
    await tester.pumpWidget(const SizedBox());
    tracker.dispose();
  });
}
