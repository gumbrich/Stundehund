import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';
import 'csv_export.dart';
import 'dialogs.dart';
import 'export_settings.dart';
import 'model.dart';
import 'tracker.dart';

const ink = Color(0xFF202C3C);
const muted = Color(0xFF747D88);
const paper = Color(0xFFF5F4F0);
const orange = Color(0xFFF4BD83);

class StundehundApp extends StatelessWidget {
  const StundehundApp({
    super.key,
    required this.tracker,
    this.desktop = false,
    this.dataPath = '',
    this.onQuit,
  });
  final Tracker tracker;
  final bool desktop;
  final String dataPath;
  final Future<void> Function()? onQuit;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Stundehund',
    debugShowCheckedModeBanner: false,
    locale: const Locale('de', 'CH'),
    supportedLocales: const [Locale('de', 'CH')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: paper,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF477A64),
        surface: paper,
      ),
      fontFamily: Platform.isWindows ? 'Segoe UI' : null,
      textTheme: const TextTheme(
        bodyMedium: TextStyle(color: ink),
        titleLarge: TextStyle(color: ink, fontWeight: FontWeight.w600),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFDDE0DD)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFDDE0DD)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    ),
    home: TrackerHome(
      tracker: tracker,
      desktop: desktop,
      dataPath: dataPath,
      onQuit: onQuit,
    ),
  );
}

class TrackerHome extends StatefulWidget {
  const TrackerHome({
    super.key,
    required this.tracker,
    required this.desktop,
    required this.dataPath,
    this.onQuit,
  });
  final Tracker tracker;
  final bool desktop;
  final String dataPath;
  final Future<void> Function()? onQuit;
  @override
  State<TrackerHome> createState() => _TrackerHomeState();
}

class _TrackerHomeState extends State<TrackerHome> with WindowListener {
  Tracker get tracker => widget.tracker;
  late DateTime selectedDay;
  Timer? timer;
  bool compact = false, closing = false;
  int tab = 0;
  @override
  void initState() {
    super.initState();
    selectedDay = dayStart(tracker.clock());
    timer = Timer.periodic(const Duration(seconds: 1), (_) => tracker.pulse());
    if (widget.desktop) {
      windowManager.addListener(this);
      windowManager.setPreventClose(true);
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    if (widget.desktop) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  @override
  void onWindowClose() {
    quit();
  }

  Future<void> quit() async {
    if (closing || tracker.busy) {
      return;
    }
    closing = true;
    if (tracker.data.active != null) {
      if (compact) {
        await toggleCompact();
      }
      if (!mounted) {
        return;
      }
      final yes = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Arbeitstag beenden?'),
          content: const Text(
            'Die laufende Erfassung wird gestoppt und gespeichert, bevor Stundehund geschlossen wird.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Weiterarbeiten'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Stoppen & schliessen'),
            ),
          ],
        ),
      );
      if (yes != true || !await tracker.stop()) {
        closing = false;
        return;
      }
    }
    timer?.cancel();
    await widget.onQuit?.call();
    closing = false;
  }

  Future<void> toggleCompact() async {
    final next = !compact;
    if (widget.desktop) {
      if (next) {
        final display = await screenRetriever.getPrimaryDisplay();
        final area = display.visibleSize ?? display.size;
        final origin = display.visiblePosition ?? Offset.zero;
        final width = (area.width - 24).clamp(760.0, 1120.0);
        // Render the small layout before shrinking the window.
        setState(() => compact = true);
        await windowManager.setMinimumSize(const Size(760, 158));
        await windowManager.setSize(Size(width, 158));
        await windowManager.setPosition(
          Offset(origin.dx + (area.width - width) / 2, origin.dy + 8),
        );
        await windowManager.setAlwaysOnTop(true);
        await windowManager.setResizable(false);
      } else {
        await windowManager.setResizable(true);
        await windowManager.setSize(const Size(1120, 820));
        await windowManager.setMinimumSize(const Size(760, 600));
        await windowManager.center();
        await windowManager.setAlwaysOnTop(false);
        if (mounted) {
          setState(() => compact = false);
        }
      }
    } else {
      setState(() => compact = next);
    }
  }

  void snack(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> editProject([Project? project]) async {
    await showDialog<void>(
      context: context,
      builder: (_) => ProjectDialog(tracker: tracker, project: project),
    );
  }

  Future<void> editEntry([TimeEntry? entry]) async {
    await showDialog<void>(
      context: context,
      builder: (_) =>
          EntryDialog(tracker: tracker, entry: entry, day: selectedDay),
    );
  }

  Future<void> exportDay() async {
    try {
      final csv = CsvExport.create(tracker.data, selectedDay, tracker.clock());
      final missing = entriesForDay(tracker.data, selectedDay, tracker.clock())
          .where(
            (e) =>
                !e.isBreak &&
                tracker.data.project(e.projectId!).code.trim().isEmpty,
          )
          .isNotEmpty;
      final approved = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('CSV exportieren'),
          content: SizedBox(
            width: 650,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Das Exportprofil muss zur Importvorlage deines Arbeitgebers passen. Die Abacus-Kompatibilität ist noch nicht bestätigt.',
                  ),
                  if (missing)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text(
                        'Für mindestens ein Projekt fehlt die Abacus-Projektnummer.',
                        style: TextStyle(color: Color(0xFF98621F)),
                      ),
                    ),
                  const SizedBox(height: 18),
                  const Text(
                    'VORSCHAU',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 1.5,
                      color: muted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SelectableText(
                        csv.replaceFirst('\uFEFF', ''),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('Datei speichern'),
            ),
          ],
        ),
      );
      if (approved != true) {
        return;
      }
      final location = await getSaveLocation(
        suggestedName: 'Stundehund-${isoDay(selectedDay)}.csv',
        acceptedTypeGroups: const [
          XTypeGroup(label: 'CSV', extensions: ['csv']),
        ],
      );
      if (location == null) {
        return;
      }
      await XFile.fromData(
        Uint8List.fromList(utf8.encode(csv)),
        mimeType: 'text/csv',
      ).saveTo(location.path);
      snack('CSV gespeichert: ${location.path}');
    } catch (e) {
      snack('Export fehlgeschlagen: $e');
    }
  }

  Future<void> backup() async {
    try {
      final location = await getSaveLocation(
        suggestedName: 'Stundehund-Sicherung-${isoDay(tracker.clock())}.json',
        acceptedTypeGroups: const [
          XTypeGroup(label: 'JSON', extensions: ['json']),
        ],
      );
      if (location == null) {
        return;
      }
      final json = const JsonEncoder.withIndent(
        '  ',
      ).convert(tracker.data.toJson());
      await XFile.fromData(
        Uint8List.fromList(utf8.encode(json)),
      ).saveTo(location.path);
      snack('Sicherung gespeichert.');
    } catch (e) {
      snack('Sicherung fehlgeschlagen: $e');
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: tracker,
    builder: (context, _) {
      final now = tracker.clock();
      final data = tracker.data;
      final active = data.active;
      final shortcuts = <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.space, control: true): () {
          if (!tracker.busy) {
            active == null ? tracker.start() : tracker.pauseOrResume();
          }
        },
        const SingleActivator(
          LogicalKeyboardKey.keyS,
          control: true,
          shift: true,
        ): () {
          if (!tracker.busy) {
            active == null ? tracker.start() : tracker.stop();
          }
        },
      };
      final keys = [
        LogicalKeyboardKey.digit1,
        LogicalKeyboardKey.digit2,
        LogicalKeyboardKey.digit3,
        LogicalKeyboardKey.digit4,
        LogicalKeyboardKey.digit5,
        LogicalKeyboardKey.digit6,
        LogicalKeyboardKey.digit7,
        LogicalKeyboardKey.digit8,
        LogicalKeyboardKey.digit9,
      ];
      final projects =
          data.projects.where((p) => !p.archived && p.id != otherId).toList()
            ..add(data.project(otherId));
      for (var i = 0; i < projects.length && i < keys.length; i++) {
        final project = projects[i];
        shortcuts[SingleActivator(keys[i], control: true)] = () {
          if (!tracker.busy) {
            tracker.switchTo(project.id);
          }
        };
      }
      return CallbackShortcuts(
        bindings: shortcuts,
        child: Focus(
          autofocus: true,
          child: Scaffold(
            body: Column(
              children: [
                timerBar(now, projects),
                if (!compact)
                  Expanded(
                    child: Column(
                      children: [
                        if (tracker.error != null || data.notice != null)
                          Container(
                            color: const Color(0xFFFFEACB),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 8,
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.info_outline_rounded,
                                  size: 18,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    tracker.error ?? data.notice!,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                                if (tracker.error == null)
                                  IconButton(
                                    onPressed: tracker.busy
                                        ? null
                                        : tracker.dismissNotice,
                                    icon: const Icon(Icons.close, size: 18),
                                  ),
                              ],
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(28, 10, 24, 0),
                          child: Row(
                            children: [
                              navButton('Tagesübersicht', 0),
                              navButton('Projekte', 1),
                              navButton('Exportprofil', 2),
                              const Spacer(),
                              Tooltip(
                                message: 'Alle Daten als JSON sichern',
                                child: TextButton.icon(
                                  onPressed: backup,
                                  icon: const Icon(
                                    Icons.backup_outlined,
                                    size: 16,
                                  ),
                                  label: const Text('Sicherung'),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1, color: Color(0xFFE2E3DE)),
                        Expanded(
                          child: switch (tab) {
                            0 => journal(now),
                            1 => projectPage(),
                            _ => ExportSettings(tracker: tracker),
                          },
                        ),
                        Container(
                          padding: const EdgeInsets.fromLTRB(28, 8, 28, 12),
                          child: Row(
                            children: [
                              Icon(
                                tracker.busy
                                    ? Icons.sync
                                    : Icons.check_circle_outline,
                                size: 13,
                                color: muted,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                tracker.busy
                                    ? 'Wird gespeichert …'
                                    : 'Lokal auf diesem Gerät gespeichert',
                                style: const TextStyle(
                                  color: muted,
                                  fontSize: 11,
                                ),
                              ),
                              const Spacer(),
                              if (MediaQuery.sizeOf(context).width > 1050)
                                const Text(
                                  'Strg + 1–9  Projekt wechseln   ·   Strg + Leertaste  Pause',
                                  style: TextStyle(color: muted, fontSize: 11),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
  Widget navButton(String title, int index) => Padding(
    padding: const EdgeInsets.only(right: 20),
    child: InkWell(
      onTap: () => setState(() => tab = index),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 17),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: tab == index ? ink : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 13,
            color: tab == index ? ink : muted,
            fontWeight: tab == index ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ),
    ),
  );

  Widget timerBar(DateTime now, List<Project> projects) {
    final active = tracker.data.active;
    final isBreak = active?.isBreak ?? false;
    final today = entriesForDay(tracker.data, now, now);
    final total = today
        .where((e) => !e.isBreak)
        .fold(Duration.zero, (d, e) => d + e.duration(now));
    final status = active == null
        ? 'Bereit für deinen Tag'
        : isBreak
        ? 'Zeit für eine Pause'
        : tracker.data.project(active.projectId!).name;
    return Container(
      height: 158,
      color: ink,
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 14),
      child: Column(
        children: [
          SizedBox(
            height: 58,
            child: Row(
              children: [
                Expanded(
                  child: widget.desktop
                      ? DragToMoveArea(
                          child: brand(status, active != null, isBreak),
                        )
                      : brand(status, active != null, isBreak),
                ),
                if (compact &&
                    (tracker.error != null || tracker.data.notice != null))
                  IconButton(
                    tooltip: tracker.error ?? tracker.data.notice,
                    onPressed: toggleCompact,
                    icon: const Icon(
                      Icons.warning_amber_rounded,
                      color: orange,
                    ),
                  ),
                FilledButton.icon(
                  key: const Key('start-stop'),
                  style: FilledButton.styleFrom(
                    backgroundColor: active == null
                        ? orange
                        : const Color(0xFF3C4A5B),
                    foregroundColor: active == null ? ink : Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 18,
                    ),
                  ),
                  onPressed: tracker.busy
                      ? null
                      : () async {
                          if (active == null) {
                            await tracker.start();
                            setState(
                              () => selectedDay = dayStart(tracker.clock()),
                            );
                          } else {
                            await tracker.stop();
                          }
                        },
                  icon: Icon(
                    active == null
                        ? Icons.play_arrow_rounded
                        : Icons.stop_rounded,
                    size: 19,
                  ),
                  label: Text(active == null ? 'Start' : 'Stop'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  key: const Key('pause'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    disabledForegroundColor: Colors.white30,
                    side: const BorderSide(color: Color(0xFF526071)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 18,
                    ),
                  ),
                  onPressed: active == null || tracker.busy
                      ? null
                      : tracker.pauseOrResume,
                  icon: Icon(
                    isBreak ? Icons.play_arrow_rounded : Icons.pause_rounded,
                    size: 18,
                  ),
                  label: Text(isBreak ? 'Weiter' : 'Pause'),
                ),
                const SizedBox(width: 22),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      elapsed(total, seconds: true),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w500,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    const Text(
                      'ARBEITSZEIT HEUTE',
                      style: TextStyle(
                        color: Color(0xFFAAB4C1),
                        fontSize: 9,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 14),
                IconButton(
                  key: const Key('compact'),
                  tooltip: compact
                      ? 'Tagesübersicht öffnen'
                      : 'Als Leiste am Bildschirmrand',
                  onPressed: toggleCompact,
                  icon: Icon(
                    compact
                        ? Icons.open_in_full_rounded
                        : Icons.vertical_align_top_rounded,
                    color: Colors.white70,
                    size: 19,
                  ),
                ),
                if (widget.desktop) ...[
                  IconButton(
                    tooltip: 'Minimieren',
                    onPressed: () => windowManager.minimize(),
                    icon: const Icon(
                      Icons.remove,
                      color: Colors.white54,
                      size: 17,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Schliessen',
                    onPressed: quit,
                    icon: const Icon(
                      Icons.close,
                      color: Colors.white54,
                      size: 17,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (var i = 0; i < projects.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: projectButton(projects[i], i, now),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Projekt hinzufügen',
                  onPressed: () async {
                    if (compact) {
                      await toggleCompact();
                    }
                    await editProject();
                  },
                  icon: const Icon(
                    Icons.add_circle_outline,
                    color: Colors.white60,
                    size: 24,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget brand(String status, bool running, bool paused) => Row(
    children: [
      Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: orange,
          borderRadius: BorderRadius.circular(13),
        ),
        child: const Icon(Icons.pets_rounded, color: ink, size: 24),
      ),
      const SizedBox(width: 12),
      Flexible(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'stundehund',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.6,
              ),
            ),
            const SizedBox(height: 3),
            Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: !running
                        ? Colors.white38
                        : paused
                        ? orange
                        : const Color(0xFF8EC8AD),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    status,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFB9C2CF),
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ],
  );
  Widget projectButton(Project project, int index, DateTime now) {
    final active = tracker.data.active?.projectId == project.id;
    final color = Color(project.color);
    final duration = entriesForDay(tracker.data, now, now)
        .where((e) => e.projectId == project.id)
        .fold(Duration.zero, (d, e) => d + e.duration(now));
    return Tooltip(
      message: '${project.name}${index < 9 ? ' · Strg + ${index + 1}' : ''}',
      child: Material(
        color: active ? color : const Color(0xFF2B3849),
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          key: Key('project-${project.id}'),
          onTap: tracker.busy ? null : () => tracker.switchTo(project.id),
          borderRadius: BorderRadius.circular(9),
          child: Container(
            constraints: const BoxConstraints(minWidth: 128, maxWidth: 210),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: active ? Colors.white24 : color.withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  active ? Icons.play_arrow_rounded : Icons.circle,
                  color: active ? Colors.white : color,
                  size: active ? 16 : 8,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    project.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  elapsed(duration),
                  style: TextStyle(
                    color: active ? Colors.white : Colors.white54,
                    fontSize: 11,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget journal(DateTime now) {
    final entries = entriesForDay(tracker.data, selectedDay, now);
    final work = entries
        .where((e) => !e.isBreak)
        .fold(Duration.zero, (d, e) => d + e.duration(now));
    final pauses = entries
        .where((e) => e.isBreak)
        .fold(Duration.zero, (d, e) => d + e.duration(now));
    final isToday = selectedDay == dayStart(now);
    final canExport = entries.isNotEmpty && !entries.any((e) => e.end == null);
    const days = [
      'Montag',
      'Dienstag',
      'Mittwoch',
      'Donnerstag',
      'Freitag',
      'Samstag',
      'Sonntag',
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 26, 28, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isToday ? 'Dein Tag im Blick.' : 'Ein Tag, gut erfasst.',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.7,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${days[selectedDay.weekday - 1]}, ${two(selectedDay.day)}.${two(selectedDay.month)}.${selectedDay.year}',
                      style: const TextStyle(color: muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Vorheriger Tag',
                onPressed: () => setState(
                  () => selectedDay = DateTime(
                    selectedDay.year,
                    selectedDay.month,
                    selectedDay.day - 1,
                  ),
                ),
                icon: const Icon(Icons.chevron_left, size: 20),
              ),
              IconButton(
                tooltip: 'Datum wählen',
                onPressed: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: selectedDay,
                    firstDate: DateTime(2000),
                    lastDate: now,
                  );
                  if (date != null) {
                    setState(() => selectedDay = date);
                  }
                },
                icon: const Icon(Icons.calendar_today_outlined, size: 18),
              ),
              IconButton(
                tooltip: 'Nächster Tag',
                onPressed: isToday
                    ? null
                    : () => setState(
                        () => selectedDay = DateTime(
                          selectedDay.year,
                          selectedDay.month,
                          selectedDay.day + 1,
                        ),
                      ),
                icon: const Icon(Icons.chevron_right, size: 20),
              ),
              const SizedBox(width: 14),
              Tooltip(
                message: canExport
                    ? 'Ausgewählten Tag exportieren'
                    : 'Einträge erfassen und die laufende Erfassung stoppen',
                child: FilledButton.icon(
                  onPressed: canExport ? exportDay : null,
                  icon: const Icon(Icons.file_download_outlined, size: 18),
                  label: const Text('CSV exportieren'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 25),
          Row(
            children: [
              Expanded(
                child: stat(
                  'ARBEITSZEIT',
                  elapsed(work),
                  'ohne Pausen',
                  Icons.timelapse_rounded,
                  const Color(0xFF3F8269),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: stat(
                  'PAUSEN',
                  elapsed(pauses),
                  'bewusst durchatmen',
                  Icons.coffee_outlined,
                  const Color(0xFFB7844A),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: stat(
                  'PROJEKTE',
                  '${entries.where((e) => !e.isBreak).map((e) => e.projectId).toSet().length}'
                      .padLeft(2, '0'),
                  'heute bearbeitet',
                  Icons.folder_open_rounded,
                  const Color(0xFF6E7CA4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 26),
          LayoutBuilder(
            builder: (context, constraints) {
              final distribution = projectSummary(entries, work, now);
              final timeline = entryList(entries, now);
              if (constraints.maxWidth < 800) {
                return Column(
                  children: [
                    distribution,
                    const SizedBox(height: 20),
                    timeline,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 4, child: distribution),
                  const SizedBox(width: 22),
                  Expanded(flex: 6, child: timeline),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget stat(
    String label,
    String amount,
    String caption,
    IconData icon,
    Color color,
  ) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFE6E7E2)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: muted,
                  fontSize: 10,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                amount,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -1,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 3),
              Text(caption, style: const TextStyle(color: muted, fontSize: 11)),
            ],
          ),
        ),
        Icon(icon, color: color, size: 22),
      ],
    ),
  );
  Widget projectSummary(List<TimeEntry> entries, Duration work, DateTime now) {
    final totals = <String, Duration>{};
    for (final e in entries.where((e) => !e.isBreak)) {
      totals[e.projectId!] =
          (totals[e.projectId!] ?? Duration.zero) + e.duration(now);
    }
    final ids = totals.keys.toList()
      ..sort((a, b) => totals[b]!.compareTo(totals[a]!));
    return surface(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Wohin deine Zeit geht',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          const Text(
            'Arbeitszeit nach Projekt',
            style: TextStyle(color: muted, fontSize: 12),
          ),
          const SizedBox(height: 25),
          if (ids.isEmpty) ...[
            const Icon(
              Icons.wb_sunny_outlined,
              color: Color(0xFFB1B6AD),
              size: 38,
            ),
            const SizedBox(height: 14),
            const Text(
              'Ein guter Tag beginnt mit einem Klick.',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            const Text(
              'Lege deine Projekte an und drücke Start. Noch nicht zugeordnete Zeit landet in «Anderes».',
              style: TextStyle(color: muted, fontSize: 12, height: 1.6),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: () => editProject(),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Erstes Projekt anlegen'),
            ),
          ],
          for (final id in ids)
            Padding(
              padding: const EdgeInsets.only(bottom: 22),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(tracker.data.project(id).color),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          tracker.data.project(id).name,
                          style: const TextStyle(fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        elapsed(totals[id]!, seconds: true),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: work.inMilliseconds == 0
                          ? 0
                          : totals[id]!.inMilliseconds / work.inMilliseconds,
                      minHeight: 5,
                      backgroundColor: paper,
                      color: Color(tracker.data.project(id).color),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget entryList(List<TimeEntry> entries, DateTime now) => surface(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Tagesverlauf',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            TextButton.icon(
              onPressed: () => editEntry(),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Nachtragen', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (entries.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 34),
            child: Center(
              child: Text(
                'Hier entsteht dein Arbeitstag.',
                style: TextStyle(color: muted, fontSize: 13),
              ),
            ),
          ),
        for (final entry in entries.reversed) entryRow(entry, now),
      ],
    ),
  );
  Widget entryRow(TimeEntry entry, DateTime now) {
    final original = tracker.data.entries.firstWhere((e) => e.id == entry.id);
    final project = entry.projectId == null
        ? null
        : tracker.data.project(entry.projectId!);
    return InkWell(
      onTap: original.end == null ? null : () => editEntry(original),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color:
                    (project == null
                            ? const Color(0xFFB7844A)
                            : Color(project.color))
                        .withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(
                project == null ? Icons.coffee_outlined : Icons.circle,
                color: project == null
                    ? const Color(0xFFB7844A)
                    : Color(project.color),
                size: project == null ? 16 : 9,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    project?.name ?? 'Pause',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${clockTime(entry.start)} – ${entry.end == null ? 'läuft' : clockTime(entry.end!)}${entry.note.isNotEmpty ? ' · ${entry.note}' : ''}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: muted),
                  ),
                ],
              ),
            ),
            Text(
              elapsed(entry.duration(now), seconds: true),
              style: const TextStyle(
                fontSize: 12,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 12),
            Icon(
              original.end == null
                  ? Icons.radio_button_checked
                  : Icons.edit_outlined,
              size: 14,
              color: original.end == null
                  ? const Color(0xFF3F8269)
                  : const Color(0xFFB4BBB9),
            ),
          ],
        ),
      ),
    );
  }

  Widget surface(Widget child) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFE6E7E2)),
    ),
    child: child,
  );
  Widget projectPage() => SingleChildScrollView(
    padding: const EdgeInsets.all(28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Deine Projekte.',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Ein Projekt, eine Farbe, ein Klick.',
                    style: TextStyle(color: muted),
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: () => editProject(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Projekt hinzufügen'),
            ),
          ],
        ),
        const SizedBox(height: 26),
        for (final p in tracker.data.projects)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: surface(
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Color(p.color).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.folder_outlined,
                      color: Color(p.color),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${p.name}${p.archived ? ' · archiviert' : ''}',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          p.code.isEmpty
                              ? 'Noch keine Abacus-Projektnummer'
                              : 'Projekt ${p.code}${p.activity.isNotEmpty ? '  ·  Leistungsart ${p.activity}' : ''}',
                          style: const TextStyle(color: muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Projekt bearbeiten',
                    onPressed: () => editProject(p),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 20),
        const Text(
          'Archivierte Projekte bleiben in deinen Zeitdaten erhalten. «Anderes» steht immer zur Verfügung.',
          style: TextStyle(color: muted, fontSize: 12),
        ),
        if (widget.dataPath.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 22),
            child: SelectableText(
              'Datenordner: ${widget.dataPath}',
              style: const TextStyle(color: muted, fontSize: 11),
            ),
          ),
      ],
    ),
  );
}
