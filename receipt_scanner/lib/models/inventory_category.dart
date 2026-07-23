import 'package:flutter/material.dart';

enum InventoryCategory {
  food,
  medicine,
  clothingHome,
  cosmetics,
  tools,
  hobby;

  String get label {
    switch (this) {
      case InventoryCategory.food:
        return 'מזון & משקאות';
      case InventoryCategory.medicine:
        return 'תרופות';
      case InventoryCategory.clothingHome:
        return 'בגדים & בית';
      case InventoryCategory.cosmetics:
        return 'קוסמטיקה';
      case InventoryCategory.tools:
        return 'כלים & ציוד';
      case InventoryCategory.hobby:
        return 'אוספים & תחביבים';
    }
  }

  IconData get icon {
    switch (this) {
      case InventoryCategory.food:
        return Icons.kitchen;
      case InventoryCategory.medicine:
        return Icons.medication;
      case InventoryCategory.clothingHome:
        return Icons.checkroom;
      case InventoryCategory.cosmetics:
        return Icons.spa;
      case InventoryCategory.tools:
        return Icons.build;
      case InventoryCategory.hobby:
        return Icons.collections_bookmark;
    }
  }

  static InventoryCategory fromName(String name) {
    return InventoryCategory.values.firstWhere(
      (c) => c.name == name,
      orElse: () => InventoryCategory.food,
    );
  }
}
