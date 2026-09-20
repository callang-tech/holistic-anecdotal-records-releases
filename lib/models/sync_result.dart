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
  });

  final bool success;

  final String message;

  final int learners;

  final int teachers;

  final int sections;

  final int schoolHistory;

  final int incidents;

  final int totalPending;
}