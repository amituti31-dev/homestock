import 'package:desktop_scanner/models/inventory_category.dart';
import 'package:desktop_scanner/models/inventory_item.dart';
import 'package:desktop_scanner/models/storage_location.dart';
import 'package:desktop_scanner/services/barcode_lookup_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InventoryItem REST serialisation', () {
    test('round-trips through the Firestore REST value format', () {
      final original = InventoryItem(
        name: 'חלב תנובה 3%',
        category: InventoryCategory.food,
        quantity: 2,
        unit: 'ל\'',
        minQuantity: 1,
        expiryDate: DateTime(2026, 8, 1),
        barcode: '7290000000001',
        photoUrl: 'https://example.org/milk.jpg',
        location: StorageLocation.fridge,
      );

      final restored = InventoryItem.fromRest(
        'projects/p/databases/(default)/documents/households/h/items/abc123',
        original.toRestFields(),
      );

      expect(restored.id, 'abc123');
      expect(restored.name, original.name);
      expect(restored.category, InventoryCategory.food);
      expect(restored.quantity, 2);
      expect(restored.unit, 'ל\'');
      expect(restored.minQuantity, 1);
      expect(restored.expiryDate, original.expiryDate);
      expect(restored.barcode, original.barcode);
      expect(restored.photoUrl, original.photoUrl);
      expect(restored.location, StorageLocation.fridge);
    });

    test('custom location name is dropped unless the location is "other"', () {
      final item = InventoryItem(
        name: 'x',
        location: StorageLocation.pantry,
        customLocationName: 'מדף עליון',
      );

      expect(item.toRestFields()['customLocationName'], {'nullValue': null});
    });
  });

  group('BarcodeProduct.displayName', () {
    test('prefixes the brand when the name does not already include it', () {
      final product = BarcodeProduct(name: 'קוטג\' 5%', brand: 'תנובה');
      expect(product.displayName, 'תנובה קוטג\' 5%');
    });

    test('leaves the name alone when it already starts with the brand', () {
      final product = BarcodeProduct(name: 'תנובה קוטג\' 5%', brand: 'תנובה');
      expect(product.displayName, 'תנובה קוטג\' 5%');
    });

    test('falls back to the bare name without a brand', () {
      expect(BarcodeProduct(name: 'קוטג\'').displayName, 'קוטג\'');
    });
  });
}
