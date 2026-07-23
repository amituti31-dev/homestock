import 'dart:convert';
import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../models/inventory_item.dart';

class GeminiService {
  Future<List<InventoryItem>> parseReceiptImage(File imageFile) async {
    final apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
    final model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: apiKey);

    const prompt = '''אתה מנתח תמונות של קבלות קניות ישראליות.
הסתכל בתמונה וחלץ את כל המוצרים שמופיעים בה.
החזר JSON בלבד, ללא הסבר, בפורמט הבא:
{"items": [{"name": "שם המוצר", "category": "food", "quantity": 1, "unit": "יח'", "price": 9.90}]}

כללים:
- name: שם המוצר בעברית, כפי שמופיע בקבלה (אל תמציא או תנחש מוצרים שלא רואים בבירור)
- category: סווג כל מוצר לאחת מהקטגוריות הבאות בלבד (ערך מדויק באנגלית):
  - "food": מזון ומשקאות (לרבות פירות, ירקות, חטיפים, שתייה)
  - "medicine": תרופות, ויטמינים, תוספי תזונה
  - "clothingHome": בגדים, כלי בית, מוצרי ניקיון, נייר טואלט, מגבות נייר, שקיות אשפה
  - "cosmetics": קוסמטיקה, טיפוח, שמפו, סבון, משחת שיניים
  - "tools": כלי עבודה וציוד
  - "hobby": ספרים, משחקים, תחביבים
  אם לא בטוח, בחר את הקטגוריה הכי הגיונית - "clothingHome" מתאים לרוב מוצרי הניקיון והבית
- quantity: כמות (מספר)
- unit: יחידת מידה (יח', ק"ג, ל', מ"ל, גרם)
- price: מחיר בשקלים (מספר עשרוני)
- התעלם משורות שאינן מוצרים (סה"כ, מע"מ, שם חנות, תאריך וכו')
- אם שורה לא ברורה או לא ניתנת לקריאה, דלג עליה לגמרי''';

    final imageBytes = await imageFile.readAsBytes();
    final response = await model.generateContent([
      Content.multi([
        TextPart(prompt),
        DataPart('image/jpeg', imageBytes),
      ])
    ]);
    final content = response.text ?? '';

    final jsonMatch = RegExp(r'\{.*\}', dotAll: true).firstMatch(content);
    if (jsonMatch == null) throw Exception('No JSON in response');

    final parsed = jsonDecode(jsonMatch.group(0)!);
    final items = parsed['items'] as List;
    return items.map((e) => InventoryItem.fromJson(e)).toList();
  }
}
