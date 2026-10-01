import '../models/sync_result.dart';

/// Called only after the local write succeeds. Never applies remote data and
/// never lets an upload failure turn a successful save into a failed save.
Future<String> attemptPostSaveUpload(
  Future<SyncResult> Function() upload, {
  Duration waitLimit = const Duration(seconds: 10),
  void Function(SyncResult result)? onCompleted,
}) async {
  Future<String> attempt() async {
    try {
      final result = await upload();
      onCompleted?.call(result);
      if (result.success &&
          result.totalPending == 0 &&
          !result.requiresRemoteApply) {
        return 'Saved and synchronized.';
      }
      // Preserve the service's conflict / remote-apply diagnosis verbatim.
      return 'Saved locally; synchronization pending. ${result.message}';
    } catch (_) {
      return 'Saved locally; synchronization unavailable or failed. '
          'Check Sync for pending changes and retry.';
    }
  }

  return attempt().timeout(waitLimit,
      onTimeout: () =>
          'Saved locally. Synchronization has not finished and may still be running. '
          'The wait timed out; synchronization was not cancelled. '
          'Check Sync for the final status.');
}
