import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:stundehund/model.dart';
import 'package:stundehund/tracker.dart';
import 'package:stundehund/storage.dart';
import 'package:stundehund/csv_export.dart';

class MemoryStore implements TrackerStore {
  TrackerData? saved;
  bool fail = false;
  @override
  Future<void> save(TrackerData data) async {
    if (fail) {
      throw const FileSystemException('Disk full');
    }
    saved = TrackerData.fromJson(data.toJson());
  }
}

void main() {
  late DateTime now;
  late MemoryStore store;
  late Tracker tracker;
  setUp(() {
    now = DateTime(2026, 10, 11, 8);
    store = MemoryStore();
    tracker = Tracker(
      TrackerData.empty().copy(
        projects: [
          ...TrackerData.empty().projects,
          const Project(
            id: 'p1',
            name: 'Projekt; "Ä"',
            code: '0012',
            color: 0xFF496CE8,
          ),
        ],
      ),
      store,
      clock: () => now,
    );
  });
  tearDown(() => tracker.dispose());
  test(
    'switch, pause, resume and stop conserve working time without overlaps',
    () async {
      await tracker.start();
      now = now.add(const Duration(minutes: 15));
      await tracker.switchTo('p1');
      now = now.add(const Duration(minutes: 30));
      await tracker.pauseOrResume();
      now = now.add(const Duration(minutes: 10));
      await tracker.pauseOrResume();
      now = now.add(const Duration(minutes: 45));
      await tracker.stop();
      expect(tracker.data.active, isNull);
      expect(tracker.data.entries.length, 4);
      expect(
        tracker.data.entries
            .where((e) => !e.isBreak)
            .fold(0, (n, e) => n + e.duration(now).inMinutes),
        90,
      );
      expect(
        tracker.data.entries
            .where((e) => e.isBreak)
            .single
            .duration(now)
            .inMinutes,
        10,
      );
      for (var i = 1; i < tracker.data.entries.length; i++) {
        expect(tracker.data.entries[i].start, tracker.data.entries[i - 1].end);
      }
      expect(store.saved!.entries.length, 4);
    },
  );
  test('a backwards clock jump cannot create overlapping new work', () async {
    await tracker.start();
    now = now.add(const Duration(hours: 1));
    await tracker.stop();
    now = now.subtract(const Duration(minutes: 30));
    expect(await tracker.start(), false);
    expect(tracker.data.active, isNull);
    expect(tracker.error, contains('Systemzeit'));
  });
  test('clicking same project does not duplicate intervals', () async {
    await tracker.start('p1');
    now = now.add(const Duration(minutes: 1));
    await tracker.switchTo('p1');
    expect(tracker.data.entries.length, 1);
  });
  test('saving failure leaves last durable state and shows an error', () async {
    await tracker.start();
    now = now.add(const Duration(minutes: 1));
    store.fail = true;
    expect(await tracker.switchTo('p1'), false);
    expect(tracker.data.active!.projectId, otherId);
    expect(tracker.error, isNotNull);
    store.fail = false;
    expect(await tracker.stop(), true);
    expect(tracker.error, isNull);
  });
  test('restart ends an open interval at its durable heartbeat', () async {
    await tracker.start();
    now = now.add(const Duration(seconds: 30));
    await tracker.pulse();
    final lastSeen = now;
    now = now.add(const Duration(hours: 12));
    final reloaded = Tracker(store.saved!, store, clock: () => now);
    await reloaded.recover();
    expect(reloaded.data.active, isNull);
    expect(reloaded.data.entries.single.end, lastSeen);
    expect(reloaded.data.notice, isNotNull);
    reloaded.dispose();
  });
  test('suspension stops at the last observed tick', () async {
    await tracker.start('p1');
    now = now.add(const Duration(seconds: 1));
    await tracker.pulse();
    final last = now;
    now = now.add(const Duration(hours: 1));
    await tracker.pulse();
    expect(tracker.data.entries.single.end, last);
    expect(tracker.data.active, isNull);
  });
  test(
    'manual corrections reject overlap, future and inverted times',
    () async {
      await tracker.start();
      now = now.add(const Duration(hours: 1));
      await tracker.stop();
      final original = tracker.data.entries.single;
      expect(
        tracker.validateEntry(
          TimeEntry(id: 'x', start: original.start, end: now, projectId: 'p1'),
        ),
        isNotNull,
      );
      expect(
        tracker.validateEntry(
          TimeEntry(
            id: original.id,
            start: original.start,
            end: now.add(const Duration(minutes: 1)),
            projectId: otherId,
          ),
        ),
        isNotNull,
      );
      expect(
        tracker.validateEntry(
          TimeEntry(
            id: original.id,
            start: now,
            end: original.start,
            projectId: otherId,
          ),
        ),
        isNotNull,
      );
      expect(
        await tracker.saveEntry(
          TimeEntry(
            id: original.id,
            start: original.start.add(const Duration(minutes: 10)),
            end: now,
            projectId: 'p1',
          ),
        ),
        true,
      );
    },
  );
  test('midnight splits interval totals and CSV boundaries', () async {
    now = DateTime(2026, 10, 11, 23, 30);
    await tracker.start('p1');
    now = DateTime(2026, 10, 12, 0, 45);
    await tracker.stop();
    final first = entriesForDay(
      tracker.data,
      DateTime(2026, 10, 11),
      now,
    ).single;
    final second = entriesForDay(
      tracker.data,
      DateTime(2026, 10, 12),
      now,
    ).single;
    expect(first.duration(now).inMinutes, 30);
    expect(second.duration(now).inMinutes, 45);
    final csv = CsvExport.create(
      tracker.data,
      DateTime(2026, 10, 11),
      now,
      profile: const ExportProfile(
        summary: false,
        bom: false,
        columns: [
          ExportColumn(ExportField.start, 'Von'),
          ExportColumn(ExportField.end, 'Bis'),
        ],
      ),
    );
    expect(csv, 'Von;Bis\r\n23:30:00;24:00:00\r\n');
  });
  test(
    'CSV mapping, quoting, ordering, decimal comma and pause exclusion',
    () async {
      await tracker.start('p1');
      now = now.add(const Duration(minutes: 90));
      await tracker.pauseOrResume();
      now = now.add(const Duration(minutes: 15));
      await tracker.stop();
      final csv = CsvExport.create(
        tracker.data,
        now,
        now,
        profile: const ExportProfile(
          bom: false,
          decimalComma: true,
          columns: [
            ExportColumn(ExportField.projectName, 'Name'),
            ExportColumn(ExportField.duration, 'Menge'),
            ExportColumn(ExportField.projectCode, 'Code'),
          ],
        ),
      );
      expect(csv, 'Name;Menge;Code\r\n"Projekt; ""Ä""";1,5000;0012\r\n');
    },
  );
  test(
    'CSV aggregates repeated projects and never implies continuous work',
    () async {
      await tracker.start('p1');
      now = now.add(const Duration(minutes: 20));
      await tracker.switchTo(otherId);
      now = now.add(const Duration(minutes: 10));
      await tracker.switchTo('p1');
      now = now.add(const Duration(minutes: 10));
      await tracker.stop();
      final csv = CsvExport.create(
        tracker.data,
        now,
        now,
        profile: const ExportProfile(
          bom: false,
          columns: [
            ExportColumn(ExportField.duration, 'h'),
            ExportColumn(ExportField.start, 'Von'),
          ],
        ),
      );
      expect(csv, 'h;Von\r\n0.5000;\r\n0.1667;\r\n');
    },
  );
  test(
    'CSV rejects running day and supports previous closed midnight slice',
    () async {
      now = DateTime(2026, 10, 11, 23);
      await tracker.start();
      now = DateTime(2026, 10, 12, 1);
      expect(() => CsvExport.create(tracker.data, now, now), throwsStateError);
      expect(
        CsvExport.create(tracker.data, DateTime(2026, 10, 11), now),
        contains('1.0000'),
      );
    },
  );
  test(
    'archiving last project preserves history and changes next start to Anderes',
    () async {
      await tracker.start('p1');
      now = now.add(const Duration(minutes: 10));
      await tracker.stop();
      await tracker.saveProject(
        const Project(id: 'p1', name: 'Archived', color: 0, archived: true),
      );
      expect(tracker.data.entries.single.projectId, 'p1');
      await tracker.start();
      expect(tracker.data.active!.projectId, otherId);
    },
  );
  test('disk snapshots survive reload and a corrupt newest slot', () async {
    final dir = await Directory.systemTemp.createTemp('stundehund-test-');
    final disk = FileStore(dir);
    try {
      await disk.load();
      await disk.save(tracker.data);
      await disk.save(tracker.data.copy(lastSeen: now));
      await disk.close();
      await File('${dir.path}/time-0.json').writeAsString('{broken');
      final reload = FileStore(dir);
      final data = await reload.load();
      expect(data.projects.length, 2);
      expect(data.lastSeen, isNull);
      expect(data.notice, isNotNull);
      await reload.close();
    } finally {
      await disk.close();
      await dir.delete(recursive: true);
    }
  });
  test('unreadable data is not overwritten with empty state', () async {
    final dir = await Directory.systemTemp.createTemp('stundehund-test-');
    final disk = FileStore(dir);
    try {
      await File('${dir.path}/time-1.json').writeAsString('bad');
      await expectLater(disk.load(), throwsA(isA<FileSystemException>()));
      expect(await File('${dir.path}/time-1.json').readAsString(), 'bad');
    } finally {
      await disk.close();
      await dir.delete(recursive: true);
    }
  });
}
