import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

import '../models/inventory_category.dart';

/// Best-effort AI classification for a scanned product's bare name, using
/// the same 15-category list the phone's receipt flow already classifies
/// into (see receipt_scanner's GeminiService — keep the category list in
/// sync with both that prompt and CategoryClassifier).
///
/// Unlike the phone's receipt flow this has no image, just a short product
/// name, so a short text prompt is enough. Callers should fall back to
/// [CategoryClassifier] on a null result (offline, quota exceeded, timeout,
/// or an unparseable response) — the scan-to-inventory loop must never hang
/// waiting on a flaky network call.
class GeminiService {
  Future<InventoryCategory?> classifyProduct(String name) async {
    final apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
    if (apiKey.isEmpty) return null;

    final model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: apiKey);
    const prompt = '''סווג את שם המוצר הבא לאחת מהקטגוריות הבאות בלבד.
החזר אך ורק את הערך המדויק באנגלית (ללא הסבר, ללא סימני פיסוק נוספים):
- dairy: מוצרי חלב (חלב, גבינות, יוגורט, שמנת, חמאה)
- meatFish: בשר, עוף, דגים, נקניקים
- vegetablesFruits: ירקות ופירות טריים
- snacks: חטיפים, ממתקים, עוגיות, שוקולד
- breadBakery: לחם ומאפים
- beverages: משקאות (מים, מיצים, שתייה קלה, בירה, יין)
- frozen: מוצרים קפואים (כולל גלידה)
- spicesSauces: תבלינים, רטבים, שמן, חומץ, ממרחים
- cannedDry: שימורים ומוצרים יבשים (פסטה, אורז, קטניות, קמח, סוכר, מלח)
- food: מזון אחר שלא מתאים לאף אחת מהקטגוריות שלמעלה
- medicine: תרופות, ויטמינים, תוספי תזונה
- clothingHome: בגדים, כלי בית, מוצרי ניקיון, נייר טואלט, מגבות נייר, שקיות אשפה
- cosmetics: קוסמטיקה, טיפוח, שמפו, סבון, משחת שיניים
- tools: כלי עבודה וציוד
- hobby: ספרים, משחקים, תחביבים

שם המוצר:''';

    try {
      final response = await model
          .generateContent([Content.text('$prompt "$name"')])
          .timeout(const Duration(seconds: 6));
      final text = response.text?.trim();
      if (text == null || text.isEmpty) return null;

      for (final category in InventoryCategory.values) {
        if (text == category.name || text.contains(category.name)) {
          return category;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
