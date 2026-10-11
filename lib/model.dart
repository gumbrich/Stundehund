import 'dart:math' as math;

const otherId = 'other';
const projectColors = [
  0xFF496CE8,
  0xFF2A9576,
  0xFFCC8750,
  0xFF9B6BC4,
  0xFFD26980,
  0xFF419AAE,
];

class Project {
  const Project({
    required this.id,
    required this.name,
    required this.color,
    this.code = '',
    this.activity = '',
    this.archived = false,
  });
  final String id, name, code, activity;
  final int color;
  final bool archived;
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'color': color,
    'code': code,
    'activity': activity,
    'archived': archived,
  };
  factory Project.fromJson(Map<String, dynamic> j) => Project(
    id: j['id'] as String,
    name: j['name'] as String,
    color: j['color'] as int,
    code: j['code'] as String? ?? '',
    activity: j['activity'] as String? ?? '',
    archived: j['archived'] as bool? ?? false,
  );
}

class TimeEntry {
  const TimeEntry({
    required this.id,
    required this.start,
    this.end,
    this.projectId,
    this.note = '',
  });
  final String id;
  final DateTime start;
  final DateTime? end;
  // A null project is a break. All work, including Anderes, has a project.
  final String? projectId;
  final String note;
  bool get isBreak => projectId == null;
  TimeEntry finish(DateTime at) => TimeEntry(
    id: id,
    start: start,
    end: at.isBefore(start) ? start : at,
    projectId: projectId,
    note: note,
  );
  Duration duration(DateTime now) => Duration(
    milliseconds: math.max(0, (end ?? now).difference(start).inMilliseconds),
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'start': start.toUtc().toIso8601String(),
    'end': end?.toUtc().toIso8601String(),
    'project': projectId,
    'note': note,
  };
  factory TimeEntry.fromJson(Map<String, dynamic> j) => TimeEntry(
    id: j['id'] as String,
    start: DateTime.parse(j['start'] as String).toLocal(),
    end: j['end'] == null ? null : DateTime.parse(j['end'] as String).toLocal(),
    projectId: j['project'] as String?,
    note: j['note'] as String? ?? '',
  );
}

enum ExportField {
  date,
  employee,
  projectCode,
  projectName,
  activity,
  start,
  end,
  duration,
  note,
}

const exportLabels = [
  'Datum',
  'Personalnummer',
  'Projektnummer',
  'Projekt',
  'Leistungsart',
  'Von',
  'Bis',
  'Dauer',
  'Bemerkung',
];

class ExportColumn {
  const ExportColumn(this.field, this.header);
  final ExportField field;
  final String header;
  Map<String, dynamic> toJson() => {'field': field.name, 'header': header};
  factory ExportColumn.fromJson(Map<String, dynamic> j) => ExportColumn(
    ExportField.values.byName(j['field'] as String),
    j['header'] as String,
  );
}

class ExportProfile {
  const ExportProfile({
    this.employee = '',
    this.delimiter = ';',
    this.decimalComma = false,
    this.dateFormat = 'dd.MM.yyyy',
    this.durationFormat = 'decimal',
    this.summary = true,
    this.includeBreaks = false,
    this.header = true,
    this.bom = true,
    this.columns = const [
      ExportColumn(ExportField.date, 'Datum'),
      ExportColumn(ExportField.employee, 'Personalnummer'),
      ExportColumn(ExportField.projectCode, 'Projektnummer'),
      ExportColumn(ExportField.projectName, 'Projekt'),
      ExportColumn(ExportField.activity, 'Leistungsart'),
      ExportColumn(ExportField.duration, 'Stunden'),
    ],
  });
  final String employee, delimiter, dateFormat, durationFormat;
  final bool decimalComma, summary, includeBreaks, header, bom;
  final List<ExportColumn> columns;
  Map<String, dynamic> toJson() => {
    'employee': employee,
    'delimiter': delimiter,
    'decimalComma': decimalComma,
    'dateFormat': dateFormat,
    'durationFormat': durationFormat,
    'summary': summary,
    'includeBreaks': includeBreaks,
    'header': header,
    'bom': bom,
    'columns': columns.map((c) => c.toJson()).toList(),
  };
  factory ExportProfile.fromJson(Map<String, dynamic> j) => ExportProfile(
    employee: j['employee'] as String,
    delimiter: j['delimiter'] as String,
    decimalComma: j['decimalComma'] as bool,
    dateFormat: j['dateFormat'] as String,
    durationFormat: j['durationFormat'] as String,
    summary: j['summary'] as bool,
    includeBreaks: j['includeBreaks'] as bool,
    header: j['header'] as bool,
    bom: j['bom'] as bool,
    columns: (j['columns'] as List)
        .map((c) => ExportColumn.fromJson(c as Map<String, dynamic>))
        .toList(),
  );
}

class TrackerData {
  TrackerData({
    required this.projects,
    required this.entries,
    this.profile = const ExportProfile(),
    this.lastProject = otherId,
    this.lastSeen,
    this.notice,
  });
  final List<Project> projects;
  final List<TimeEntry> entries;
  final ExportProfile profile;
  final String lastProject;
  final DateTime? lastSeen;
  final String? notice;
  factory TrackerData.empty() => TrackerData(
    projects: [const Project(id: otherId, name: 'Anderes', color: 0xFF7A8391)],
    entries: [],
  );
  TimeEntry? get active => entries.where((e) => e.end == null).firstOrNull;
  Project project(String id) => projects.firstWhere((p) => p.id == id);
  TrackerData copy({
    List<Project>? projects,
    List<TimeEntry>? entries,
    ExportProfile? profile,
    String? lastProject,
    DateTime? lastSeen,
    String? notice,
    bool clearNotice = false,
  }) => TrackerData(
    projects: projects ?? this.projects,
    entries: entries ?? this.entries,
    profile: profile ?? this.profile,
    lastProject: lastProject ?? this.lastProject,
    lastSeen: lastSeen ?? this.lastSeen,
    notice: clearNotice ? null : notice ?? this.notice,
  );
  Map<String, dynamic> toJson() => {
    'schema': 1,
    'projects': projects.map((p) => p.toJson()).toList(),
    'entries': entries.map((e) => e.toJson()).toList(),
    'profile': profile.toJson(),
    'lastProject': lastProject,
    'lastSeen': lastSeen?.toUtc().toIso8601String(),
    'notice': notice,
  };
  factory TrackerData.fromJson(Map<String, dynamic> j) {
    if (j['schema'] != 1) {
      throw const FormatException('Unbekannte Datenversion.');
    }
    final data = TrackerData(
      projects: (j['projects'] as List)
          .map((p) => Project.fromJson(p as Map<String, dynamic>))
          .toList(),
      entries: (j['entries'] as List)
          .map((e) => TimeEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      profile: ExportProfile.fromJson(j['profile'] as Map<String, dynamic>),
      lastProject: j['lastProject'] as String,
      lastSeen: j['lastSeen'] == null
          ? null
          : DateTime.parse(j['lastSeen'] as String).toLocal(),
      notice: j['notice'] as String?,
    );
    final ids = data.projects.map((p) => p.id).toSet();
    if (!ids.contains(otherId) ||
        ids.length != data.projects.length ||
        !ids.contains(data.lastProject) ||
        data.entries.where((e) => e.end == null).length > 1) {
      throw const FormatException('Ungültige Projektdaten.');
    }
    if (data.entries.any(
      (e) =>
          (e.projectId != null && !ids.contains(e.projectId)) ||
          (e.end?.isBefore(e.start) ?? false),
    )) {
      throw const FormatException('Ungültige Zeitdaten.');
    }
    return data;
  }
}

DateTime dayStart(DateTime d) => DateTime(d.year, d.month, d.day);
String two(int n) => n.toString().padLeft(2, '0');
String isoDay(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';
String clockTime(DateTime d, {bool seconds = false}) =>
    '${two(d.hour)}:${two(d.minute)}${seconds ? ':${two(d.second)}' : ''}';
String elapsed(Duration d, {bool seconds = false}) =>
    '${two(d.inHours)}:${two(d.inMinutes.remainder(60))}${seconds ? ':${two(d.inSeconds.remainder(60))}' : ''}';

// Calendar boundaries, rather than 24-hour increments, preserve DST days.
List<TimeEntry> entriesForDay(TrackerData data, DateTime day, DateTime now) {
  final from = dayStart(day);
  final until = DateTime(day.year, day.month, day.day + 1);
  return data.entries
      .where((e) => e.start.isBefore(until) && (e.end ?? now).isAfter(from))
      .map(
        (e) => TimeEntry(
          id: e.id,
          projectId: e.projectId,
          start: e.start.isBefore(from) ? from : e.start,
          end: (e.end ?? now).isAfter(until) ? until : e.end,
          note: e.note,
        ),
      )
      .toList()
    ..sort((a, b) => a.start.compareTo(b.start));
}
