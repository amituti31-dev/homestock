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
  /// `InventoryCategory.food` ("מזון אחר") when nothing matches.
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

    // Food subcategories — checked before the generic clothingHome/food
    // fallback so a scanned grocery item lands somewhere more specific than
    // "מזון אחר" whenever possible.
    // No bare 'לבן'/'לבנה' ("white") here — as a generic color adjective it
    // false-matches non-dairy products like "קמח לבן" (white flour) or
    // "שעועית לבנה" (white beans); 'גבינ' already covers "גבינה לבנה".
    InventoryCategory.dairy: [
      'חלב', 'גבינ', 'יוגורט', 'שמנת', 'חמאה', 'קוטג\'', 'קפיר',
      'מעדן חלב', 'קצפת',
    ],
    InventoryCategory.meatFish: [
      'בשר', 'עוף', 'הודו', 'נקניק', 'סלמון', 'טונה', 'דג ', 'דגים', 'כבד',
      'קציצות', 'המבורגר', 'שניצל', 'פסטרמה', 'סלמי', 'בקר', 'כבש', 'פילה',
      'סטייק', 'צלי',
    ],
    // Checked before vegetablesFruits: fruit names ("תפוז", "לימון"...) show
    // up constantly in juice/drink names, and "מיץ תפוזים" is a beverage,
    // not produce.
    InventoryCategory.beverages: [
      'מיץ', 'משקה קל', 'קולה', 'סודה', 'בקבוק מים', 'מים מינרל', 'בירה',
      'יין', 'ליקר', 'משקה אנרגי', 'נביעות', 'סירופ מייפל',
    ],
    // Checked before snacks: "גלידת שוקולד" contains a snack-flavor word
    // ("שוקולד") but is frozen, not a shelf snack.
    InventoryCategory.frozen: [
      'קפוא', 'קפואה', 'קפואים', 'גלידה', 'גלידת',
    ],
    // Checked before vegetablesFruits/snacks/breadBakery: prepared sauces,
    // spice mixes and spreads very often name a raw ingredient ("רוטב
    // עגבניות" = tomato sauce, "ממרח עגבניות" = tomato spread), which would
    // otherwise false-match on that ingredient's produce/snack keyword.
    InventoryCategory.spicesSauces: [
      'תבלין', 'רוטב', 'קטשופ', 'מיונז', 'חרדל', 'שמן זית', 'חומץ',
      'אבקת קארי', 'זעתר', 'פפריקה', 'כמון', 'קארי', 'קימל', 'אורגנו', 'ממרח',
    ],
    InventoryCategory.cannedDry: [
      'שימור', 'פסטה', 'אורז', 'קטני', 'עדשים', 'חומוס יבש', 'קמח', 'סוכר',
      'מלח', 'דגני בוקר', 'גרעיני', 'קינואה', 'בורגול', 'שעועית',
    ],
    InventoryCategory.vegetablesFruits: [
      'עגבני', 'מלפפון', 'תפוח אדמה', 'תפוח עץ', 'בננה', 'גזר', 'בצל', 'חסה',
      'פלפל', 'אבוקדו', 'לימון', 'תפוז', 'ענבים', 'אבטיח', 'מלון',
      // Space-bounded so "שום" (garlic) doesn't false-match inside "שומשום"
      // (sesame), which contains it as a substring with no word boundary.
      ' שום', 'שום ',
      'פטריות', 'ירק ', 'ירקות', 'פרי ', 'פירות', 'תות', 'אגס', 'אפרסק',
    ],
    InventoryCategory.snacks: [
      'חטיף', 'במבה', 'ביסלי', 'צ\'יפס', 'עוגי', 'שוקולד', 'ממתק', 'סוכריה',
      'סוכריות', 'וופל', 'קרקר', 'פופקורן', 'חטיפי',
    ],
    InventoryCategory.breadBakery: [
      'לחם', 'פיתה', 'בגט', 'לחמניה', 'חלה', 'מאפה', 'קרואסון', 'עוגה',
      'בורקס', 'לחמניות',
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
