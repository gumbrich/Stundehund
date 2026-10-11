# Stundehund

A small, private Windows desktop timekeeper. Click a coloured project button,
work, switch projects, and export the day. German (Swiss) interface.

## Download and run

**Build status:** the source and local tests are complete, but no Windows binary
has been published yet. GitHub refused the first Windows job before execution
because the account's Actions budget prevents further use. After enabling the
budget, rerun the workflow; alternatively use the Windows build script below.

Download **Stundehund-Windows-x64.zip** from this private repository's
[Releases](https://github.com/gumbrich/Stundehund/releases), extract the **whole folder**, and run `stundehund.exe`.
Keep the DLLs and `data` folder beside the executable. No Flutter SDK or
administrator installation is needed on the target computer.

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
4. The upper-right arrow switches to a compact, draggable bar positioned at the
   top of the primary screen and kept above other windows. Expand it to review.
5. Press **Stop**. Review project totals and individual intervals. Click a closed
   interval to correct its project, times or note. **Nachtragen** adds missed time;
   overlapping and future intervals are rejected.
6. **CSV exportieren** previews and saves the selected date. The calendar provides
   access to earlier days. Stopping does not erase anything and you can restart.

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
- One row per project/day or one row per interval; optional breaks.
- Semicolon, comma or tab; decimal point or comma; ISO or Swiss dates.
- Decimal hours (4 decimals), minutes (2 decimals), or `HH:MM:SS`.
- Optional header and UTF-8 BOM; CRLF line endings and CSV quoting.

Raw timestamps are preserved. Summaries aggregate before rounding and leave
start/end blank because the work may be discontinuous. Overnight intervals split
at local calendar midnight; an interval ending at that boundary exports `24:00:00`.
There is no implicit five/fifteen-minute payroll rounding. Leading zeroes in codes
are preserved in the CSV text; spreadsheet software may reinterpret them when
opening a file. Text is exported verbatim, so only use trusted project names/notes
when opening exports in software that evaluates spreadsheet formulas.

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
flutter run -d windows
flutter build windows --release
```

To produce the portable ZIP on a Windows build machine:

```powershell
.\tool\build_windows.ps1
```

The script checks formatting, analysis and tests, builds the release, bundles the
Visual C++ runtime, and writes `Stundehund-Windows-x64.zip` to the repository root.
The Windows script and pipeline await execution on a Windows host.

On macOS, use `flutter run -d macos`. The Windows workflow runs formatting,
analysis, tests and a native release build; bundles Visual C++ runtime DLLs; and
uploads a portable ZIP. Pushing a `v*` tag creates a release in this **private**
repository. Workflow artifacts expire after 90 days; release assets remain.

Core code: `model.dart` (data/calendar boundaries), `tracker.dart` (transitions),
`storage.dart` (durable snapshots), `csv_export.dart` (mapping/formatting). UI and
native window control are separated from timekeeping for deterministic testing.
Tests cover switching, breaks, failures, restart/sleep recovery, manual edits,
CSV formats/escaping/aggregation, midnight splitting, corrupted files and UI.

Private software. All rights reserved. No affiliation with Abacus Research AG.
