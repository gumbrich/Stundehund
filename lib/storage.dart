import 'dart:convert';
import 'dart:io';
import 'model.dart';

abstract class TrackerStore {
  Future<void> save(TrackerData data);
}

class FileStore implements TrackerStore {
  FileStore(this.directory);
  final Directory directory;
  RandomAccessFile? _lock;
  int _sequence = 0;

  Future<TrackerData> load() async {
    await directory.create(recursive: true);
    _lock = await File(
      '${directory.path}/stundehund.lock',
    ).open(mode: FileMode.append);
    try {
      await _lock!.lock(FileLock.exclusive);
    } catch (_) {
      throw const FileSystemException('Stundehund ist bereits geöffnet.');
    }
    final candidates = <({int sequence, TrackerData data})>[];
    var exists = false;
    var invalid = false;
    for (final slot in [0, 1]) {
      final file = File('${directory.path}/time-$slot.json');
      if (!await file.exists()) {
        continue;
      }
      exists = true;
      try {
        final json =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        candidates.add((
          sequence: json['sequence'] as int,
          data: TrackerData.fromJson(json['data'] as Map<String, dynamic>),
        ));
      } catch (_) {
        invalid = true;
      }
    }
    if (candidates.isEmpty) {
      if (exists) {
        throw const FileSystemException(
          'Die Zeitdateien können nicht gelesen werden. Sie wurden nicht überschrieben. Bitte aus einer Sicherung wiederherstellen.',
        );
      }
      return TrackerData.empty();
    }
    candidates.sort((a, b) => b.sequence.compareTo(a.sequence));
    _sequence = candidates.first.sequence;
    return invalid
        ? candidates.first.data.copy(
            notice:
                'Die letzte lesbare Sicherung wurde geladen. Bitte die letzten Einträge prüfen.',
          )
        : candidates.first.data;
  }

  @override
  Future<void> save(TrackerData data) async {
    // Alternate complete snapshots: an interrupted write never destroys both.
    final next = _sequence + 1;
    final file = File('${directory.path}/time-${next % 2}.json');
    await file.writeAsString(
      jsonEncode({'sequence': next, 'data': data.toJson()}),
      flush: true,
    );
    _sequence = next;
  }

  Future<void> close() async {
    await _lock?.unlock();
    await _lock?.close();
    _lock = null;
  }
}
