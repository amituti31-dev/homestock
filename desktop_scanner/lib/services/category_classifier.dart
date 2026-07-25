import '../models/inventory_category.dart';

/// Best-effort category guess from a product's Hebrew name.
///
/// Barcode scans have no Gemini call to ask instead (that's the receipt
/// flow's job, on the phone only) — just a name string from the local index
/// or Open Food Facts. Keyword matching against real product-name vocabulary
/// pulled from the bundled price lists is good enough to beat "everything
/// defaults to food," which is what scanned items got before this existed.
class CategoryClassifier {
  CategoryClassifier._();

  /// Checked in this order, so a product matching more than one list (e.g.
  /// "משחת שיניים" containing both a cosmetics and a home-adjacent word)
  /// lands in the more specific category first. Falls back to
  /// `InventoryCategory.food` when nothing matches — the single most common
  /// category in a grocery store's catalogue anyway.
  static InventoryCategory classify(String name) {
    final normalized = name.trim();
    if (normalized.isEmpty) return InventoryCategory.food;

    for (final entry in _rules.entries) {
      if (entry.value.any((keyword) => normalized.contains(keyword))) {
        return entry.key;
      }
    }
    return InventoryCategory.food;
  }

  static final _rules = <InventoryCategory, List<String>>{
    InventoryCategory.medicine: [
      'תרופ', 'ויטמין', 'כמוס', 'טבליו', 'טבליה', 'תוסף תזונה', 'פרוביוטיק',
      'סירופ', 'משכך כאבים', 'אקמול', 'נורופן', 'אדוויל', 'אספירין',
      'פראצטמול', 'איבופרופן', 'פלסטר', 'חיטוי', 'מדחום', 'תחבושת',
      'קומפרס', 'משחת פצעים', 'קולגן', 'מגנזיום', 'אומגה 3', 'ברזל',
      'מולטי ויטמין', 'תרסיס לאף', 'טיפות עיניים', 'משאף',
    ],
    InventoryCategory.cosmetics: [
      'שמפו', 'מרכך', 'סבון', 'ג\'ל רחצה', 'גל רחצה', 'דאודורנט', 'בושם',
      'איפור', 'מייקאפ', 'ליפסטיק', 'לק ', 'מסכת פנים', 'מסיכת פנים',
      'קרם לחות', 'קרם יום', 'קרם לילה', 'קרם גוף', 'קרם פנים', 'קרם ידיים',
      'טיפוח', 'שפתון', 'מייק אפ', 'מגבונים לחים', 'משחת שיניים',
      'מברשת שיניים', 'חוט דנטלי', 'מסטיק', 'קונדישינר', 'תחליב גוף',
      'תחליב שיזוף', 'פילינג', 'מגן קרינה', 'קרן יום', 'ספריי שיער',
      'ג\'ל שיער', 'מוס לשיער', 'צבע שיער', 'מייבש שיער', 'מסרקה',
      'פד הנקה', 'רפידות הנקה', 'תחתון סופג', 'תחבושות היגייניות', 'טמפון',
      'קרם הגנה', 'אנטי אייג', 'סרום', 'טונר', 'מי פנים',
    ],
    InventoryCategory.tools: [
      'מברגה', 'פטיש', 'מקדחה', 'ברגים', 'בורג', 'סוללות', 'סוללה', 'נורה',
      'נורות', 'כבל חשמל', 'מברג', 'צבע קיר', 'דבק חזק', 'איטום',
      'מפתח ברגים', 'מסור', 'מלחציים', 'סרט מדידה', 'פלס',
    ],
    InventoryCategory.hobby: [
      'משחק קופסא', 'פאזל', 'צעצוע', 'ספר קריאה', 'צבעי', 'מכחול', 'קלף',
      'קלפים', 'לגו', 'בובה', 'משחקי ילדים', 'מלאכת יד', 'רקמה',
    ],
    InventoryCategory.clothingHome: [
      'חולצה', 'מכנס', 'נעל', 'נעליים', 'גרב', 'גרביים', 'מגבת', 'סדין',
      'מצעים', 'ציפית', 'שקית זבל', 'אבקת כביסה', 'מרכך כביסה', 'נייר טואלט',
      'נייר סופג', 'מגבון לניקוי', 'כלים חד פעמי', 'צלחות חד פעמי', 'מטלית',
      'ספוג כלים', 'אקונומיקה', 'מנקה רצפות', 'מנקה זכוכית', 'שואב אבק',
      'מכונת כביסה', 'תיק גב', 'כפפות ניקיון', 'שמיכה', 'כרית',
    ],
  };
}
