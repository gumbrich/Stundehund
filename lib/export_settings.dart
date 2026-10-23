import 'package:flutter/material.dart';
import 'model.dart';
import 'tracker.dart';

class ExportSettings extends StatefulWidget {
  const ExportSettings({super.key, required this.tracker});
  final Tracker tracker;
  @override
  State<ExportSettings> createState() => _ExportSettingsState();
}

class _ExportSettingsState extends State<ExportSettings> {
  late final employee = TextEditingController(
    text: widget.tracker.data.profile.employee,
  );
  late String delimiter = widget.tracker.data.profile.delimiter;
  late String dateFormat = widget.tracker.data.profile.dateFormat;
  late String rounding = widget.tracker.data.profile.rounding;
  late String durationFormat = widget.tracker.data.profile.durationFormat;
  late bool decimalComma = widget.tracker.data.profile.decimalComma;
  late bool summary = widget.tracker.data.profile.summary;
  late bool includeBreaks = widget.tracker.data.profile.includeBreaks;
  late bool header = widget.tracker.data.profile.header;
  late bool bom = widget.tracker.data.profile.bom;
  late List<ExportField> order = [
    ...widget.tracker.data.profile.columns.map((c) => c.field),
    ...ExportField.values.where(
      (f) => !widget.tracker.data.profile.columns.any((c) => c.field == f),
    ),
  ];
  late Set<ExportField> enabled =
      widget.tracker.data.profile.columns.map((c) => c.field).toSet()
        ..add(ExportField.note);
  late Map<ExportField, TextEditingController> headers = {
    for (final f in ExportField.values)
      f: TextEditingController(
        text:
            widget.tracker.data.profile.columns
                .where((c) => c.field == f)
                .firstOrNull
                ?.header ??
            exportLabels[f.index],
      ),
  };
  bool saving = false;
  String? message;
  @override
  void dispose() {
    employee.dispose();
    for (final c in headers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (enabled.isEmpty) {
      setState(() => message = 'Bitte mindestens eine Spalte auswählen.');
      return;
    }
    if (enabled.any((f) => headers[f]!.text.trim().isEmpty)) {
      setState(() => message = 'Bitte alle ausgewählten Spalten benennen.');
      return;
    }
    final profile = ExportProfile(
      employee: employee.text.trim(),
      delimiter: delimiter,
      dateFormat: dateFormat,
      durationFormat: durationFormat,
      decimalComma: decimalComma,
      summary: summary,
      includeBreaks: includeBreaks,
      header: header,
      bom: bom,
      rounding: rounding,
      columns: order
          .where(enabled.contains)
          .map((f) => ExportColumn(f, headers[f]!.text.trim()))
          .toList(),
    );
    setState(() => saving = true);
    final ok = await widget.tracker.saveProfile(profile);
    if (mounted) {
      setState(() {
        saving = false;
        message = ok ? 'Exportprofil gespeichert.' : widget.tracker.error;
      });
    }
  }

  Widget dropdown(
    String title,
    String value,
    Map<String, String> values,
    void Function(String) onChange,
  ) => DropdownButtonFormField<String>(
    key: ValueKey('$title:$value'),
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(labelText: title),
    items: values.entries
        .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
        .toList(),
    onChanged: (v) => setState(() {
      onChange(v!);
      message = null;
    }),
  );
  Widget pair(Widget a, Widget b) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: a),
        const SizedBox(width: 18),
        Expanded(child: b),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(28),
    child: Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
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
                        'Bereit für die Übergabe.',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Passe die CSV-Datei an die Importvorlage deiner Firma an.',
                        style: TextStyle(color: Color(0xFF747D88)),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: saving ? null : save,
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Profil speichern'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFEEECE3),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 18),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Abacus-Import noch nicht bestätigt. Frage deine Administration nach einer Importvorlage, Personalnummer, Projektnummern und Leistungsarten. Bis dahin dient die CSV auch als übersichtlicher Rapport.',
                      style: TextStyle(fontSize: 12, height: 1.6),
                    ),
                  ),
                ],
              ),
            ),
            if (message != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  message!,
                  style: TextStyle(
                    color: message == 'Exportprofil gespeichert.'
                        ? const Color(0xFF3F8269)
                        : Colors.red,
                  ),
                ),
              ),
            const SizedBox(height: 24),
            pair(
              TextField(
                controller: employee,
                decoration: const InputDecoration(labelText: 'Personalnummer'),
              ),
              rounding != 'none'
                  ? const InputDecorator(
                      decoration: InputDecoration(labelText: 'Zeilen'),
                      child: Text('Eine Zeile pro Projekt und Tag'),
                    )
                  : dropdown(
                      'Zeilen',
                      summary ? 'summary' : 'interval',
                      const {
                        'summary': 'Eine Zeile pro Projekt und Tag',
                        'interval': 'Eine Zeile pro Zeitabschnitt',
                      },
                      (v) => summary = v == 'summary',
                    ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: dropdown('Rundung pro Projekt / Tag', rounding, const {
                'nearest':
                    '15 Minuten · kaufmännisch (ab 7½ Minuten aufrunden)',
                'none': 'Keine Rundung · Rohdaten',
              }, (v) => rounding = v),
            ),
            pair(
              dropdown('Trennzeichen', delimiter, const {
                ';': 'Semikolon (;)',
                ',': 'Komma (,)',
                '\t': 'Tabulator',
              }, (v) => delimiter = v),
              dropdown('Datum', dateFormat, const {
                'dd.MM.yyyy': 'TT.MM.JJJJ',
                'yyyy-MM-dd': 'JJJJ-MM-TT',
              }, (v) => dateFormat = v),
            ),
            pair(
              dropdown('Dauer', durationFormat, const {
                'decimal': 'Dezimalstunden (1.50)',
                'minutes': 'Minuten (90)',
                'hhmm': 'Stunden:Minuten (01:30)',
                'hhmmss': 'Sekunden nur ohne Rundung',
              }, (v) => durationFormat = v),
              dropdown(
                'Dezimalzeichen',
                decimalComma ? ',' : '.',
                const {'.': 'Punkt (1.50)', ',': 'Komma (1,50)'},
                (v) => decimalComma = v == ',',
              ),
            ),
            Wrap(
              spacing: 20,
              runSpacing: 8,
              children: [
                option('Kopfzeile', header, (v) => header = v),
                option('UTF-8 mit BOM', bom, (v) => bom = v),
                option(
                  'Pausen exportieren',
                  includeBreaks,
                  (v) => includeBreaks = v,
                ),
              ],
            ),
            const SizedBox(height: 26),
            const Text(
              'Spalten & Reihenfolge',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              (rounding != 'none' || summary)
                  ? '«Von» und «Bis» bleiben bei Tagessummen leer.'
                  : 'Zeitabschnitte werden an Mitternacht getrennt. Das Tagesende wird als 24:00:00 ausgegeben.',
              style: const TextStyle(fontSize: 12, color: Color(0xFF747D88)),
            ),
            const SizedBox(height: 14),
            for (var i = 0; i < order.length; i++) columnRow(order[i], i),
            const SizedBox(height: 20),
            const Text(
              'Die Projektzeiten werden zuerst pro Tag summiert und erst dann gerundet. Die Vorschau zeigt Rohzeit und Exportzeit. Auf 0 gerundete Projekte entfallen im CSV. F9-Texte sind für bearbeitete Projekte erforderlich. Dateien verwenden UTF-8 und Windows-Zeilenumbrüche (CRLF).',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF747D88),
                height: 1.6,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: saving ? null : save,
              child: const Text('Profil speichern'),
            ),
          ],
        ),
      ),
    ),
  );
  Widget option(String label, bool value, void Function(bool) onChange) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Checkbox(value: value, onChanged: (v) => setState(() => onChange(v!))),
      Text(label, style: const TextStyle(fontSize: 13)),
    ],
  );
  Widget columnRow(ExportField field, int index) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Checkbox(
          value: enabled.contains(field),
          onChanged: field == ExportField.note
              ? null
              : (v) => setState(() {
                  if (v!) {
                    enabled.add(field);
                  } else {
                    enabled.remove(field);
                  }
                }),
        ),
        SizedBox(
          width: 140,
          child: Text(
            exportLabels[field.index],
            style: const TextStyle(fontSize: 13),
          ),
        ),
        Expanded(
          child: TextField(
            controller: headers[field],
            enabled: enabled.contains(field),
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Spaltenname in CSV',
            ),
          ),
        ),
        const SizedBox(width: 12),
        IconButton(
          tooltip: 'Nach oben',
          onPressed: index == 0
              ? null
              : () => setState(() {
                  order.removeAt(index);
                  order.insert(index - 1, field);
                }),
          icon: const Icon(Icons.arrow_upward, size: 16),
        ),
        IconButton(
          tooltip: 'Nach unten',
          onPressed: index == order.length - 1
              ? null
              : () => setState(() {
                  order.removeAt(index);
                  order.insert(index + 1, field);
                }),
          icon: const Icon(Icons.arrow_downward, size: 16),
        ),
      ],
    ),
  );
}
