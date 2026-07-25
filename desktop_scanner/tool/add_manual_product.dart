// Adds a single hand-entered barcode -> product mapping, for barcodes that
// don't appear in any chain's price file (e.g. told to us directly by the
// user rather than scanned from a catalogue). By default this only touches
// this machine's local cache; --bundle instead writes to
// assets/manual_additions_seed.json, which ships with the app and so
// reaches every install once rebuilt and released — see CLAUDE.md.
//
// Usage: dart run tool/add_manual_product.dart [--bundle] <barcode> <name> [manufacturer] [price]
import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  final bundle = args.contains('--bundle');
  final positional = args.where((a) => a != '--bundle').toList();

  if (positional.length < 2) {
    stderr.writeln('Usage: dart run tool/add_manual_product.dart [--bundle] <barcode> <name> [manufacturer] [price]');
    exit(1);
  }

  final barcode = positional[0];
  final name = positional[1];
  final manufacturer = positional.length > 2 && positional[2].isNotEmpty ? positional[2] : null;
  final price = positional.length > 3 ? double.tryParse(positional[3]) : null;

  final targetFile = bundle
      ? File('assets/manual_additions_seed.json')
      : File('${Platform.environment['APPDATA']}\\HomeStock\\HomeStock Scanner\\product_index.json');

  Map<String, dynamic> products = {};
  if (targetFile.existsSync()) {
    final data = jsonDecode(targetFile.readAsStringSync()) as Map<String, dynamic>;
    products = data['products'] as Map<String, dynamic>;
  }

  products[barcode] = {
    'n': name,
    if (manufacturer != null) 'm': manufacturer,
    if (price != null) 'p': price,
  };

  final encoded = jsonEncode({
    if (!bundle) 'updatedAt': DateTime.now().toIso8601String(),
    'products': products,
  });

  // Verify the round-trip before writing — a Hebrew name mangled by argument
  // encoding should fail loudly here, not silently corrupt the file.
  final reparsed = (jsonDecode(encoded) as Map<String, dynamic>)['products']
      as Map<String, dynamic>;
  if (reparsed[barcode]?['n'] != name) {
    stderr.writeln('Round-trip mismatch for "$name" — not writing. '
        'Try passing the name via a script with the Hebrew text as a string '
        'literal instead of a command-line argument.');
    exit(1);
  }

  targetFile.parent.createSync(recursive: true);
  targetFile.writeAsStringSync(encoded);

  stdout.writeln('Added $barcode -> $name to ${targetFile.path}. '
      'Now has ${products.length} products.');
}
