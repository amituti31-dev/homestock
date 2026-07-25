// Removes a single barcode. By default from the local cache; --bundle
// instead removes it from assets/manual_additions_seed.json.
//
// Usage: dart run tool/remove_product.dart [--bundle] <barcode>
import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  final bundle = args.contains('--bundle');
  final positional = args.where((a) => a != '--bundle').toList();

  if (positional.isEmpty) {
    stderr.writeln('Usage: dart run tool/remove_product.dart [--bundle] <barcode>');
    exit(1);
  }

  final barcode = positional[0];
  final targetFile = bundle
      ? File('assets/manual_additions_seed.json')
      : File('${Platform.environment['APPDATA']}\\HomeStock\\HomeStock Scanner\\product_index.json');

  if (!targetFile.existsSync()) {
    stderr.writeln('No file at ${targetFile.path}');
    exit(1);
  }

  final data = jsonDecode(targetFile.readAsStringSync()) as Map<String, dynamic>;
  final products = data['products'] as Map<String, dynamic>;

  if (!products.containsKey(barcode)) {
    stdout.writeln('$barcode is not in ${targetFile.path} — nothing to remove.');
    return;
  }

  final removed = products.remove(barcode);
  targetFile.writeAsStringSync(jsonEncode({
    if (!bundle) 'updatedAt': DateTime.now().toIso8601String(),
    'products': products,
  }));

  stdout.writeln('Removed $barcode ($removed) from ${targetFile.path}. '
      'Now has ${products.length} products.');
}
