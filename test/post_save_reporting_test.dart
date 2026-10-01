import 'package:flutter_test/flutter_test.dart';
import 'package:holistic_anecdotal_records/models/sync_result.dart';
import 'package:holistic_anecdotal_records/services/post_save_sync.dart';

void main() {
  for (final success in [false, true]) {
    for (final pending in [0, 1]) {
      for (final remoteApply in [false, true]) {
        test('success=$success pending=$pending remoteApply=$remoteApply',
            () async {
          final message = await attemptPostSaveUpload(() async => SyncResult(
                success: success,
                totalPending: pending,
                requiresRemoteApply: remoteApply,
                message: 'Service detail',
                learners: pending,
                teachers: 0,
                sections: 0,
                schoolHistory: 0,
                incidents: 0,
              ));
          if (success && pending == 0 && !remoteApply) {
            expect(message, 'Saved and synchronized.');
          } else {
            expect(message,
                'Saved locally; synchronization pending. Service detail');
          }
        });
      }
    }
  }

  for (final detail in [
    'Saved locally; conflict review required. Conflicts: 1. Pending: 1.',
    'Remote changes require Download/Apply. Local changes are preserved. Pending: 1.',
    'Please sign in with Google first.',
    'Google Sheets synchronization failed. Network unavailable.',
  ]) {
    test('preserves service diagnosis: $detail', () async {
      final message = await attemptPostSaveUpload(() async => SyncResult(
            success: false,
            totalPending: 1,
            message: detail,
            learners: 1,
            teachers: 0,
            sections: 0,
            schoolHistory: 0,
            incidents: 0,
          ));
      expect(message, 'Saved locally; synchronization pending. $detail');
      expect(message, isNot(contains('Saved and synchronized.')));
    });
  }
}
