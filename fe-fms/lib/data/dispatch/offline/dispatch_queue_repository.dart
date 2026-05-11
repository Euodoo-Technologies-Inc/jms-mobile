import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _prefsKey = 'dispatch.queue.entries';

/// Discriminator for queued op types.
enum DispatchQueueOpType { start, finish, fcm }

/// A single persisted operation. Photo files for `finish` ops are copied
/// into the app's documents directory so they survive temp-dir cleanup.
class DispatchQueueEntry {
  DispatchQueueEntry({
    required this.id,
    required this.type,
    required this.enqueuedAt,
    this.jobId,
    this.notes,
    this.photoPaths = const [],
    this.fcmToken,
  });

  final String id; // monotonically increasing index, used to dedupe drains
  final DispatchQueueOpType type;
  final DateTime enqueuedAt;
  final int? jobId;
  final String? notes;
  final List<String> photoPaths;
  final String? fcmToken;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'enqueuedAt': enqueuedAt.toIso8601String(),
        if (jobId != null) 'jobId': jobId,
        if (notes != null) 'notes': notes,
        if (photoPaths.isNotEmpty) 'photoPaths': photoPaths,
        if (fcmToken != null) 'fcmToken': fcmToken,
      };

  factory DispatchQueueEntry.fromJson(Map<String, dynamic> json) {
    return DispatchQueueEntry(
      id: json['id']?.toString() ?? '',
      type: DispatchQueueOpType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => DispatchQueueOpType.start,
      ),
      enqueuedAt:
          DateTime.tryParse(json['enqueuedAt']?.toString() ?? '') ??
              DateTime.now(),
      jobId: (json['jobId'] as num?)?.toInt(),
      notes: json['notes']?.toString(),
      photoPaths: ((json['photoPaths'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(growable: false),
      fcmToken: json['fcmToken']?.toString(),
    );
  }
}

/// Persistent FIFO queue of dispatch operations that failed to reach the
/// server (network/5xx). Drained by [DispatchSyncService] on reconnect.
///
/// Photo files are copied to `<documents>/dispatch_queue_photos/` on enqueue;
/// the copies are deleted on dequeue.
class DispatchQueueRepository {
  static int _counter = 0;

  static Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  Future<Directory> _photoDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'dispatch_queue_photos'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  String _nextId() {
    _counter++;
    return '${DateTime.now().microsecondsSinceEpoch}-$_counter';
  }

  Future<List<DispatchQueueEntry>> readAll() async {
    final prefs = await _prefs();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is List) {
        return list
            .whereType<Map<String, dynamic>>()
            .map(DispatchQueueEntry.fromJson)
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  Future<void> _writeAll(List<DispatchQueueEntry> entries) async {
    final prefs = await _prefs();
    await prefs.setString(
      _prefsKey,
      jsonEncode(entries.map((e) => e.toJson()).toList()),
    );
  }

  /// Enqueues a start operation. Idempotency key is already persisted by
  /// the controller via [DispatchIdempotencyStore].
  Future<DispatchQueueEntry> enqueueStart(int jobId) async {
    final entry = DispatchQueueEntry(
      id: _nextId(),
      type: DispatchQueueOpType.start,
      enqueuedAt: DateTime.now(),
      jobId: jobId,
    );
    final all = await readAll();
    all.add(entry);
    await _writeAll(all);
    return entry;
  }

  /// Enqueues a finish operation. Photos are copied into the queue's
  /// persistent directory so picker temp-files cleanup doesn't drop them.
  Future<DispatchQueueEntry> enqueueFinish(
    int jobId, {
    String? notes,
    List<File> photos = const [],
  }) async {
    final dir = await _photoDir();
    final copies = <String>[];
    final stamp = DateTime.now().microsecondsSinceEpoch;
    for (var i = 0; i < photos.length; i++) {
      final src = photos[i];
      final ext = p.extension(src.path).isNotEmpty
          ? p.extension(src.path)
          : '.jpg';
      final dest = File(p.join(dir.path, 'job_${jobId}_${stamp}_$i$ext'));
      try {
        await src.copy(dest.path);
        copies.add(dest.path);
      } catch (_) {
        // Skip unreadable files; surface at drain time.
      }
    }
    final entry = DispatchQueueEntry(
      id: _nextId(),
      type: DispatchQueueOpType.finish,
      enqueuedAt: DateTime.now(),
      jobId: jobId,
      notes: notes,
      photoPaths: copies,
    );
    final all = await readAll();
    all.add(entry);
    await _writeAll(all);
    return entry;
  }

  /// Enqueues an FCM token refresh. Only the **latest** token is kept; any
  /// older queued FCM entries are removed (coalesce per docs §8.2).
  Future<DispatchQueueEntry> enqueueFcmRefresh(String fcmToken) async {
    final all = await readAll();
    all.removeWhere((e) => e.type == DispatchQueueOpType.fcm);
    final entry = DispatchQueueEntry(
      id: _nextId(),
      type: DispatchQueueOpType.fcm,
      enqueuedAt: DateTime.now(),
      fcmToken: fcmToken,
    );
    all.add(entry);
    await _writeAll(all);
    return entry;
  }

  /// Removes the entry with matching id and cleans up any photo copies.
  Future<void> remove(String id) async {
    final all = await readAll();
    final idx = all.indexWhere((e) => e.id == id);
    if (idx < 0) return;
    final entry = all[idx];
    for (final path in entry.photoPaths) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    all.removeAt(idx);
    await _writeAll(all);
  }

  /// Wipes the queue + all photo copies. Called on logout / 401.
  Future<void> wipe() async {
    final prefs = await _prefs();
    await prefs.remove(_prefsKey);
    try {
      final dir = await _photoDir();
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {}
  }

  Future<bool> get isEmpty async => (await readAll()).isEmpty;
}
