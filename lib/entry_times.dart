import 'model.dart';
import 'tracker.dart';

DateTime? parseEntryTime(String day, String time) {
  final dateParts = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(day.trim());
  final swiss = RegExp(
    r'^(\d{1,2})\.(\d{1,2})\.(\d{4})$',
  ).firstMatch(day.trim());
  final parts = RegExp(
    r'^(\d{1,2})[:.](\d{2})(?::(\d{2}))?$',
  ).firstMatch(time.trim());
  if ((dateParts == null && swiss == null) || parts == null) return null;
  final year = int.parse(dateParts?[1] ?? swiss![3]!);
  final month = int.parse(dateParts?[2] ?? swiss![2]!);
  final dayOfMonth = int.parse(dateParts?[3] ?? swiss![1]!);
  final hour = int.parse(parts[1]!);
  final minute = int.parse(parts[2]!);
  final second = int.parse(parts[3] ?? '0');
  final value = DateTime(year, month, dayOfMonth, hour, minute, second);
  return value.year == year &&
          value.month == month &&
          value.day == dayOfMonth &&
          value.hour == hour &&
          value.minute == minute &&
          value.second == second
      ? value
      : null;
}

/// Suggest the latest free span, capped at an hour, inside the selected day.
/// Exact boundaries are retained so subsecond timer starts do not overlap.
TimeEntry suggestedEntry(Tracker tracker, DateTime day) {
  final now = tracker.clock();
  final from = dayStart(day);
  final nextDay = DateTime(day.year, day.month, day.day + 1);
  final until = nextDay.isBefore(now) ? nextDay : now;
  final entries = entriesForDay(tracker.data, day, now);
  // Include a just-started active entry, which entriesForDay omits at zero duration.
  final active = tracker.data.active;
  if (active != null &&
      !active.start.isBefore(from) &&
      active.start.isBefore(nextDay) &&
      !entries.any((e) => e.id == active.id)) {
    entries.add(active);
    entries.sort((a, b) => a.start.compareTo(b.start));
  }
  if (entries.isEmpty) {
    final morning = DateTime(day.year, day.month, day.day, 8);
    final end = DateTime(day.year, day.month, day.day, 9);
    if (!end.isAfter(until)) {
      return TimeEntry(
        id: '',
        start: morning,
        end: end,
        projectId: tracker.data.lastProject,
      );
    }
  }
  var cursor = from;
  DateTime? gapStart, gapEnd;
  for (final entry in entries) {
    if (entry.start.isAfter(cursor)) {
      gapStart = cursor;
      gapEnd = entry.start;
    }
    final end = entry.end ?? until;
    if (end.isAfter(cursor)) cursor = end;
  }
  if (cursor.isBefore(until)) {
    gapStart = cursor;
    gapEnd = until;
  }
  final end = gapEnd ?? until;
  final earliest = gapStart ?? end;
  final hourBefore = end.subtract(const Duration(hours: 1));
  return TimeEntry(
    id: '',
    start: earliest.isAfter(hourBefore) ? earliest : hourBefore,
    end: end,
    projectId: tracker.data.lastProject,
  );
}
