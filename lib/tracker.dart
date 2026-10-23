import 'package:flutter/foundation.dart';
import 'model.dart';
import 'storage.dart';

class Tracker extends ChangeNotifier {
  Tracker(this.data, this.store, {DateTime Function()? clock})
    : clock = clock ?? DateTime.now;
  TrackerData data;
  final TrackerStore store;
  final DateTime Function() clock;
  bool busy = false;
  String? error;
  int _counter = 0;
  DateTime? _previousTick;
  String nextId() => '${clock().microsecondsSinceEpoch}-${_counter++}';
  Future<bool> _commit(TrackerData next) async {
    if (busy) {
      return false;
    }
    busy = true;
    notifyListeners();
    try {
      await store.save(next);
      data = next;
      error = null;
      return true;
    } catch (_) {
      error =
          'Speichern fehlgeschlagen. Die Änderung wurde nicht übernommen. Bitte Speicherplatz und Zugriffsrechte prüfen.';
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> recover() async {
    final active = data.active;
    if (active != null) {
      final now = clock();
      var end = data.lastSeen ?? active.start;
      if (end.isAfter(now)) {
        end = now;
      }
      await _commit(
        data.copy(
          entries: [
            ...data.entries.where((e) => e.id != active.id),
            active.finish(end),
          ],
          lastSeen: now,
          notice:
              'Die vorherige Sitzung wurde beim letzten Speicherpunkt beendet. Bitte die Endzeit prüfen und den Arbeitstag erneut starten.',
        ),
      );
    }
    _previousTick = clock();
  }

  Future<void> pulse() async {
    if (busy) {
      return;
    }
    final now = clock();
    final previous = _previousTick ?? now;
    _previousTick = now;
    final active = data.active;
    if (active == null) {
      notifyListeners();
      return;
    }
    final gap = now.difference(previous);
    if (gap > const Duration(seconds: 90) || gap.isNegative) {
      // Never silently charge suspension or a clock jump to a project.
      final cutoff = previous.isBefore(active.start) ? active.start : previous;
      final entries = [
        ...data.entries.where((e) => e.id != active.id),
        active.finish(cutoff),
      ];
      await _commit(
        data.copy(
          entries: entries,
          lastSeen: now,
          notice:
              'Eine Unterbrechung oder Zeitumstellung wurde erkannt. Die Erfassung wurde angehalten. Bitte die letzte Endzeit prüfen.',
        ),
      );
    } else if (data.lastSeen == null ||
        now.difference(data.lastSeen!) >= const Duration(seconds: 30)) {
      await _commit(data.copy(lastSeen: now));
    } else {
      notifyListeners();
    }
  }

  Future<bool> start([String? project]) =>
      switchTo(project ?? data.lastProject);
  Future<bool> switchTo(String project) async {
    if (data.project(project).archived) {
      return false;
    }
    if (data.active?.projectId == project) {
      return true;
    }
    return _transition(project);
  }

  Future<bool> pauseOrResume() async {
    if (data.active == null) {
      return false;
    }
    return _transition(data.active!.isBreak ? data.lastProject : null);
  }

  Future<bool> _transition(String? project) async {
    final now = clock();
    if (data.entries.any((e) => (e.end ?? e.start).isAfter(now))) {
      error =
          'Die Systemzeit liegt vor dem letzten Eintrag. Bitte die Uhrzeit oder den Eintrag korrigieren.';
      notifyListeners();
      return false;
    }
    if (data.active != null && now.isBefore(data.active!.start)) {
      return false;
    }
    final entries = data.entries
        .map((e) => e.end == null ? e.finish(now) : e)
        .where((e) => e.end == null || e.end!.isAfter(e.start))
        .toList();
    entries.add(TimeEntry(id: nextId(), start: now, projectId: project));
    _previousTick = now;
    return _commit(
      data.copy(
        entries: entries,
        lastProject: project ?? data.lastProject,
        lastSeen: now,
        clearNotice: true,
      ),
    );
  }

  Future<bool> stop() async {
    final now = clock();
    return _commit(
      data.copy(
        entries: data.entries
            .map((e) => e.end == null ? e.finish(now) : e)
            .where((e) => e.end!.isAfter(e.start))
            .toList(),
        lastSeen: now,
      ),
    );
  }

  Future<bool> saveProject(Project project) => _commit(
    data.copy(
      projects: [...data.projects.where((p) => p.id != project.id), project],
      lastProject: project.archived && data.lastProject == project.id
          ? otherId
          : data.lastProject,
    ),
  );
  Future<bool> saveProfile(ExportProfile profile) =>
      _commit(data.copy(profile: profile));
  Future<bool> dismissNotice() => _commit(data.copy(clearNotice: true));
  Future<bool> saveAnimal(String animal) async {
    if (!animalNames.containsKey(animal)) return false;
    return _commit(data.copy(animal: animal));
  }

  Future<bool> saveDayNotes(DateTime day, Map<String, String> values) =>
      _commit(
        data.copy(
          dayNotes: {
            ...data.dayNotes,
            isoDay(day): {
              ...?data.dayNotes[isoDay(day)],
              ...values.map((id, value) => MapEntry(id, value.trim())),
            },
          },
        ),
      );

  Future<bool> deleteDay(DateTime day) async {
    if (busy) return false;
    final from = dayStart(day);
    final until = DateTime(day.year, day.month, day.day + 1);
    final now = clock();
    final kept = <TimeEntry>[];
    final removed = <TimeEntry>[];
    for (final e in data.entries) {
      final end = e.end ?? now;
      final intersects =
          e.start.isBefore(until) &&
          (end.isAfter(from) || (e.end == null && !end.isBefore(from)));
      if (!intersects) {
        kept.add(e);
        continue;
      }
      if (e.start.isBefore(from)) {
        kept.add(
          TimeEntry(
            id: nextId(),
            start: e.start,
            end: from,
            projectId: e.projectId,
            note: e.note,
          ),
        );
      }
      if (end.isAfter(until)) {
        kept.add(
          TimeEntry(
            id: nextId(),
            start: until,
            end: e.end,
            projectId: e.projectId,
            note: e.note,
          ),
        );
      }
      final cutStart = e.start.isBefore(from) ? from : e.start;
      final cutEnd = end.isAfter(until) ? until : end;
      if (cutEnd.isAfter(cutStart)) {
        removed.add(
          TimeEntry(
            id: nextId(),
            start: cutStart,
            end: cutEnd,
            projectId: e.projectId,
            note: e.note,
          ),
        );
      }
    }
    final key = isoDay(day);
    final notes = {...data.dayNotes}..remove(key);
    return _commit(
      data.copy(
        entries: kept,
        dayNotes: notes,
        lastSeen: now,
        clearNotice: true,
        deletedTimes: DeletedTimes(
          entries: removed,
          dayNotes: {
            if (data.dayNotes.containsKey(key)) key: data.dayNotes[key]!,
          },
          label: 'Tag $key',
        ),
      ),
    );
  }

  Future<bool> resetTimes() async {
    if (busy) return false;
    final now = clock();
    final removed = data.entries
        .map((e) => e.end == null ? e.finish(now) : e)
        .toList();
    return _commit(
      data.copy(
        entries: [],
        dayNotes: {},
        lastSeen: now,
        clearNotice: true,
        deletedTimes: DeletedTimes(
          entries: removed,
          dayNotes: data.dayNotes,
          label: 'Alle Zeitdaten',
        ),
      ),
    );
  }

  Future<bool> restoreDeletedTimes() async {
    final deleted = data.deletedTimes;
    if (deleted == null || busy) return false;
    final now = clock();
    for (final removed in deleted.entries) {
      if (data.entries.any(
        (e) =>
            removed.start.isBefore(e.end ?? now) &&
            removed.end!.isAfter(e.start),
      )) {
        error =
            'Wiederherstellung würde neue Einträge überschneiden. Bitte diese zuerst korrigieren.';
        notifyListeners();
        return false;
      }
    }
    final notes = data.dayNotes.map(
      (day, values) => MapEntry(day, {...values}),
    );
    for (final day in deleted.dayNotes.entries) {
      final values = notes.putIfAbsent(day.key, () => {});
      for (final value in day.value.entries) {
        values[value.key] = {
          value.value,
          if (values[value.key] != null) values[value.key]!,
        }.where((v) => v.isNotEmpty).join('; ');
      }
    }
    return _commit(
      data.copy(
        entries: [
          ...data.entries,
          ...deleted.entries.map(
            (e) => TimeEntry(
              id: nextId(),
              start: e.start,
              end: e.end,
              projectId: e.projectId,
              note: e.note,
            ),
          ),
        ]..sort((a, b) => a.start.compareTo(b.start)),
        dayNotes: notes,
        clearDeletedTimes: true,
      ),
    );
  }

  String? validateEntry(TimeEntry entry) {
    if (entry.end == null || !entry.end!.isAfter(entry.start)) {
      return 'Das Ende muss nach dem Beginn liegen.';
    }
    if (entry.end!.isAfter(clock())) {
      return 'Einträge dürfen nicht in der Zukunft liegen.';
    }
    if (data.active?.id == entry.id) {
      return 'Bitte zuerst die laufende Erfassung stoppen.';
    }
    if (data.entries.any(
      (e) =>
          e.id != entry.id &&
          entry.start.isBefore(e.end ?? clock()) &&
          entry.end!.isAfter(e.start),
    )) {
      return 'Der Zeitraum überschneidet sich mit einem anderen Eintrag.';
    }
    return null;
  }

  Future<bool> saveEntry(TimeEntry entry) async {
    final message = validateEntry(entry);
    if (message != null) {
      error = message;
      notifyListeners();
      return false;
    }
    return _commit(
      data.copy(
        entries: [...data.entries.where((e) => e.id != entry.id), entry]
          ..sort((a, b) => a.start.compareTo(b.start)),
      ),
    );
  }

  Future<bool> deleteEntry(String id) async {
    if (data.active?.id == id) {
      return false;
    }
    return _commit(
      data.copy(
        entries: data.entries.where((e) => e.id != id).toList(),
        deletedTimes: DeletedTimes(
          entries: data.entries.where((e) => e.id == id).toList(),
          dayNotes: {},
          label: 'Eintrag',
        ),
      ),
    );
  }
}
