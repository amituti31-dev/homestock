import 'dart:convert';
import 'package:http/http.dart' as http;

class BarcodeProduct {
  final String name;
  final String? imageUrl;

  BarcodeProduct({required this.name, this.imageUrl});
}

class BarcodeLookupService {
  Future<BarcodeProduct?> lookup(String barcode) async {
    try {
      final response = await http
          .get(Uri.parse(
              'https://world.openfoodfacts.org/api/v2/product/$barcode.json'))
          .timeout(const Duration(seconds: 6));

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body);
      if (data['status'] != 1) return null;

      final product = data['product'];
      final name = product['product_name'] ?? product['product_name_he'];
      if (name == null || (name as String).trim().isEmpty) return null;

      return BarcodeProduct(
        name: name,
        imageUrl: product['image_front_small_url'] ?? product['image_url'],
      );
    } catch (_) {
      return null;
    }
  }
}
