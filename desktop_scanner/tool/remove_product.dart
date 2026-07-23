// Removes a single barcode from the cached product_index.json.
//
// Usage: dart run tool/remove_product.dart <barcode>
import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run tool/remove_product.dart <barcode>');
    exit(1);
  }

  final barcode = args[0];
  final indexFile = File('${Platform.environment['APPDATA']}\\HomeStock\\HomeStock Scanner\\product_index.json');

  if (!indexFile.existsSync()) {
    stderr.writeln('No index file at ${indexFile.path}');
    exit(1);
  }

  final data = jsonDecode(indexFile.readAsStringSync()) as Map<String, dynamic>;
  final products = data['products'] as Map<String, dynamic>;

  if (!products.containsKey(barcode)) {
    stdout.writeln('$barcode is not in the index — nothing to remove.');
    return;
  }

  final removed = products.remove(barcode);
  indexFile.writeAsStringSync(jsonEncode({
    'updatedAt': DateTime.now().toIso8601String(),
    'products': products,
  }));

  stdout.writeln('Removed $barcode ($removed). Index now has ${products.length} products.');
}
