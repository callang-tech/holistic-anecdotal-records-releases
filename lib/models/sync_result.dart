class SyncResult {
  const SyncResult({
    required this.success,
    required this.message,
    required this.learners,
    required this.teachers,
    required this.sections,
    required this.schoolHistory,
    required this.incidents,
    required this.totalPending,
    this.requiresRemoteApply = false,
  });

  final bool success;

  /// Upload callers must not report full success yet, but the combined Sync
  /// action can continue through its existing safe Download/Apply step.
  final bool requiresRemoteApply;

  final String message;

  final int learners;

  final int teachers;

  final int sections;

  final int schoolHistory;

  final int incidents;

  final int totalPending;
}
