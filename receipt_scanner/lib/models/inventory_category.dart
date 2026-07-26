import 'package:flutter/material.dart';

/// Mirrors `InventoryCategory` in the desktop app. The enum *names* are the
/// values stored in Firestore — keep them identical across both apps.
///
/// `food` is kept as the enum name (not renamed/removed) even though its
/// label is now "מזון אחר" — it's the catch-all for food that doesn't match
/// a more specific bucket, and renaming or removing it would silently break
/// every item already stored with category: "food".
enum InventoryCategory {
  dairy,
  meatFish,
  vegetablesFruits,
  snacks,
  breadBakery,
  beverages,
  cannedDry,
  frozen,
  spicesSauces,
  food,
  medicine,
  clothingHome,
  cosmetics,
  tools,
  hobby;

  String get label {
    switch (this) {
      case InventoryCategory.dairy:
        return 'מוצרי חלב';
      case InventoryCategory.meatFish:
        return 'בשר ודגים';
      case InventoryCategory.vegetablesFruits:
        return 'ירקות ופירות';
      case InventoryCategory.snacks:
        return 'חטיפים ומתוקים';
      case InventoryCategory.breadBakery:
        return 'לחם ומאפים';
      case InventoryCategory.beverages:
        return 'משקאות';
      case InventoryCategory.cannedDry:
        return 'שימורים ויבשים';
      case InventoryCategory.frozen:
        return 'קפואים';
      case InventoryCategory.spicesSauces:
        return 'תבלינים ורטבים';
      case InventoryCategory.food:
        return 'מזון אחר';
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
      case InventoryCategory.dairy:
        return Icons.icecream;
      case InventoryCategory.meatFish:
        return Icons.set_meal;
      case InventoryCategory.vegetablesFruits:
        return Icons.eco;
      case InventoryCategory.snacks:
        return Icons.cookie;
      case InventoryCategory.breadBakery:
        return Icons.bakery_dining;
      case InventoryCategory.beverages:
        return Icons.local_drink;
      case InventoryCategory.cannedDry:
        return Icons.rice_bowl;
      case InventoryCategory.frozen:
        return Icons.ac_unit;
      case InventoryCategory.spicesSauces:
        return Icons.soup_kitchen;
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
