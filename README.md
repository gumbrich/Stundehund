# Stundehund

A small, private Windows desktop timekeeper. Click a coloured project button,
work, switch projects, and export the day. German (Swiss) interface.
The top workday timer displays hours and minutes (`HH:MM`).

Choose **Hund**, **Eichhörnchen** or **Eule** under **Einstellungen**. The choice
is saved and updates the in-app mark and the running Windows window/taskbar or
Mac Dock icon. The executable/Finder file icon remains the default dog.
Regenerate artwork with `python3 tool/generate_icons.py` (Pillow required).

## Download and run

**Desktop preview:** the build workflow runs static analysis, the automated
regression suite and a native window test on Windows before creating the ZIP.
The native window test repeatedly switches compact/expanded modes and minimises /
restores the real application window, checking its coordinates.

Download **Stundehund-Windows-x64.zip** from this private repository's
[Releases](https://github.com/gumbrich/Stundehund/releases), extract the **whole folder**, and run `stundehund.exe`.
Keep the DLLs and `data` folder beside the executable. No Flutter SDK or
administrator installation is needed on the target computer.

The same release also includes **Stundehund-macOS.zip** for trying the desktop
app on a Mac. Extract it and open `Stundehund.app`. This development preview is
not notarized for distribution.

Target: **Windows 11, x64**. Builds are unsigned. Windows on ARM and managed
company deployments have not been tested. A macOS target is included for local
development and native integration testing.

## Daily workflow

1. Add projects under **Projekte**, choosing a name, colour, optional Abacus
   project number and activity code. **Anderes** is always available.
2. Press **Start**, or a project button, to begin. Start resumes your last
   project, initially Anderes. Only one project runs at a time.
3. Switch projects with one click. **Pause** excludes breaks from work totals;
   **Weiter** resumes the preceding project. Selecting a project also ends a break.
4. The upper-right arrow switches to a compact, draggable bar kept above other
   windows. Switching layouts preserves its current top-left position, including
   on a secondary screen. Drag it to the position you prefer. The active project
   has a white tile, checkmark and **AKTIV** label, plus a persistent status line.
   The Windows taskbar title also identifies the active project.
5. Press **Stop**. Review project totals and individual intervals. Click a closed
   interval to correct its project, times or note. **Nachtragen** adds missed time;
   overlapping and future intervals are rejected.
6. **F9-Text erfassen** (or F9 / Fn+F9 according to the keyboard) records daily
   project keywords. Choose preset phrases, combine them, or type custom text.
   Missing F9 texts must be completed before export. These are descriptive texts,
   separate from the project's Abacus activity code (**Leistungsart**).
7. **Vorheriger Tag**, the calendar, the next-day arrow and **Heute** let you review
   any earlier day. Click a closed interval to edit its exact start/end, project
   or note. Edit that day's F9 texts separately. Browsing/editing a previous day
   does not switch the live project timer. F9 follows the selected day in the
   dashboard; the compact bar always refers to today.
8. **CSV exportieren** previews raw and rounded project totals for the selected
   date. Stopping does not erase anything and you can restart.

Keyboard shortcuts apply while the app has focus: `Ctrl+1`…`Ctrl+9` selects a
project in bar order; `Ctrl+Space` starts/pauses/resumes; `Ctrl+Shift+S` starts/stops.
More projects remain reachable by horizontal scrolling.

## Abacus export — configuration required

**This is a configurable CSV exporter, not a verified Abacus connector.** The
employer's import template is not available yet. Do not assume the default CSV
will import directly. Abacus documents data exchange through
[AbaConnect](https://downloads.abacus.ch/downloads/abaconnect/dokumentationen),
with application/version-specific interfaces and mappings.

Ask your administrator for the accepted file format and an example, employee
number, project numbers, activity codes, field order, date/duration formats,
encoding, rounding rules, and whether attendance and project reports are separate
imports. Match **Exportprofil**, save it, and have a small sample validated first.
If XML/AbaConnect is required, a matching exporter must be added once the mapping
is supplied. There is no automatic submission or Abacus login.

Configurable options:

- Column selection, order and header names: date, employee, project number/name,
  activity, start/end, duration and note.
- Nearest-quarter-hour daily project totals by default. Optional unrounded mode
  supports daily totals or separate intervals; optional breaks.
- Semicolon, comma or tab; decimal point or comma; ISO or Swiss dates.
- Rounded decimal hours (e.g. `1.25`), whole minutes or `HH:MM`; unrounded mode
  also supports decimal hours with 4 places, minutes with 2 places, or `HH:MM:SS`.
- Optional header and UTF-8 BOM; CRLF line endings and CSV quoting.

Exact timestamps and intervals are preserved in local storage and JSON backups.
Project totals and interval details in the dashboard continue to show raw time.
Export first sums **all intervals of each project within the selected calendar
day**, then rounds to the nearest 15 minutes (7 minutes 30 seconds rounds up).
For example, 22 minutes becomes 15 minutes; 23 minutes becomes 30 minutes. Short
switches are never rounded individually. The preview shows raw versus rounded
values; project rounding can change the overall daily total. Projects rounded to
zero are shown in the preview but omitted from the CSV. If all rows round to zero,
the preview explains this and no empty report is saved. For unrounded exports,
choose **Keine Rundung · Rohdaten** in the export profile.

Summaries leave start/end blank because project work may be discontinuous.
Overnight intervals split at local calendar midnight; an interval ending at that
boundary exports `24:00:00`. The F9 text is kept per project and day and included
in the default CSV. Existing interval notes are used as a fallback until a daily
F9 text is entered. Leading zeroes in codes
are preserved in the CSV text; spreadsheet software may reinterpret them when
opening a file. Text is exported verbatim, so only use trusted project names/notes
when opening exports in software that evaluates spreadsheet formulas.

## Delete and reset

**Tag löschen** deletes only the selected day's intervals and F9 texts after
confirmation. Today's running interval is stopped if it belongs to that day.
Intervals crossing midnight are clipped so adjacent days remain intact.

**Einstellungen → Alle Zeitdaten zurücksetzen** clears all times/F9 texts while
keeping projects, the animal choice and export settings. There are also separate
controls for resetting the export profile and explicitly centring the window.

**Letzte Löschung wiederherstellen** restores the latest deleted day, reset or
individual entry, even after restarting the app. This recovery point is replaced
by the next deletion. Restoring merges with new work; it refuses overlapping
records instead of overwriting them. Restored intervals are closed, so restoring
a day does not accidentally restart its timer. Regular JSON backups are still
recommended.

## Storage and recovery

No server, telemetry or network calls at runtime. Data lives in the OS application
support directory, with its exact path shown under **Projekte**. Two alternating
JSON snapshots are flushed to disk on every change and every 30 seconds while
running. A failed write leaves the previous state active and shows an error. If
one snapshot is corrupt, the other is used with a warning; unreadable data is
never replaced with an empty database. Windows also uses a single-instance mutex.

On normal close, an active timer is stopped and saved after confirmation. After a
crash/restart it is stopped at the last durable heartbeat (up to 30 seconds may
need correction). A gap between timer ticks over 90 seconds, or a backwards clock
jump, stops recording at the last observed tick and requests review. This avoids
silently recording hours of sleep time. **Locking the screen alone does not pause
recording**; use Pause before stepping away. This is not an idle/activity monitor.
Timestamps are stored in UTC and displayed/grouped in the computer's current local
timezone. Changing timezone can therefore change historical day grouping.

**Sicherung** saves a portable JSON backup. Back up regularly. To restore, close
the app, preserve the two current files, and put the backup in `time-1.json` wrapped
as `{"sequence":1,"data": <backup JSON object>}`; remove `time-0.json` from the active
data directory. Reopen and verify the records. Do not edit live snapshots.

## Development

Flutter **3.41.5**, Dart **3.11.3**. Dependencies are locked. On Windows install
Visual Studio with **Desktop development with C++**, plus the Windows SDK.

```sh
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter test integration_test/window_test.dart -d windows
flutter run -d windows
flutter build windows --release
```

To produce the portable ZIP on a Windows build machine:

```powershell
.\tool\build_windows.ps1
```

The script checks formatting, analysis and tests, builds the release, bundles the
Visual C++ runtime, and writes `Stundehund-Windows-x64.zip` to the repository root.
The same script is used by the GitHub Windows build workflow.

On macOS, use `flutter run -d macos`. The Windows workflow runs formatting,
analysis, tests and a native release build; bundles Visual C++ runtime DLLs; and
uploads a portable ZIP. Pushing a `v*` tag uploads the ZIP directly to a draft
prerelease in this **private** repository; attach the Mac ZIP and checksums before
publishing it. Direct release uploads do not depend on Actions artifact storage.
Development artifact uploads are optional when that storage quota is full.
Workflow artifacts expire after 90 days; release assets remain.

Core code: `model.dart` (data/calendar boundaries), `tracker.dart` (transitions),
`storage.dart` (durable snapshots), `csv_export.dart` (mapping/formatting). UI and
native window control are separated from timekeeping for deterministic testing.
Tests cover switching, breaks, failures, restart/sleep recovery, manual edits,
CSV formats/escaping/aggregation, quarter-hour boundaries, exact-data retention,
F9 text and migration, historical editing, deletion/restore, midnight splitting,
corrupted files, animal selection and native window positions.

Private software. All rights reserved. No affiliation with Abacus Research AG.
