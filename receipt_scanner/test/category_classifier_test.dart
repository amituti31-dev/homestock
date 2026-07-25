import 'package:receipt_scanner/models/inventory_category.dart';
import 'package:receipt_scanner/services/category_classifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CategoryClassifier.classify', () {
    test('recognises cosmetics products', () {
      expect(CategoryClassifier.classify('קולגייט משחת שיניים 100 מל'),
          InventoryCategory.cosmetics);
      expect(CategoryClassifier.classify('שמפו לשיער יבש 400 מל'),
          InventoryCategory.cosmetics);
    });

    test('recognises medicine and supplements', () {
      expect(CategoryClassifier.classify('אקמול 500 מג 20 טבליות'),
          InventoryCategory.medicine);
      expect(CategoryClassifier.classify('ויטמין C ליפוזומלי 250 מל'),
          InventoryCategory.medicine);
    });

    test('recognises household and tool products', () {
      expect(CategoryClassifier.classify('נייר טואלט 24 גלילים'),
          InventoryCategory.clothingHome);
      expect(CategoryClassifier.classify('סוללות AA ארבע יחידות'),
          InventoryCategory.tools);
    });

    test('falls back to food when nothing matches', () {
      expect(CategoryClassifier.classify('עגבניות קצוצות ברסק'),
          InventoryCategory.food);
      expect(CategoryClassifier.classify(''), InventoryCategory.food);
    });
  });
}
