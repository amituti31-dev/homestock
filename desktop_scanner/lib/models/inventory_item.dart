import '../services/rest_value.dart';
import 'inventory_category.dart';
import 'storage_location.dart';

/// Mirrors `InventoryItem` in the mobile app, but serialises to the Firestore
/// REST value format instead of using `cloud_firestore` (unsupported on
/// Windows). The field names must stay identical to the mobile app's
/// `toFirestore()` or the two clients will disagree about the same document.
class InventoryItem {
  /// Assigned by Firestore on create, so it is set after construction.
  String? id;
  String name;
  InventoryCategory category;
  double quantity;
  String unit;
  double minQuantity;
  DateTime? expiryDate;
  String? photoUrl;
  String? barcode;
  double? price;
  StorageLocation? location;
  String? customLocationName;
  String source;

  InventoryItem({
    this.id,
    required this.name,
    this.category = InventoryCategory.food,
    this.quantity = 1,
    this.unit = 'יח\'',
    this.minQuantity = 0,
    this.expiryDate,
    this.photoUrl,
    this.barcode,
    this.price,
    this.location,
    this.customLocationName,
    this.source = 'desktop_scan',
  });

  String? get locationLabel => location == StorageLocation.other
      ? (customLocationName?.trim().isNotEmpty == true
          ? customLocationName
          : location?.label)
      : location?.label;

  factory InventoryItem.fromRest(String docName, Map<String, dynamic> fields) {
    Map<String, dynamic>? f(String key) =>
        fields[key] as Map<String, dynamic>?;

    return InventoryItem(
      id: documentId(docName),
      name: decodeString(f('name')) ?? '',
      category: InventoryCategory.fromName(decodeString(f('category')) ?? 'food'),
      quantity: decodeDouble(f('quantity')) ?? 1,
      unit: decodeString(f('unit')) ?? 'יח\'',
      minQuantity: decodeDouble(f('minQuantity')) ?? 0,
      expiryDate: decodeTimestamp(f('expiryDate')),
      photoUrl: decodeString(f('photoUrl')),
      barcode: decodeString(f('barcode')),
      price: decodeDouble(f('price')),
      location: StorageLocation.fromName(decodeString(f('location'))),
      customLocationName: decodeString(f('customLocationName')),
      source: decodeString(f('source')) ?? 'manual',
    );
  }

  /// `addedAt` / `updatedAt` are deliberately absent: they are written as
  /// server-side transforms by `FirestoreService`, not as client values.
  Map<String, dynamic> toRestFields() {
    return {
      'name': encodeString(name),
      'category': encodeString(category.name),
      'quantity': encodeDouble(quantity),
      'unit': encodeString(unit),
      'minQuantity': encodeDouble(minQuantity),
      'expiryDate': encodeTimestamp(expiryDate),
      'photoUrl': encodeString(photoUrl),
      'barcode': encodeString(barcode),
      'price': encodeDouble(price),
      'location': encodeString(location?.name),
      'customLocationName': encodeString(
          location == StorageLocation.other ? customLocationName : null),
      'source': encodeString(source),
    };
  }
}
