class SyncApplyResult {
  const SyncApplyResult({
    required this.success,
    required this.message,
    required this.learnersInserted,
    required this.learnersUpdated,
    required this.learnersDeleted,
    required this.teachersInserted,
    required this.teachersUpdated,
    required this.teachersDeleted,
    required this.sectionsInserted,
    required this.sectionsUpdated,
    required this.sectionsDeleted,
    required this.schoolHistoryInserted,
    required this.schoolHistoryUpdated,
    required this.schoolHistoryDeleted,
    required this.incidentsInserted,
    required this.incidentsUpdated,
    required this.incidentsDeleted,
    required this.skipped,
    required this.conflicts,
  });

  final bool success;

  final String message;

  final int learnersInserted;
  final int learnersUpdated;
  final int learnersDeleted;

  final int teachersInserted;
  final int teachersUpdated;
  final int teachersDeleted;

  final int sectionsInserted;
  final int sectionsUpdated;
  final int sectionsDeleted;

  final int schoolHistoryInserted;
  final int schoolHistoryUpdated;
  final int schoolHistoryDeleted;

  final int incidentsInserted;
  final int incidentsUpdated;
  final int incidentsDeleted;

  final int skipped;

  final int conflicts;

  int get inserted =>
      learnersInserted +
      teachersInserted +
      sectionsInserted +
      schoolHistoryInserted +
      incidentsInserted;

  int get updated =>
      learnersUpdated +
      teachersUpdated +
      sectionsUpdated +
      schoolHistoryUpdated +
      incidentsUpdated;

  int get deleted =>
      learnersDeleted +
      teachersDeleted +
      sectionsDeleted +
      schoolHistoryDeleted +
      incidentsDeleted;
}