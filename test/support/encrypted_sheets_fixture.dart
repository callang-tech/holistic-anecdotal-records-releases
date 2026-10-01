import 'package:googleapis/sheets/v4.dart' as api;
import 'package:holistic_anecdotal_records/services/dataset_key_service.dart';
import 'package:holistic_anecdotal_records/services/google_sheets_service.dart';
import 'package:holistic_anecdotal_records/services/sheets_encryption_codec.dart';
import 'package:holistic_anecdotal_records/services/sync_context_service.dart';

class MemoryKeyStore implements DatasetKeyStore {
  String? value;
  bool failRead = false, failWrite = false;
  int writes = 0;
  @override
  Future<String?> read() async {
    if (failRead) throw StateError('synthetic secure-store read failure');
    return value;
  }

  @override
  Future<void> write(String data) async {
    if (failWrite) throw StateError('synthetic secure-store write failure');
    value = data;
    writes++;
  }
}

/// Only transport and target validation are mocked. All production downloads,
/// serializers, encryption, and the upsert reread execute unchanged.
class EncryptedMemorySheets extends GoogleSheetsService {
  EncryptedMemorySheets(this.context, this.codec)
      : super.forTesting(codec: codec);
  final SyncContextService context;
  final SheetsEncryptionCodec codec;
  static const headers = {
    'LEARNERS': GoogleSheetsService.learnerHeaders,
    'TEACHERS': GoogleSheetsService.teacherHeaders,
    'SECTIONS': GoogleSheetsService.sectionHeaders,
    'SCHOOL_HISTORY': GoogleSheetsService.schoolHistoryHeaders,
    'INCIDENTS': GoogleSheetsService.incidentHeaders,
  };
  final records = <String, List<Map<String, Object?>>>{
    for (final table in headers.keys) table: [],
  };
  String? activeId;
  int writes = 0;
  bool failWrites = false;
  Future<void> Function(String)? beforeRead;
  @override
  String? get spreadsheetId => activeId;
  @override
  Future<void> initialize() async {
    activeId = await context.activeSpreadsheetId();
  }

  @override
  Future<api.Spreadsheet> validateSpreadsheet(String input) async =>
      api.Spreadsheet(spreadsheetId: input);
  @override
  Future<List<List<Object?>>> readRange(
      {required String sheetTitle,
      String range = 'A:ZZ',
      String? spreadsheetId}) async {
    await beforeRead?.call(sheetTitle);
    return [
      headers[sheetTitle]!,
      for (final record in records[sheetTitle]!)
        [for (final column in headers[sheetTitle]!) record[column]]
    ];
  }

  @override
  Future<void> updateRange(
      {required String sheetTitle,
      required String range,
      required List<List<Object?>> values}) async {
    if (failWrites) throw StateError('synthetic transport failure');
    final index =
        int.parse(RegExp(r'^A(\d+)').firstMatch(range)!.group(1)!) - 2;
    records[sheetTitle]![index] = {
      for (var i = 0; i < headers[sheetTitle]!.length; i++)
        headers[sheetTitle]![i]: values.single[i]
    };
    writes++;
  }

  @override
  Future<void> appendRows(
      {required String sheetTitle, required List<List<Object?>> rows}) async {
    if (failWrites) throw StateError('synthetic transport failure');
    for (final row in rows) {
      records[sheetTitle]!.add({
        for (var i = 0; i < headers[sheetTitle]!.length; i++)
          headers[sheetTitle]![i]: row[i]
      });
      writes++;
    }
  }

  Future<Map<String, Object?>> logical(String table) =>
      codec.decode(table, records[table]!.single);
  Future<void> edit(String table, Map<String, Object?> fields) async {
    records[table] = [
      await codec.encode(table, {...await logical(table), ...fields})
    ];
  }
}
