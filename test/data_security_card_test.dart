import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:holistic_anecdotal_records/services/dataset_key_service.dart';
import 'package:holistic_anecdotal_records/services/sync_context_service.dart';
import 'package:holistic_anecdotal_records/widgets/data_security_card.dart';
import 'support/encrypted_sheets_fixture.dart';

// UI tests exercise entry/confirmation without running PBKDF2 in fake async.
// Real derivation and cross-device interoperability are covered separately.
class _UiKeyService extends DatasetKeyService {
  _UiKeyService(MemoryKeyStore store)
      : super(
            store: store,
            context: SyncContextService(
                database: () => throw StateError('No database permitted')));
  @override
  Future<void> setUpWithPassphrase(String passphrase,
          {bool replaceExisting = false}) =>
      super.setUp();
}

void main() {
  late MemoryKeyStore store;
  late DatasetKeyService service;
  setUp(() {
    store = MemoryKeyStore();
  });
  Future<void> mount(WidgetTester tester) async {
    // Create the operation guard in the widget test's fake-async zone.
    service = _UiKeyService(store);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: DataSecurityCard(service: service)))));
    await tester.pumpAndSettle();
  }

  testWidgets('setup cancellation, confirmation, status and no secret shown',
      (tester) async {
    await mount(tester);
    expect(find.text('Encryption: Not Configured'), findsOneWidget);
    await tester.tap(find.text('Set Up Encryption'));
    // The busy indicator keeps animating while confirmation is open.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(store.value, isNull);
    await tester.tap(find.text('Set Up Encryption'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Cloud Encryption Passphrase'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), 'short');
    await tester.enterText(find.byType(TextField).at(1), 'different');
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(store.value, isNull);
    expect(find.text('Check the password length and confirmation.'),
        findsOneWidget);
    await tester.enterText(
        find.byType(TextField).at(0), 'Synthetic cloud phrase 123!');
    await tester.enterText(
        find.byType(TextField).at(1), 'Synthetic cloud phrase 123!');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Encryption: Configured'), findsOneWidget);
    expect(store.writes, 1);
    expect(find.textContaining((await service.requireKey()).id), findsNothing);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Set Up Encryption'))
            .onPressed,
        isNull);
  });
  testWidgets('secure storage failure disables secret operations safely',
      (tester) async {
    store.failRead = true;
    await mount(tester);
    expect(find.textContaining('Cloud synchronization is blocked.'),
        findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Set Up Encryption'))
            .onPressed,
        isNull);
    expect(store.writes, 0);
  });
}
