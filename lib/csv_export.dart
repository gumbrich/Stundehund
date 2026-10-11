import 'model.dart';

class CsvExport {
  static String create(
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
    if (p.columns.isEmpty) {
      throw StateError('Bitte mindestens eine Exportspalte wählen.');
    }
    final rows = <List<String>>[];
    if (p.header) {
      rows.add(p.columns.map((c) => c.header).toList());
    }
    final groups = <String, List<TimeEntry>>{};
    for (final entry in entries) {
      if (entry.isBreak && !p.includeBreaks) {
        continue;
      }
      final key = p.summary ? (entry.projectId ?? '__break') : entry.id;
      groups.putIfAbsent(key, () => []).add(entry);
    }
    for (final group in groups.values) {
      final first = group.first;
      final project = first.projectId == null
          ? null
          : data.project(first.projectId!);
      final millis = group.fold<int>(
        0,
        (sum, e) => sum + e.duration(now).inMilliseconds,
      );
      final duration = Duration(milliseconds: millis);
      var amount = switch (p.durationFormat) {
        'minutes' => (millis / 60000).toStringAsFixed(2),
        'hhmmss' => elapsed(duration, seconds: true),
        _ => (millis / 3600000).toStringAsFixed(4),
      };
      if (p.decimalComma) {
        amount = amount.replaceAll('.', ',');
      }
      final values = <ExportField, String>{
        ExportField.date: p.dateFormat == 'yyyy-MM-dd'
            ? isoDay(day)
            : '${two(day.day)}.${two(day.month)}.${day.year}',
        ExportField.employee: p.employee,
        ExportField.projectCode: project?.code ?? '',
        ExportField.projectName: project?.name ?? 'Pause',
        ExportField.activity: project?.activity ?? '',
        // A summary has no continuous interval. Leave start/end blank.
        ExportField.start: p.summary
            ? ''
            : clockTime(first.start, seconds: true),
        ExportField.end: p.summary
            ? ''
            : (dayStart(first.end!) != dayStart(first.start)
                  ? '24:00:00'
                  : clockTime(first.end!, seconds: true)),
        ExportField.duration: amount,
        ExportField.note: group
            .map((e) => e.note)
            .where((n) => n.isNotEmpty)
            .toSet()
            .join(' | '),
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
