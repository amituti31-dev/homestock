// Regenerates a bundled per-chain seed asset from a price file. The app
// bundles one of these per chain instead of downloading live — some machines
// fail TLS verification against arbitrary external hosts — so every chain's
// data has to ship inside the app itself. See CLAUDE.md "Bundled chain seeds".
//
// Usage: dart run tool/generate_price_asset.dart <PriceFull...xml> <output-name>
// e.g.:  dart run tool/generate_price_asset.dart Barcods/יוחננוף/PriceFull....xml yohananof
import 'dart:convert';
import 'dart:io';

import 'package:xml/xml_events.dart';

Map<String, Map<String, dynamic>> _parsePriceFile(String xml) {
  final products = <String, Map<String, dynamic>>{};
  String? currentTag;
  String? code, name, manufacturer, price;

  void flush() {
    final barcode = code?.trim();
    final productName = name?.trim();
    if (barcode != null &&
        barcode.isNotEmpty &&
        productName != null &&
        productName.isNotEmpty) {
      final trimmedManufacturer = manufacturer?.trim();
      final parsedPrice = double.tryParse(price?.trim() ?? '');
      products[barcode] = {
        'n': productName,
        if (trimmedManufacturer != null && trimmedManufacturer.isNotEmpty)
          'm': trimmedManufacturer,
        if (parsedPrice != null) 'p': parsedPrice,
      };
    }
    code = name = manufacturer = price = null;
  }

  for (final event in parseEvents(xml)) {
    if (event is XmlStartElementEvent) {
      currentTag = event.name;
    } else if (event is XmlTextEvent && currentTag != null) {
      switch (currentTag) {
        case 'ItemCode':
          code = event.value;
        case 'ItemName':
          name = event.value;
        case 'ManufacturerName':
          manufacturer = event.value;
        case 'ItemPrice':
          price = event.value;
      }
    } else if (event is XmlEndElementEvent) {
      if (event.name == 'Item') flush();
      currentTag = null;
    }
  }
  return products;
}

void main(List<String> args) {
  if (args.length < 2) {
    stderr.writeln('Usage: dart run tool/generate_price_asset.dart <price-file.xml> <output-name>');
    exit(1);
  }

  final xml = File(args[0]).readAsStringSync();
  final products = _parsePriceFile(xml);
  if (products.isEmpty) {
    stderr.writeln('No products parsed from ${args[0]}');
    exit(1);
  }

  final outFile = File('assets/${args[1]}_seed.json');
  outFile.parent.createSync(recursive: true);
  outFile.writeAsStringSync(jsonEncode({
    'generatedAt': DateTime.now().toIso8601String(),
    'products': products,
  }));

  stdout.writeln('Wrote ${products.length} products to ${outFile.path}');
}
