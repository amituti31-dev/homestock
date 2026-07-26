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

    test('recognises food subcategories instead of a generic food bucket', () {
      expect(CategoryClassifier.classify('גבינה צהובה עמק 200 גרם'),
          InventoryCategory.dairy);
      expect(CategoryClassifier.classify('חזה עוף טרי'),
          InventoryCategory.meatFish);
      expect(CategoryClassifier.classify('עגבניות שרי אשכול'),
          InventoryCategory.vegetablesFruits);
      expect(CategoryClassifier.classify('במבה אסם 80 גרם'),
          InventoryCategory.snacks);
      expect(CategoryClassifier.classify('לחם אחיד פרוס'),
          InventoryCategory.breadBakery);
      expect(CategoryClassifier.classify('מיץ תפוזים טבעי 1 ליטר'),
          InventoryCategory.beverages);
      expect(CategoryClassifier.classify('גלידת שוקולד קפואה'),
          InventoryCategory.frozen);
      expect(CategoryClassifier.classify('תבלין קימל טחון'),
          InventoryCategory.spicesSauces);
      expect(CategoryClassifier.classify('אורז בסמטי 1 ק"ג'),
          InventoryCategory.cannedDry);
    });

    test('falls back to food ("מזון אחר") when nothing matches', () {
      expect(CategoryClassifier.classify('מוצר ללא סיווג ברור 123'),
          InventoryCategory.food);
      expect(CategoryClassifier.classify(''), InventoryCategory.food);
    });

    test('prefers spicesSauces over a produce keyword inside a sauce name', () {
      // "רוטב עגבניות" (tomato sauce) contains "עגבני" (tomato), but a sauce
      // isn't produce.
      expect(CategoryClassifier.classify('רוטב עגבניות קלאסי'),
          InventoryCategory.spicesSauces);
      expect(CategoryClassifier.classify('ממרח עגבניות מיובשות 185 גרם'),
          InventoryCategory.spicesSauces);
    });

    test('does not match "שום" (garlic) inside the unrelated word "שומשום" (sesame)', () {
      expect(CategoryClassifier.classify('שומשום'), InventoryCategory.food);
      expect(CategoryClassifier.classify('זעתר ושומשום בלדי 150 גרם'),
          InventoryCategory.spicesSauces);
    });

    test('does not treat "white" ("לבן"/"לבנה") as a dairy signal on its own', () {
      expect(CategoryClassifier.classify('קמח חיטה לבן מנופה'),
          InventoryCategory.cannedDry);
      expect(CategoryClassifier.classify('סוכר לבן 1 ק"ג'),
          InventoryCategory.cannedDry);
      expect(CategoryClassifier.classify('שעועית לבנה גדולה'),
          InventoryCategory.cannedDry);
    });
  });
}
