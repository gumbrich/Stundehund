import 'package:flutter/material.dart';
import 'model.dart';
import 'tracker.dart';

class DayNotesDialog extends StatefulWidget {
  const DayNotesDialog({
    super.key,
    required this.tracker,
    required this.day,
    required this.projectIds,
  });
  final Tracker tracker;
  final DateTime day;
  final List<String> projectIds;
  @override
  State<DayNotesDialog> createState() => _DayNotesDialogState();
}

class _DayNotesDialogState extends State<DayNotesDialog> {
  late final fields = {
    for (final id in widget.projectIds)
      id: TextEditingController(
        text: widget.tracker.data.notesForDay(
          widget.day,
          id,
          widget.tracker.clock(),
        ),
      ),
  };
  bool saving = false;
  String? error;
  @override
  void dispose() {
    for (final field in fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  void toggle(TextEditingController field, String suggestion) {
    final parts = field.text
        .split(';')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.contains(suggestion)) {
      parts.remove(suggestion);
    } else {
      parts.add(suggestion);
    }
    setState(() {
      field.text = parts.join('; ');
      field.selection = TextSelection.collapsed(offset: field.text.length);
    });
  }

  Future<void> save() async {
    if (fields.values.any((f) => f.text.trim().isEmpty)) {
      setState(
        () => error =
            'Bitte für jedes Projekt ein Stichwort wählen oder einen eigenen Text eingeben.',
      );
      return;
    }
    setState(() => saving = true);
    final ok = await widget.tracker.saveDayNotes(
      widget.day,
      fields.map((id, field) => MapEntry(id, field.text)),
    );
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
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
      'F9-Text · ${two(widget.day.day)}.${two(widget.day.month)}.${widget.day.year}',
    ),
    content: SizedBox(
      width: 680,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Grobe Stichworte pro Projekt und Tag. Mehrere Vorschläge kombinieren oder frei ergänzen.',
            ),
            const SizedBox(height: 20),
            for (final id in widget.projectIds)
              Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.circle,
                          size: 10,
                          color: Color(widget.tracker.data.project(id).color),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.tracker.data.project(id).name,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final suggestion in activitySuggestions)
                          FilterChip(
                            label: Text(
                              suggestion,
                              style: const TextStyle(fontSize: 12),
                            ),
                            selected: fields[id]!.text
                                .split(';')
                                .map((s) => s.trim())
                                .contains(suggestion),
                            onSelected: saving
                                ? null
                                : (_) => toggle(fields[id]!, suggestion),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: Key('day-note-$id'),
                      controller: fields[id],
                      onChanged: (_) => setState(() {}),
                      enabled: !saving,
                      maxLength: 1000,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'F9-Text / eigene Stichworte',
                      ),
                    ),
                  ],
                ),
              ),
            if (error != null)
              Text(error!, style: const TextStyle(color: Colors.red)),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: saving ? null : () => Navigator.pop(context, false),
        child: const Text('Abbrechen'),
      ),
      FilledButton(
        onPressed: saving ? null : save,
        child: const Text('Speichern'),
      ),
    ],
  );
}
