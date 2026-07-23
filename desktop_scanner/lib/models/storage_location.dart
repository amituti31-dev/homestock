import 'package:flutter/material.dart';

enum StorageLocation {
  fridge,
  freezer,
  pantry,
  bathroom,
  garage,
  closet,
  other;

  String get label {
    switch (this) {
      case StorageLocation.fridge:
        return 'מקרר';
      case StorageLocation.freezer:
        return 'מקפיא';
      case StorageLocation.pantry:
        return 'מזווה';
      case StorageLocation.bathroom:
        return 'חדר אמבטיה';
      case StorageLocation.garage:
        return 'מוסך';
      case StorageLocation.closet:
        return 'ארון';
      case StorageLocation.other:
        return 'אחר';
    }
  }

  IconData get icon {
    switch (this) {
      case StorageLocation.fridge:
        return Icons.kitchen;
      case StorageLocation.freezer:
        return Icons.ac_unit;
      case StorageLocation.pantry:
        return Icons.door_sliding;
      case StorageLocation.bathroom:
        return Icons.bathtub;
      case StorageLocation.garage:
        return Icons.garage;
      case StorageLocation.closet:
        return Icons.checkroom;
      case StorageLocation.other:
        return Icons.more_horiz;
    }
  }

  static StorageLocation? fromName(String? name) {
    if (name == null) return null;
    for (final loc in StorageLocation.values) {
      if (loc.name == name) return loc;
    }
    return null;
  }
}
