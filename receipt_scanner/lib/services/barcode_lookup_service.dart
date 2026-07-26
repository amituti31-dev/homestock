import 'dart:convert';

import 'package:http/http.dart' as http;

class BarcodeProduct {
  final String name;
  final String? imageUrl;
  final String? brand;
  final String? quantityText;

  BarcodeProduct({
    required this.name,
    this.imageUrl,
    this.brand,
    this.quantityText,
  });

  /// Brand and product name read better together on the confirmation card, but
  /// only when the name doesn't already start with the brand.
  String get displayName {
    if (brand == null || brand!.isEmpty) return name;
    if (name.toLowerCase().startsWith(brand!.toLowerCase())) return name;
    return '$brand $name';
  }
}

/// Product lookup against Open Food Facts.
///
/// Best-effort by design: any failure returns null and the caller falls back
/// to letting the user type the name (or to the local price index — see
/// ProductResolver). Open Food Facts asks clients to identify themselves via
/// User-Agent. Duplicated from desktop_scanner's copy — see its CLAUDE.md
/// note on why models/services are duplicated rather than shared.
class BarcodeLookupService {
  static const _userAgent =
      'HomeStock-MobileScanner/1.0 (https://github.com/homestock)';

  Future<BarcodeProduct?> lookup(String barcode) async {
    try {
      final response = await http.get(
        Uri.parse('https://world.openfoodfacts.org/api/v2/product/$barcode.json'),
        headers: {'User-Agent': _userAgent},
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body);
      if (data['status'] != 1) return null;

      final product = data['product'] as Map<String, dynamic>;

      // Israeli products are often catalogued with a Hebrew name only, so
      // prefer that before falling back to the generic name.
      final name = _firstNonEmpty([
        product['product_name_he'],
        product['product_name'],
        product['generic_name_he'],
        product['generic_name'],
      ]);
      if (name == null) return null;

      return BarcodeProduct(
        name: name,
        imageUrl: _firstNonEmpty([
          product['image_front_url'],
          product['image_front_small_url'],
          product['image_url'],
        ]),
        brand: _firstNonEmpty([product['brands']])?.split(',').first.trim(),
        quantityText: _firstNonEmpty([product['quantity']]),
      );
    } catch (_) {
      return null;
    }
  }

  static String? _firstNonEmpty(List<dynamic> candidates) {
    for (final candidate in candidates) {
      if (candidate is String && candidate.trim().isNotEmpty) {
        return candidate.trim();
      }
    }
    return null;
  }
}
