import 'package:cloud_firestore/cloud_firestore.dart';
import 'inventory_category.dart';
import 'storage_location.dart';

class InventoryItem {
  final String? id;
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
  bool selected;

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
    this.source = 'manual',
    this.selected = true,
  });

  String? get locationLabel => location == StorageLocation.other
      ? (customLocationName?.trim().isNotEmpty == true
          ? customLocationName
          : location?.label)
      : location?.label;

  bool get isLowStock => minQuantity > 0 && quantity <= minQuantity;

  bool get isExpired =>
      expiryDate != null && expiryDate!.isBefore(DateTime.now());

  bool get isExpiringSoon {
    if (expiryDate == null || isExpired) return false;
    return expiryDate!.difference(DateTime.now()).inDays <= 3;
  }

  factory InventoryItem.fromJson(Map<String, dynamic> json) {
    return InventoryItem(
      name: json['name'] ?? '',
      category: InventoryCategory.fromName(json['category'] ?? 'food'),
      quantity: (json['quantity'] ?? 1).toDouble(),
      unit: json['unit'] ?? 'יח\'',
      price: json['price']?.toDouble(),
      source: 'receipt_scan',
    );
  }

  factory InventoryItem.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return InventoryItem(
      id: doc.id,
      name: data['name'] ?? '',
      category: InventoryCategory.fromName(data['category'] ?? 'food'),
      quantity: (data['quantity'] ?? 1).toDouble(),
      unit: data['unit'] ?? 'יח\'',
      minQuantity: (data['minQuantity'] ?? 0).toDouble(),
      expiryDate: (data['expiryDate'] as Timestamp?)?.toDate(),
      photoUrl: data['photoUrl'],
      barcode: data['barcode'],
      price: data['price']?.toDouble(),
      location: StorageLocation.fromName(data['location']),
      customLocationName: data['customLocationName'],
      source: data['source'] ?? 'manual',
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'category': category.name,
      'quantity': quantity,
      'unit': unit,
      'minQuantity': minQuantity,
      'expiryDate': expiryDate != null ? Timestamp.fromDate(expiryDate!) : null,
      'photoUrl': photoUrl,
      'barcode': barcode,
      'price': price,
      'location': location?.name,
      'customLocationName': location == StorageLocation.other ? customLocationName : null,
      'source': source,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}
