import 'model.dart';

class ExportRow {
  const ExportRow({
    required this.entries,
    required this.rawDuration,
    required this.duration,
    required this.note,
  });
  final List<TimeEntry> entries;
  final Duration rawDuration, duration;
  final String note;
  String? get projectId => entries.first.projectId;
}

class CsvExport {
  static Duration rounded(Duration raw, String mode) {
    if (mode == 'none') return raw;
    const step = 15 * 60 * 1000;
    final millis = raw.inMilliseconds;
    return Duration(
      milliseconds: switch (mode) {
        'nearest' => ((millis + step ~/ 2) ~/ step) * step,
        'up' => ((millis + step - 1) ~/ step) * step,
        _ => throw StateError('Unbekannte Rundungsregel.'),
      },
    );
  }

  static List<ExportRow> rowsForDay(
    TrackerData data,
    DateTime day,
    DateTime now, {
    ExportProfile? profile,
  }) {
    final p = profile ?? data.profile;
    final entries = entriesForDay(data, day, now);
    if (entries.any((e) => e.end == null)) {
      throw StateError('Bitte zuerst die laufende Erfassung stoppen.');
    }
    final groups = <String, List<TimeEntry>>{};
    for (final entry in entries) {
      if (entry.isBreak && !p.includeBreaks) continue;
      final key = p.dailySummary ? (entry.projectId ?? '__break') : entry.id;
      groups.putIfAbsent(key, () => []).add(entry);
    }
    return groups.values.map((group) {
      final raw = group.fold(Duration.zero, (sum, e) => sum + e.duration(now));
      return ExportRow(
        entries: group,
        rawDuration: raw,
        duration: rounded(raw, p.rounding),
        note: group.first.isBreak
            ? 'Pause'
            : data.notesForDay(day, group.first.projectId!, now),
      );
    }).toList();
  }

  static String create(
    TrackerData data,
    DateTime day,
    DateTime now, {
    ExportProfile? profile,
  }) {
    final p = profile ?? data.profile;
    final groups = rowsForDay(data, day, now, profile: p);
    if (p.columns.isEmpty) {
      throw StateError('Bitte mindestens eine Exportspalte wählen.');
    }
    if (groups.any((row) => row.projectId != null && row.note.trim().isEmpty)) {
      throw StateError(
        'Bitte den F9-Text für jedes bearbeitete Projekt erfassen.',
      );
    }
    if (groups.every((row) => row.duration == Duration.zero)) {
      throw StateError(
        'Nach der Rundung gibt es keine Zeit zu exportieren. Bitte Rundungsvorschau prüfen.',
      );
    }
    final rows = <List<String>>[];
    if (p.header) rows.add(p.columns.map((c) => c.header).toList());
    for (final row in groups) {
      if (row.duration == Duration.zero) continue;
      final first = row.entries.first;
      final project = row.projectId == null
          ? null
          : data.project(row.projectId!);
      final millis = row.duration.inMilliseconds;
      var amount = switch (p.durationFormat) {
        'minutes' => (millis / 60000).toStringAsFixed(
          p.rounding == 'none' ? 2 : 0,
        ),
        'hhmm' => elapsed(row.duration),
        'hhmmss' => elapsed(row.duration, seconds: p.rounding == 'none'),
        _ => (millis / 3600000).toStringAsFixed(p.rounding == 'none' ? 4 : 2),
      };
      if (p.decimalComma) amount = amount.replaceAll('.', ',');
      final values = <ExportField, String>{
        ExportField.date: p.dateFormat == 'yyyy-MM-dd'
            ? isoDay(day)
            : '${two(day.day)}.${two(day.month)}.${day.year}',
        ExportField.employee: p.employee,
        ExportField.projectCode: project?.code ?? '',
        ExportField.projectName: project?.name ?? 'Pause',
        ExportField.activity: project?.activity ?? '',
        ExportField.start: p.dailySummary
            ? ''
            : clockTime(first.start, seconds: true),
        ExportField.end: p.dailySummary
            ? ''
            : (dayStart(first.end!) != dayStart(first.start)
                  ? '24:00:00'
                  : clockTime(first.end!, seconds: true)),
        ExportField.duration: amount,
        ExportField.note: row.note,
      };
      rows.add(p.columns.map((c) => values[c.field]!).toList());
    }
    String escape(String value) {
      if (value.contains(p.delimiter) ||
          value.contains('"') ||
          value.contains('\n') ||
          value.contains('\r')) {
        return '"${value.replaceAll('"', '""')}"';
      }
      return value;
    }

    return '${p.bom ? '\uFEFF' : ''}${rows.map((row) => row.map(escape).join(p.delimiter)).join('\r\n')}\r\n';
  }
}
