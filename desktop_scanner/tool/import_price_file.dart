// One-off importer: merges a manually-downloaded Shufersal price file
// (already-extracted XML, not gzipped) into the cached product_index.json
// that ProductIndexService normally builds from the network. Useful when a
// file was grabbed by hand for a store not covered by the weekly refresh.
//
// Self-contained (doesn't import product_index_service.dart) because that
// file pulls in path_provider -> flutter -> dart:ui, which isn't available
// under plain `dart run`. The parsing logic here must stay in sync with
// ProductIndexService.parsePriceFile.
//
// Usage: dart run tool/import_price_file.dart <path-to-PriceFull...xml> [path-to-product_index.json]
import 'dart:convert';
import 'dart:io';

import 'package:xml/xml_events.dart';

class IndexedProduct {
  IndexedProduct({required this.name, this.manufacturer, this.price});

  final String name;
  final String? manufacturer;
  final double? price;

  Map<String, dynamic> toJson() => {
        'n': name,
        if (manufacturer != null) 'm': manufacturer,
        if (price != null) 'p': price,
      };

  factory IndexedProduct.fromJson(Map<String, dynamic> json) => IndexedProduct(
        name: json['n'] as String,
        manufacturer: json['m'] as String?,
        price: (json['p'] as num?)?.toDouble(),
      );
}

Map<String, IndexedProduct> parsePriceFile(String xml) {
  final products = <String, IndexedProduct>{};

  String? currentTag;
  String? code, name, manufacturer, price;

  void flush() {
    final barcode = code?.trim();
    final productName = name?.trim();
    if (barcode != null &&
        barcode.isNotEmpty &&
        productName != null &&
        productName.isNotEmpty) {
      products[barcode] = IndexedProduct(
        name: productName,
        manufacturer:
            manufacturer?.trim().isEmpty ?? true ? null : manufacturer!.trim(),
        price: double.tryParse(price?.trim() ?? ''),
      );
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
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run tool/import_price_file.dart <price-file.xml> [product_index.json]');
    exit(1);
  }

  final xmlFile = File(args[0]);
  if (!xmlFile.existsSync()) {
    stderr.writeln('File not found: ${args[0]}');
    exit(1);
  }

  final indexFile = File(args.length > 1
      ? args[1]
      : '${Platform.environment['APPDATA']}\\HomeStock\\HomeStock Scanner\\product_index.json');

  final xml = xmlFile.readAsStringSync();
  final parsed = parsePriceFile(xml);
  if (parsed.isEmpty) {
    stderr.writeln('No products parsed from ${args[0]}');
    exit(1);
  }

  Map<String, IndexedProduct> existing = {};
  if (indexFile.existsSync()) {
    final data = jsonDecode(indexFile.readAsStringSync()) as Map<String, dynamic>;
    existing = (data['products'] as Map<String, dynamic>).map(
      (barcode, json) => MapEntry(barcode, IndexedProduct.fromJson(json as Map<String, dynamic>)),
    );
  }

  final addedCount = parsed.keys.where((k) => !existing.containsKey(k)).length;
  final updatedCount = parsed.length - addedCount;

  existing.addAll(parsed);

  indexFile.parent.createSync(recursive: true);
  indexFile.writeAsStringSync(jsonEncode({
    'updatedAt': DateTime.now().toIso8601String(),
    'products': existing.map((k, v) => MapEntry(k, v.toJson())),
  }));

  stdout.writeln('Parsed ${parsed.length} products from price file.');
  stdout.writeln('Added: $addedCount, updated: $updatedCount.');
  stdout.writeln('Index now has ${existing.length} products at ${indexFile.path}.');
}
