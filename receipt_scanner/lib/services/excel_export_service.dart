import 'dart:io';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/inventory_item.dart';

class ExcelExportService {
  Future<void> exportAndShare(List<InventoryItem> items) async {
    final excel = Excel.createExcel();
    final sheet = excel[excel.getDefaultSheet()!];

    const headers = [
      'שם המוצר',
      'קטגוריה',
      'כמות',
      'יחידה',
      'כמות מינימלית',
      'תאריך תפוגה',
      'מחיר',
      'ברקוד',
    ];
    sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());

    for (final item in items) {
      sheet.appendRow([
        TextCellValue(item.name),
        TextCellValue(item.category.label),
        DoubleCellValue(item.quantity),
        TextCellValue(item.unit),
        DoubleCellValue(item.minQuantity),
        TextCellValue(item.expiryDate != null
            ? DateFormat('dd/MM/yyyy').format(item.expiryDate!)
            : ''),
        item.price != null ? DoubleCellValue(item.price!) : TextCellValue(''),
        TextCellValue(item.barcode ?? ''),
      ]);
    }

    final bytes = excel.save();
    if (bytes == null) throw Exception('יצירת קובץ ה-Excel נכשלה');

    final dir = await getTemporaryDirectory();
    final fileName =
        'מלאי_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.xlsx';
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);

    await Share.shareXFiles([XFile(file.path)], text: 'גיבוי מלאי HomeStock');
  }
}
