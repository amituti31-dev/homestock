// Adds a single hand-entered barcode -> product mapping to the cached
// product_index.json, for barcodes that don't appear in any chain's price
// file (e.g. told to us directly by the user rather than scanned from a
// catalogue).
//
// Usage: dart run tool/add_manual_product.dart <barcode> <name> [manufacturer] [price]
import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  if (args.length < 2) {
    stderr.writeln('Usage: dart run tool/add_manual_product.dart <barcode> <name> [manufacturer] [price]');
    exit(1);
  }

  final barcode = args[0];
  final name = args[1];
  final manufacturer = args.length > 2 && args[2].isNotEmpty ? args[2] : null;
  final price = args.length > 3 ? double.tryParse(args[3]) : null;

  final indexFile = File('${Platform.environment['APPDATA']}\\HomeStock\\HomeStock Scanner\\product_index.json');

  Map<String, dynamic> products = {};
  if (indexFile.existsSync()) {
    final data = jsonDecode(indexFile.readAsStringSync()) as Map<String, dynamic>;
    products = data['products'] as Map<String, dynamic>;
  }

  products[barcode] = {
    'n': name,
    if (manufacturer != null) 'm': manufacturer,
    if (price != null) 'p': price,
  };

  indexFile.parent.createSync(recursive: true);
  indexFile.writeAsStringSync(jsonEncode({
    'updatedAt': DateTime.now().toIso8601String(),
    'products': products,
  }));

  stdout.writeln('Added $barcode -> $name. Index now has ${products.length} products.');
}
