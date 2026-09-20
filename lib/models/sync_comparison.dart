enum SyncComparisonStatus {
  newRemote,
  localOnly,
  remoteNewer,
  localNewer,
  same,
  conflict,
}

class SyncComparison {
  const SyncComparison({
    required this.tableName,
    required this.syncId,
    required this.status,
    required this.localRecord,
    required this.remoteRecord,
  });

  final String tableName;

  final String syncId;

  final SyncComparisonStatus status;

  final Map<String, Object?>? localRecord;

  final Map<String, Object?>? remoteRecord;
}

class SyncComparisonResult {
  const SyncComparisonResult({
    required this.comparisons,
  });

  final List<SyncComparison> comparisons;

  int get newRemoteCount =>
      comparisons
          .where(
            (item) =>
                item.status ==
                SyncComparisonStatus.newRemote,
          )
          .length;

  int get localOnlyCount =>
      comparisons
          .where(
            (item) =>
                item.status ==
                SyncComparisonStatus.localOnly,
          )
          .length;

  int get remoteNewerCount =>
      comparisons
          .where(
            (item) =>
                item.status ==
                SyncComparisonStatus.remoteNewer,
          )
          .length;

  int get localNewerCount =>
      comparisons
          .where(
            (item) =>
                item.status ==
                SyncComparisonStatus.localNewer,
          )
          .length;

  int get sameCount =>
      comparisons
          .where(
            (item) =>
                item.status ==
                SyncComparisonStatus.same,
          )
          .length;

  int get conflictCount =>
      comparisons
          .where(
            (item) =>
                item.status ==
                SyncComparisonStatus.conflict,
          )
          .length;

  int get total =>
      comparisons.length;
}