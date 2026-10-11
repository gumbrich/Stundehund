import 'package:flutter/material.dart';
import 'model.dart';
import 'tracker.dart';

class ProjectDialog extends StatefulWidget {
  const ProjectDialog({super.key, required this.tracker, this.project});
  final Tracker tracker;
  final Project? project;
  @override
  State<ProjectDialog> createState() => _ProjectDialogState();
}

class _ProjectDialogState extends State<ProjectDialog> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.project?.name ?? '');
  late final code = TextEditingController(text: widget.project?.code ?? '');
  late final activity = TextEditingController(
    text: widget.project?.activity ?? '',
  );
  late int color =
      widget.project?.color ??
      projectColors[(widget.tracker.data.projects.length - 1) %
          projectColors.length];
  late bool archived = widget.project?.archived ?? false;
  bool saving = false;
  String? error;
  @override
  void dispose() {
    name.dispose();
    code.dispose();
    activity.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate() || saving) {
      return;
    }
    setState(() => saving = true);
    final ok = await widget.tracker.saveProject(
      Project(
        id: widget.project?.id ?? widget.tracker.nextId(),
        name: name.text.trim(),
        color: color,
        code: code.text.trim(),
        activity: activity.text.trim(),
        archived: archived,
      ),
    );
    if (!mounted) {
      return;
    }
    if (ok) {
      Navigator.pop(context);
    } else {
      setState(() {
        saving = false;
        error = widget.tracker.error ?? 'Bitte erneut versuchen.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.project == null ? 'Neues Projekt' : 'Projekt bearbeiten',
    ),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: name,
                autofocus: true,
                readOnly: widget.project?.id == otherId,
                maxLength: 50,
                decoration: const InputDecoration(labelText: 'Projektname'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Bitte einen Namen eingeben.'
                    : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: code,
                maxLength: 50,
                decoration: const InputDecoration(
                  labelText: 'Abacus-Projektnummer',
                  helperText: 'Kann später ergänzt werden.',
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: activity,
                maxLength: 50,
                decoration: const InputDecoration(
                  labelText: 'Leistungsart (optional)',
                ),
              ),
              const SizedBox(height: 14),
              const Text('Projektfarbe'),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  for (final c in {...projectColors, 0xFF7A8391})
                    Semantics(
                      label: 'Farbe ${projectColors.indexOf(c) + 1}',
                      selected: c == color,
                      button: true,
                      child: InkWell(
                        onTap: () => setState(() => color = c),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(c),
                          ),
                          child: c == color
                              ? const Icon(
                                  Icons.check,
                                  color: Colors.white,
                                  size: 19,
                                )
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
              if (widget.project != null && widget.project!.id != otherId)
                Padding(
                  padding: const EdgeInsets.only(top: 15),
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Projekt archivieren'),
                    subtitle: Text(
                      widget.tracker.data.active?.projectId ==
                              widget.project!.id
                          ? 'Bitte zuerst zu einem anderen Projekt wechseln.'
                          : 'Zeitdaten bleiben erhalten.',
                    ),
                    value: archived,
                    onChanged:
                        widget.tracker.data.active?.projectId ==
                            widget.project!.id
                        ? null
                        : (v) => setState(() => archived = v),
                  ),
                ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: saving ? null : () => Navigator.pop(context),
        child: const Text('Abbrechen'),
      ),
      FilledButton(
        onPressed: saving ? null : save,
        child: const Text('Speichern'),
      ),
    ],
  );
}

class EntryDialog extends StatefulWidget {
  const EntryDialog({
    super.key,
    required this.tracker,
    required this.day,
    this.entry,
  });
  final Tracker tracker;
  final DateTime day;
  final TimeEntry? entry;
  @override
  State<EntryDialog> createState() => _EntryDialogState();
}

class _EntryDialogState extends State<EntryDialog> {
  final form = GlobalKey<FormState>();
  late final startDate = TextEditingController(
    text: isoDay(widget.entry?.start ?? widget.day),
  );
  late final endDate = TextEditingController(
    text: isoDay(widget.entry?.end ?? widget.day),
  );
  late final start = TextEditingController(
    text: widget.entry == null
        ? '08:00:00'
        : clockTime(widget.entry!.start, seconds: true),
  );
  late final end = TextEditingController(
    text: widget.entry == null
        ? '09:00:00'
        : clockTime(widget.entry!.end!, seconds: true),
  );
  late final note = TextEditingController(text: widget.entry?.note ?? '');
  late String project = widget.entry == null
      ? otherId
      : widget.entry!.projectId ?? '__pause';
  String? error;
  bool saving = false;
  @override
  void dispose() {
    for (final c in [startDate, endDate, start, end, note]) {
      c.dispose();
    }
    super.dispose();
  }

  DateTime? parse(String day, String time) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(day) ||
        !RegExp(r'^\d{2}:\d{2}(:\d{2})?$').hasMatch(time)) {
      return null;
    }
    final date = DateTime.tryParse('${day}T$time');
    if (date == null ||
        isoDay(date) != day ||
        clockTime(date, seconds: time.length > 5) != time) {
      return null;
    }
    return date;
  }

  Future<void> save() async {
    if (saving) {
      return;
    }
    final from = parse(startDate.text.trim(), start.text.trim());
    final until = parse(endDate.text.trim(), end.text.trim());
    if (from == null || until == null) {
      setState(
        () => error =
            'Bitte Datum als JJJJ-MM-TT und Zeit als HH:MM oder HH:MM:SS eingeben.',
      );
      return;
    }
    final entry = TimeEntry(
      id: widget.entry?.id ?? widget.tracker.nextId(),
      start: from,
      end: until,
      projectId: project == '__pause' ? null : project,
      note: note.text.trim(),
    );
    final message = widget.tracker.validateEntry(entry);
    if (message != null) {
      setState(() => error = message);
      return;
    }
    setState(() => saving = true);
    final ok = await widget.tracker.saveEntry(entry);
    if (!mounted) {
      return;
    }
    if (ok) {
      Navigator.pop(context);
    } else {
      setState(() {
        saving = false;
        error = widget.tracker.error ?? 'Bitte erneut versuchen.';
      });
    }
  }

  Future<void> remove() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eintrag löschen?'),
        content: const Text(
          'Dieser Zeitraum wird aus der Zeiterfassung entfernt.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (yes != true) {
      return;
    }
    setState(() => saving = true);
    final ok = await widget.tracker.deleteEntry(widget.entry!.id);
    if (!mounted) {
      return;
    }
    if (ok) {
      Navigator.pop(context);
    } else {
      setState(() {
        saving = false;
        error = widget.tracker.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.entry == null ? 'Zeit nachtragen' : 'Eintrag bearbeiten',
    ),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: project,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Projekt'),
              items: [
                for (final p in widget.tracker.data.projects.where(
                  (p) => !p.archived || p.id == project,
                ))
                  DropdownMenuItem(value: p.id, child: Text(p.name)),
                const DropdownMenuItem(value: '__pause', child: Text('Pause')),
              ],
              onChanged: (value) => setState(() => project = value!),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: startDate,
                    decoration: const InputDecoration(
                      labelText: 'Beginn · Datum',
                      hintText: 'JJJJ-MM-TT',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: start,
                    decoration: const InputDecoration(
                      labelText: 'Uhrzeit',
                      hintText: 'HH:MM:SS',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: endDate,
                    decoration: const InputDecoration(
                      labelText: 'Ende · Datum',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: end,
                    decoration: const InputDecoration(labelText: 'Uhrzeit'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: note,
              maxLines: 2,
              maxLength: 300,
              decoration: const InputDecoration(
                labelText: 'Bemerkung (optional)',
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(error!, style: const TextStyle(color: Colors.red)),
              ),
          ],
        ),
      ),
    ),
    actions: [
      if (widget.entry != null)
        TextButton(
          onPressed: saving ? null : remove,
          child: const Text('Löschen', style: TextStyle(color: Colors.red)),
        ),
      TextButton(
        onPressed: saving ? null : () => Navigator.pop(context),
        child: const Text('Abbrechen'),
      ),
      FilledButton(
        onPressed: saving ? null : save,
        child: const Text('Speichern'),
      ),
    ],
  );
}
