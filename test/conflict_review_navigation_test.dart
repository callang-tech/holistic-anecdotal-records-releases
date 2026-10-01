import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holistic_anecdotal_records/models/sync_result.dart';
import 'package:holistic_anecdotal_records/services/post_save_sync.dart';
import 'package:holistic_anecdotal_records/widgets/conflict_review_navigation.dart';

SyncResult conflictResult() => const SyncResult(
      success: false,
      conflictCount: 1,
      message: 'conflict review required',
      learners: 1,
      teachers: 0,
      sections: 0,
      schoolHistory: 0,
      incidents: 0,
      totalPending: 1,
    );

void main() {
  testWidgets('post-save conflict opens once and returning refreshes state',
      (tester) async {
    final guard = ConflictReviewNavigation();
    var refreshes = 0;
    var opens = 0;
    late BuildContext origin;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      origin = context;
      return const Scaffold(body: Text('Learner'));
    })));
    Future<void> request(int count) => guard.show(
          conflictCount: count,
          mounted: () => origin.mounted,
          open: () async {
            opens++;
            await Navigator.of(origin).push(MaterialPageRoute<void>(
                builder: (_) =>
                    const Scaffold(body: Text('Existing conflict review'))));
          },
          refresh: () async {
            refreshes++;
          },
        );
    await attemptPostSaveUpload(() async => conflictResult(),
        onCompleted: (result) {
      request(result.conflictCount);
    });
    await tester.pumpAndSettle();
    expect(find.text('Existing conflict review'), findsOneWidget);
    await request(1);
    expect(opens, 1);
    expect(refreshes, 0);
    Navigator.of(origin).pop();
    await tester.pumpAndSettle();
    expect(refreshes, 1);
    expect(find.text('Learner'), findsOneWidget);
  });

  test('zero conflicts or disposed origin never opens review', () async {
    final guard = ConflictReviewNavigation();
    var opens = 0;
    for (final count in [0, 1]) {
      await guard.show(
          conflictCount: count,
          mounted: () => count == 0,
          open: () async {
            opens++;
          },
          refresh: () async {
            fail('Unexpected refresh');
          });
    }
    expect(opens, 0);
  });

  test('disposed origin is not refreshed when review closes', () async {
    final guard = ConflictReviewNavigation();
    final closed = Completer<void>();
    var alive = true;
    final request = guard.show(
        conflictCount: 1,
        mounted: () => alive,
        open: () => closed.future,
        refresh: () async {
          fail('Disposed refresh');
        });
    alive = false;
    closed.complete();
    await request;
  });

  test('late post-save completion reports conflict once after timeout',
      () async {
    final result = Completer<SyncResult>();
    var requests = 0;
    final message = await attemptPostSaveUpload(() => result.future,
        waitLimit: Duration.zero, onCompleted: (value) {
      requests += value.conflictCount;
    });
    expect(message, contains('was not cancelled'));
    expect(requests, 0);
    result.complete(conflictResult());
    await Future<void>.delayed(Duration.zero);
    expect(requests, 1);
  });

  test('Sync Now and Download/Apply reveal existing conflict review', () {
    final source = File('lib/screens/sync_screen.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    expect(source,
        contains('await _reviewDetectedConflicts(uploadResult.conflictCount)'));
    expect(source,
        contains('await _revealConflictReview(finalComparison.conflictCount)'));
    expect(
        source, contains('await _reviewDetectedConflicts(result.conflicts)'));
    expect(source, contains('Scrollable.ensureVisible(target'));
  });

  test('Sync to Cloud handles upload conflicts before its early return', () {
    final source = File('lib/widgets/sync_status_bar.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    expect(
        source,
        contains(
            'await _openConflictReview(uploadResult.conflictCount);\n        return;'));
    expect(
        source, contains('await _openConflictReview(applyResult.conflicts)'));
    expect(source, contains('refresh: _load'));
    expect(source, contains('SyncScreen(focusConflicts: true)'));
  });
}
