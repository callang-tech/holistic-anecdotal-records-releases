/// UI-owned navigation guard. Services report conflicts; widgets decide how
/// to present the existing review UI and refresh after it closes.
class ConflictReviewNavigation {
  bool _opening = false;

  Future<void> show({
    required int conflictCount,
    required bool Function() mounted,
    required Future<void> Function() open,
    required Future<void> Function() refresh,
  }) async {
    if (conflictCount <= 0 || !mounted() || _opening) return;
    _opening = true;
    try {
      await open();
      if (mounted()) await refresh();
    } finally {
      _opening = false;
    }
  }
}
