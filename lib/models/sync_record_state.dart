import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'sync_comparison.dart';

/// The existing comparison rules: trim/case-fold values, equate missing and
/// empty fields, and ignore device-local IDs and revision counters/timestamps.
/// SyncID, LearnerSyncID, DeviceID, CreatedAt and every deletion state remain.
class SyncRecordState {
  static const _ignored = {
    'LearnerID',
    'TeacherID',
    'SectionID',
    'SchoolHistoryID',
    'IncidentID',
    'Version',
    'UpdatedAt',
  };

  static String fingerprint(Map<String, Object?> row) {
    final values = <String, String>{};
    for (final entry in row.entries) {
      if (_ignored.contains(entry.key)) continue;
      final value = entry.value?.toString().trim().toLowerCase() ?? '';
      if (value.isNotEmpty) values[entry.key] = value;
    }
    final keys = values.keys.toList()..sort();
    return 'v1:${sha256.convert(utf8.encode(jsonEncode({
          for (final key in keys) key: values[key],
        })))}';
  }

  static bool same(Map<String, Object?>? a, Map<String, Object?>? b) =>
      a == null || b == null
          ? a == null && b == null
          : fingerprint(a) == fingerprint(b);

  static SyncComparisonStatus compare({
    required Map<String, Object?>? local,
    required Map<String, Object?>? remote,
    required Map<String, Object?>? baseline,
  }) {
    if (local == null) {
      return remote == null
          ? SyncComparisonStatus.same
          : SyncComparisonStatus.newRemote;
    }
    // A previously synchronized row disappearing remotely is not a new local
    // record. Preserve it for review rather than silently resurrecting it.
    if (remote == null) {
      return baseline == null
          ? SyncComparisonStatus.localOnly
          : SyncComparisonStatus.conflict;
    }
    if (same(local, remote)) return SyncComparisonStatus.same;
    final fingerprint = baseline?['SyncedFingerprint'];
    if (fingerprint is! String ||
        !RegExp(r'^v1:[a-f0-9]{64}$').hasMatch(fingerprint)) {
      return SyncComparisonStatus.conflict;
    }
    final localChanged = SyncRecordState.fingerprint(local) != fingerprint;
    final remoteChanged = SyncRecordState.fingerprint(remote) != fingerprint;
    if (!remoteChanged && localChanged) return SyncComparisonStatus.localNewer;
    if (!localChanged && remoteChanged) return SyncComparisonStatus.remoteNewer;
    return SyncComparisonStatus.conflict;
  }
}

class RemoteRecordChanged implements Exception {
  const RemoteRecordChanged();
  @override
  String toString() =>
      'Remote record changed before upload; conflict review required.';
}
