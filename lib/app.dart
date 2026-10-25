import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:window_manager/window_manager.dart';
import 'csv_export.dart';
import 'day_notes_dialog.dart';
import 'window_geometry.dart';
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
  bool changingWindow = false, expandedWasMaximized = false;
  final windowGeometry = WindowGeometry();
  String? desktopAppearanceKey, desktopAnimal;
  bool syncingAppearance = false;
  @override
  void initState() {
    super.initState();
    selectedDay = dayStart(tracker.clock());
    timer = Timer.periodic(const Duration(seconds: 1), (_) => tracker.pulse());
    if (widget.desktop) {
      windowManager.addListener(this);
      windowManager.setPreventClose(true);
      tracker.addListener(syncDesktopAppearance);
      syncDesktopAppearance();
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    if (widget.desktop) {
      windowManager.removeListener(this);
      tracker.removeListener(syncDesktopAppearance);
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
    if (changingWindow) return;
    final previous = compact;
    final next = !compact;
    if (!widget.desktop) {
      setState(() => compact = next);
      return;
    }
    setState(() => changingWindow = true);
    try {
      final current = await windowManager.getBounds();
      if (next) {
        expandedWasMaximized = await windowManager.isMaximized();
        if (expandedWasMaximized) await windowManager.unmaximize();
      }
      final bounds = windowGeometry.forMode(current, compact: next);
      if (next && mounted) setState(() => compact = true);
      await windowManager.setResizable(true);
      await windowManager.setMinimumSize(
        Size(760, next ? compactBarHeight : 600),
      );
      await windowManager.setBounds(bounds, animate: false);
      await windowManager.setAlwaysOnTop(next);
      await windowManager.setResizable(!next);
      if (!next && expandedWasMaximized) await windowManager.maximize();
      if (mounted) setState(() => compact = next);
    } catch (error) {
      if (mounted) setState(() => compact = previous);
      snack('Fenster konnte nicht umgeschaltet werden: $error');
    } finally {
      if (mounted) setState(() => changingWindow = false);
    }
  }

  Future<void> syncDesktopAppearance() async {
    if (!widget.desktop || syncingAppearance) return;
    final data = tracker.data;
    final active = data.active;
    final title = active == null
        ? 'Stundehund'
        : active.isBreak
        ? 'Pause · ${data.project(data.lastProject).name} – Stundehund'
        : 'AKTIV · ${data.project(active.projectId!).name} – Stundehund';
    final key = '${data.animal}|$title';
    if (desktopAppearanceKey == key) return;
    desktopAppearanceKey = key;
    syncingAppearance = true;
    try {
      await windowManager.setTitle(title);
      if (desktopAnimal != data.animal) {
        if (Platform.isWindows) {
          await windowManager.setIcon('assets/animals/${data.animal}.ico');
        } else if (Platform.isMacOS) {
          final bytes = await rootBundle.load(
            'assets/animals/${data.animal}.png',
          );
          await const MethodChannel(
            'stundehund/appearance',
          ).invokeMethod<void>('setIcon', bytes.buffer.asUint8List());
        }
        desktopAnimal = data.animal;
      }
    } catch (error) {
      snack('Fenstersymbol konnte nicht aktualisiert werden: $error');
    } finally {
      syncingAppearance = false;
      if (mounted) syncDesktopAppearance();
    }
  }

  Future<bool> editDayNotes(DateTime day, {List<String>? projectIds}) async {
    if (compact) await toggleCompact();
    if (!mounted) return false;
    final ids =
        projectIds ??
        entriesForDay(
          tracker.data,
          day,
          tracker.clock(),
        ).where((e) => !e.isBreak).map((e) => e.projectId!).toSet().toList();
    if (ids.isEmpty) ids.add(tracker.data.lastProject);
    return await showDialog<bool>(
          context: context,
          builder: (_) =>
              DayNotesDialog(tracker: tracker, day: day, projectIds: ids),
        ) ??
        false;
  }

  Future<void> confirmDeleteDay() async {
    final entries = entriesForDay(tracker.data, selectedDay, tracker.clock());
    if (entries.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Tag ${isoDay(selectedDay)} löschen?'),
        content: const Text(
          'Alle Zeiten und F9-Texte dieses Tages werden gelöscht. Eine laufende Erfassung für diesen Tag wird gestoppt. Andere Tage bleiben erhalten. Unter Einstellungen kannst du die letzte Löschung wiederherstellen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Tag löschen'),
          ),
        ],
      ),
    );
    if (confirmed == true && await tracker.deleteDay(selectedDay)) {
      snack('Tag gelöscht. Wiederherstellen unter Einstellungen.');
    }
  }

  Future<void> confirmResetTimes() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Alle Zeitdaten zurücksetzen?'),
        content: const Text(
          'Alle Tage und F9-Texte werden gelöscht und die Erfassung gestoppt. Projekte, Tier und Exportprofil bleiben erhalten. Diese Löschung ersetzt die bisherige Wiederherstellung.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Alle Zeiten zurücksetzen'),
          ),
        ],
      ),
    );
    if (confirmed == true && await tracker.resetTimes()) {
      snack(
        'Zeiten zurückgesetzt. Die letzte Löschung kann wiederhergestellt werden.',
      );
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
      final missingNotes =
          entriesForDay(tracker.data, selectedDay, tracker.clock())
              .where((e) => !e.isBreak)
              .map((e) => e.projectId!)
              .toSet()
              .where(
                (id) => tracker.data
                    .notesForDay(selectedDay, id, tracker.clock())
                    .trim()
                    .isEmpty,
              )
              .toList();
      if (missingNotes.isNotEmpty &&
          !await editDayNotes(selectedDay, projectIds: missingNotes)) {
        return;
      }
      if (!mounted) return;
      final rows = CsvExport.rowsForDay(
        tracker.data,
        selectedDay,
        tracker.clock(),
      );
      final hasExport = rows.any((row) => row.duration > Duration.zero);
      final csv = hasExport
          ? CsvExport.create(tracker.data, selectedDay, tracker.clock())
          : '';
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
                  Text(
                    tracker.data.profile.rounding == 'none'
                        ? 'Ohne Rundung'
                        : tracker.data.profile.rounding == 'up'
                        ? 'Pro Projekt und Tag auf 15 Minuten aufgerundet'
                        : 'Pro Projekt und Tag auf die nächsten 15 Minuten gerundet',
                  ),
                  const SizedBox(height: 8),
                  for (final row in rows)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              row.projectId == null
                                  ? 'Pause'
                                  : tracker.data.project(row.projectId!).name,
                            ),
                          ),
                          Text(
                            '${elapsed(row.rawDuration, seconds: true)} → ${elapsed(row.duration)}${row.duration == Duration.zero ? ' (entfällt)' : ''}',
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  const Text(
                    'Rundung kann die Tagessumme verändern. Rohzeiten bleiben gespeichert.',
                    style: TextStyle(fontSize: 12, color: muted),
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
                        hasExport
                            ? csv.replaceFirst('\uFEFF', '')
                            : 'Alle Projekte ergeben gerundet 0 Minuten. Die exakten Rohzeiten bleiben gespeichert.',
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
              onPressed: hasExport ? () => Navigator.pop(ctx, true) : null,
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
        const SingleActivator(LogicalKeyboardKey.f9): () {
          final day = compact ? tracker.clock() : selectedDay;
          editDayNotes(
            day,
            projectIds: dayStart(day) == dayStart(tracker.clock())
                ? [tracker.data.active?.projectId ?? tracker.data.lastProject]
                : null,
          );
        },
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
            // Native window bounds include the Windows border. In compact
            // mode, let the bar shrink to the actual client area.
            body: compact
                ? Align(
                    alignment: Alignment.topCenter,
                    child: timerBar(now, projects),
                  )
                : Column(
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
                                          icon: const Icon(
                                            Icons.close,
                                            size: 18,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  28,
                                  10,
                                  24,
                                  0,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: SingleChildScrollView(
                                        scrollDirection: Axis.horizontal,
                                        child: Row(
                                          children: [
                                            navButton('Tagesübersicht', 0),
                                            navButton('Projekte', 1),
                                            navButton('Exportprofil', 2),
                                            navButton('Einstellungen', 3),
                                          ],
                                        ),
                                      ),
                                    ),
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
                              const Divider(
                                height: 1,
                                color: Color(0xFFE2E3DE),
                              ),
                              Expanded(
                                child: switch (tab) {
                                  0 => journal(now),
                                  1 => projectPage(),
                                  2 => ExportSettings(tracker: tracker),
                                  _ => settingsPage(),
                                },
                              ),
                              Container(
                                padding: const EdgeInsets.fromLTRB(
                                  28,
                                  8,
                                  28,
                                  12,
                                ),
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
                                        style: TextStyle(
                                          color: muted,
                                          fontSize: 11,
                                        ),
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
      height: compactBarHeight,
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
                    onPressed: changingWindow ? null : toggleCompact,
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
                      elapsed(total),
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
                  onPressed: changingWindow ? null : toggleCompact,
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
          const SizedBox(height: 6),
          SizedBox(
            height: 32,
            child: Row(
              children: [
                Icon(
                  active == null
                      ? Icons.stop_circle_outlined
                      : isBreak
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_fill,
                  size: 20,
                  color: active == null
                      ? Colors.white54
                      : isBreak
                      ? orange
                      : Colors.white,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    active == null
                        ? 'GESTOPPT'
                        : isBreak
                        ? 'PAUSE · ${tracker.data.project(tracker.data.lastProject).name}'
                        : 'AKTIV · ${tracker.data.project(active.projectId!).name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: active == null ? Colors.white54 : Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                TextButton.icon(
                  key: const Key('f9-text'),
                  onPressed: () => editDayNotes(
                    now,
                    projectIds: [active?.projectId ?? tracker.data.lastProject],
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor:
                        tracker.data
                            .notesForDay(
                              now,
                              active?.projectId ?? tracker.data.lastProject,
                              now,
                            )
                            .isEmpty
                        ? orange
                        : Colors.white70,
                  ),
                  icon: const Icon(Icons.edit_note, size: 19),
                  label: Text(
                    tracker.data
                            .notesForDay(
                              now,
                              active?.projectId ?? tracker.data.lastProject,
                              now,
                            )
                            .isEmpty
                        ? 'F9-Text erfassen'
                        : 'F9-Text bearbeiten',
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
      Image.asset(
        'assets/animals/${tracker.data.animal}.png',
        width: 40,
        height: 40,
        excludeFromSemantics: true,
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
    return Semantics(
      selected: active,
      button: true,
      label: '${project.name}${active ? ', aktiv' : ''}',
      child: Tooltip(
        message: '${project.name}${index < 9 ? ' · Strg + ${index + 1}' : ''}',
        child: Material(
          color: active ? Colors.white : const Color(0xFF2B3849),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            key: Key('project-${project.id}'),
            onTap: tracker.busy ? null : () => tracker.switchTo(project.id),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              constraints: const BoxConstraints(minWidth: 144, maxWidth: 240),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: active ? color : color.withValues(alpha: 0.4),
                  width: active ? 3 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    active ? Icons.check_circle : Icons.circle,
                    color: color,
                    size: active ? 19 : 9,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          project.name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: active ? ink : Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (active)
                          const Text(
                            'AKTIV',
                            style: TextStyle(
                              color: ink,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    elapsed(duration),
                    style: TextStyle(
                      color: active ? ink : Colors.white54,
                      fontSize: 11,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
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
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                key: const Key('previous-day'),
                onPressed: () => setState(
                  () => selectedDay = DateTime(
                    selectedDay.year,
                    selectedDay.month,
                    selectedDay.day - 1,
                  ),
                ),
                icon: const Icon(Icons.chevron_left, size: 18),
                label: const Text('Vorheriger Tag'),
              ),
              OutlinedButton.icon(
                key: const Key('choose-day'),
                onPressed: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: selectedDay,
                    firstDate: selectedDay.isBefore(DateTime(1970))
                        ? selectedDay
                        : DateTime(1970),
                    lastDate: now,
                  );
                  if (date != null && mounted) {
                    setState(() => selectedDay = date);
                  }
                },
                icon: const Icon(Icons.calendar_today_outlined, size: 16),
                label: Text(
                  '${two(selectedDay.day)}.${two(selectedDay.month)}.${selectedDay.year}',
                ),
              ),
              IconButton(
                key: const Key('next-day'),
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
                icon: const Icon(Icons.chevron_right),
              ),
              TextButton(
                key: const Key('today'),
                onPressed: isToday
                    ? null
                    : () => setState(() => selectedDay = dayStart(now)),
                child: const Text('Heute'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            isToday
                ? 'Tagesverlauf und Projektverteilung zeigen die exakten Rohzeiten.'
                : 'Vergangener Tag · Einträge anklicken, um Zeiten oder Zuordnung zu korrigieren. F9-Texte sind ebenfalls bearbeitbar.',
            style: const TextStyle(color: muted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              TextButton.icon(
                onPressed: () => editDayNotes(selectedDay),
                icon: const Icon(Icons.edit_note),
                label: const Text('F9-Texte für diesen Tag'),
              ),
              TextButton.icon(
                onPressed: entries.isEmpty || tracker.busy
                    ? null
                    : confirmDeleteDay,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Tag löschen'),
              ),
            ],
          ),
          const SizedBox(height: 12),
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
      key: Key('entry-${entry.id}'),
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
  Widget settingsPage() => SingleChildScrollView(
    padding: const EdgeInsets.all(28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Dein Stundehund.',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        const Text(
          'Wähle dein Tier für die App und das laufende Fenster-/Dock-Symbol.',
          style: TextStyle(color: muted),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            for (final animal in animalNames.entries)
              Semantics(
                selected: tracker.data.animal == animal.key,
                child: InkWell(
                  key: Key('animal-${animal.key}'),
                  onTap: tracker.busy
                      ? null
                      : () => tracker.saveAnimal(animal.key),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    width: 160,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: tracker.data.animal == animal.key
                            ? const Color(0xFF3F8269)
                            : const Color(0xFFE0E3DE),
                        width: 2,
                      ),
                    ),
                    child: Column(
                      children: [
                        Image.asset(
                          'assets/animals/${animal.key}.png',
                          width: 72,
                          height: 72,
                        ),
                        const SizedBox(height: 12),
                        Text(animal.value),
                        const SizedBox(height: 4),
                        Icon(
                          tracker.data.animal == animal.key
                              ? Icons.check_circle
                              : Icons.circle_outlined,
                          size: 18,
                          color: const Color(0xFF3F8269),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 32),
        const Text(
          'Zurücksetzen & Wiederherstellen',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Alle Zeitdaten zurücksetzen'),
          subtitle: const Text(
            'Löscht alle Tage und F9-Texte. Projekte und Einstellungen bleiben erhalten.',
          ),
          trailing: OutlinedButton(
            onPressed: tracker.busy ? null : confirmResetTimes,
            child: const Text('Zurücksetzen'),
          ),
        ),
        if (tracker.data.deletedTimes != null)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Letzte Löschung wiederherstellen'),
            subtitle: Text(tracker.data.deletedTimes!.label),
            trailing: FilledButton(
              onPressed: tracker.busy
                  ? null
                  : () async {
                      if (await tracker.restoreDeletedTimes()) {
                        snack('Zeiten wiederhergestellt.');
                      }
                    },
              child: const Text('Wiederherstellen'),
            ),
          ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Exportprofil zurücksetzen'),
          subtitle: const Text(
            'Standardspalten, F9-Text und Rundung auf 15 Minuten.',
          ),
          trailing: OutlinedButton(
            onPressed: tracker.busy
                ? null
                : () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Exportprofil zurücksetzen?'),
                        content: const Text(
                          'Eigene Spalten und Personalnummer werden durch das Standardprofil ersetzt. Zeitdaten und Projekte bleiben erhalten.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Abbrechen'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Zurücksetzen'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true &&
                        await tracker.saveProfile(const ExportProfile())) {
                      snack('Exportprofil zurückgesetzt.');
                    }
                  },
            child: const Text('Zurücksetzen'),
          ),
        ),
        if (widget.desktop)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Fensterposition zurücksetzen'),
            subtitle: const Text(
              'Fenster einmalig auf dem Bildschirm zentrieren.',
            ),
            trailing: OutlinedButton(
              onPressed: () => windowManager.center(),
              child: const Text('Zentrieren'),
            ),
          ),
      ],
    ),
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
