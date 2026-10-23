import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:stundehund/model.dart';
import 'package:stundehund/storage.dart';
import 'package:stundehund/tracker.dart';
import 'package:stundehund/csv_export.dart';
import 'package:stundehund/window_geometry.dart';

class TestStore implements TrackerStore {
  TrackerData? saved;
  bool fail = false;
  @override
  Future<void> save(TrackerData data) async {
    if (fail) throw StateError('Disk full');
    saved = TrackerData.fromJson(data.toJson());
  }
}

void main() {
  late DateTime now;
  late TestStore store;
  late Tracker tracker;
  setUp(() {
    now = DateTime(2026, 10, 23, 10);
    store = TestStore();
    tracker = Tracker(TrackerData.empty(), store, clock: () => now);
  });
  tearDown(() => tracker.dispose());

  test('mode switches keep the exact anchor including a secondary screen', () {
    final geometry = WindowGeometry();
    var bounds = const Rect.fromLTWH(-1200, 80, 1000, 700);
    for (var i = 0; i < 10; i++) {
      bounds = geometry.forMode(bounds, compact: true);
      expect(bounds, const Rect.fromLTWH(-1200, 80, 1000, compactBarHeight));
      bounds = geometry.forMode(bounds, compact: false);
      expect(bounds, const Rect.fromLTWH(-1200, 80, 1000, 700));
    }
    geometry.forMode(bounds, compact: true);
    expect(
      geometry.forMode(
        const Rect.fromLTWH(150, 120, 1000, compactBarHeight),
        compact: false,
      ),
      const Rect.fromLTWH(150, 120, 1000, 700),
    );
  });
  test('old files migrate to quarter hours and include the F9 column', () {
    final json = tracker.data.toJson()
      ..remove('animal')
      ..remove('dayNotes')
      ..remove('deletedTimes');
    final profile = json['profile'] as Map<String, dynamic>;
    profile.remove('rounding');
    (profile['columns'] as List).removeWhere((c) => c['field'] == 'note');
    final loaded = TrackerData.fromJson(json);
    expect(loaded.animal, 'dog');
    expect(loaded.profile.rounding, 'nearest');
    expect(loaded.profile.columns.last.field, ExportField.note);
    expect(loaded.entries, isEmpty);
  });
  test('animal and manual F9 text persist through reload', () async {
    await tracker.saveAnimal('squirrel');
    await tracker.saveDayNotes(now, {
      otherId: 'Projektkoordination; eigene Stichworte',
    });
    final loaded = store.saved!;
    expect(loaded.animal, 'squirrel');
    expect(
      loaded.notesForDay(now, otherId, now),
      'Projektkoordination; eigene Stichworte',
    );
    expect(await tracker.saveAnimal('unknown'), false);
  });
  test('F9 edits during an active session preserve its elapsed time', () async {
    await tracker.start();
    final start = tracker.data.active!.start;
    now = now.add(const Duration(minutes: 20));
    await tracker.saveDayNotes(now, {otherId: 'Abstimmung intern'});
    expect(tracker.data.active!.start, start);
    expect(tracker.data.active!.duration(now).inMinutes, 20);
  });
  test(
    'current-day deletion stops recording and is recoverable after restart',
    () async {
      await tracker.start();
      now = now.add(const Duration(minutes: 20));
      await tracker.saveDayNotes(now, {otherId: 'Abstimmung extern'});
      expect(await tracker.deleteDay(now), true);
      expect(tracker.data.active, isNull);
      expect(tracker.data.entries, isEmpty);
      expect(tracker.data.dayNotes, isEmpty);
      final reloaded = Tracker(store.saved!, store, clock: () => now);
      expect(await reloaded.restoreDeletedTimes(), true);
      expect(reloaded.data.entries.single.duration(now).inMinutes, 20);
      expect(reloaded.data.active, isNull);
      expect(reloaded.data.notesForDay(now, otherId, now), 'Abstimmung extern');
      reloaded.dispose();
    },
  );
  test(
    'deleting a middle day clips only that day and restores without overlap',
    () async {
      tracker.data = tracker.data.copy(
        entries: [
          TimeEntry(
            id: 'overnight',
            start: DateTime(2026, 10, 21, 23),
            end: DateTime(2026, 10, 23, 1),
            projectId: otherId,
          ),
        ],
      );
      await tracker.deleteDay(DateTime(2026, 10, 22));
      expect(tracker.data.entries.length, 2);
      expect(
        tracker.data.entries.fold(
          0,
          (sum, e) => sum + e.duration(now).inMinutes,
        ),
        120,
      );
      expect(entriesForDay(tracker.data, DateTime(2026, 10, 22), now), isEmpty);
      await tracker.restoreDeletedTimes();
      expect(
        tracker.data.entries.fold(0, (sum, e) => sum + e.duration(now).inHours),
        26,
      );
    },
  );
  test(
    'deleting yesterday preserves the active portion of an overnight session',
    () async {
      now = DateTime(2026, 10, 22, 23);
      await tracker.start();
      now = DateTime(2026, 10, 23, 1);
      await tracker.deleteDay(DateTime(2026, 10, 22));
      expect(tracker.data.active!.start, DateTime(2026, 10, 23));
      expect(tracker.data.active!.duration(now).inHours, 1);
    },
  );
  test(
    'reset keeps projects and preferences; undo preserves newly recorded work',
    () async {
      await tracker.saveAnimal('owl');
      await tracker.start();
      now = now.add(const Duration(minutes: 20));
      await tracker.resetTimes();
      expect(tracker.data.projects.length, 1);
      expect(tracker.data.animal, 'owl');
      expect(tracker.data.entries, isEmpty);
      now = now.add(const Duration(minutes: 5));
      await tracker.start();
      now = now.add(const Duration(minutes: 10));
      await tracker.stop();
      await tracker.restoreDeletedTimes();
      expect(tracker.data.entries.length, 2);
      expect(
        tracker.data.entries.fold(
          0,
          (sum, e) => sum + e.duration(now).inMinutes,
        ),
        30,
      );
    },
  );
  test(
    'undo rejects overlap with corrections entered after deleting',
    () async {
      await tracker.start();
      now = now.add(const Duration(minutes: 30));
      await tracker.resetTimes();
      await tracker.saveEntry(
        TimeEntry(
          id: 'replacement',
          start: now.subtract(const Duration(minutes: 10)),
          end: now,
          projectId: otherId,
        ),
      );
      expect(await tracker.restoreDeletedTimes(), false);
      expect(tracker.data.entries.single.id, 'replacement');
      expect(tracker.data.deletedTimes, isNotNull);
    },
  );
  test(
    'failed delete cannot lose records or the previous recovery point',
    () async {
      await tracker.start();
      now = now.add(const Duration(minutes: 15));
      await tracker.stop();
      store.fail = true;
      expect(await tracker.deleteDay(now), false);
      expect(tracker.data.entries.single.duration(now).inMinutes, 15);
      expect(tracker.data.deletedTimes, isNull);
    },
  );
  test('nearest and upward rounding are exact at quarter-hour boundaries', () {
    expect(
      CsvExport.rounded(const Duration(minutes: 7, seconds: 29), 'nearest'),
      Duration.zero,
    );
    expect(
      CsvExport.rounded(const Duration(minutes: 7, seconds: 30), 'nearest'),
      const Duration(minutes: 15),
    );
    expect(
      CsvExport.rounded(const Duration(minutes: 22, seconds: 30), 'nearest'),
      const Duration(minutes: 30),
    );
    expect(
      CsvExport.rounded(const Duration(minutes: 15), 'up'),
      const Duration(minutes: 15),
    );
    expect(
      CsvExport.rounded(const Duration(minutes: 15, milliseconds: 1), 'up'),
      const Duration(minutes: 30),
    );
  });
  test(
    'project intervals aggregate before rounding and F9 text reaches CSV',
    () async {
      tracker.data = tracker.data.copy(
        entries: [
          TimeEntry(
            id: '1',
            start: DateTime(2026, 10, 23, 8),
            end: DateTime(2026, 10, 23, 8, 5),
            projectId: otherId,
          ),
          TimeEntry(
            id: '2',
            start: DateTime(2026, 10, 23, 8, 10),
            end: DateTime(2026, 10, 23, 8, 15),
            projectId: otherId,
          ),
        ],
      );
      await tracker.saveDayNotes(now, {
        otherId: 'Controlling & Rechnungsstellung; "Test"',
      });
      final rows = CsvExport.rowsForDay(
        tracker.data,
        now,
        now,
        profile: const ExportProfile(summary: false),
      );
      expect(rows.length, 1);
      expect(rows.single.rawDuration.inMinutes, 10);
      expect(rows.single.duration.inMinutes, 15);
      final csv = CsvExport.create(tracker.data, now, now);
      expect(csv, contains('0.25'));
      expect(csv, contains('"Controlling & Rechnungsstellung; ""Test"""'));
      expect(tracker.data.entries.first.duration(now).inMinutes, 5);
    },
  );
  test(
    'export requires F9 text and reports days rounded entirely to zero',
    () async {
      await tracker.start();
      now = now.add(const Duration(minutes: 3));
      await tracker.stop();
      expect(() => CsvExport.create(tracker.data, now, now), throwsStateError);
      await tracker.saveDayNotes(now, {otherId: 'Projektkoordination'});
      expect(() => CsvExport.create(tracker.data, now, now), throwsStateError);
      expect(
        CsvExport.create(
          tracker.data,
          now,
          now,
          profile: const ExportProfile(rounding: 'up'),
        ),
        contains('0.25'),
      );
    },
  );
}
