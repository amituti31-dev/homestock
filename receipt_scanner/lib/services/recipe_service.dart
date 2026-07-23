import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../models/inventory_item.dart';
import '../models/recipe_suggestion.dart';

class RecipeService {
  Future<List<RecipeSuggestion>> suggestRecipes(
      List<InventoryItem> foodItems) async {
    final apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
    final model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: apiKey);

    final expiringSoon = foodItems
        .where((i) => i.isExpiringSoon || i.isExpired)
        .map((i) => i.name)
        .toList();
    final allNames = foodItems.map((i) => '${i.name} (${i.quantity} ${i.unit})').join(', ');

    final prompt = '''אתה שף שמציע מתכונים על בסיס מה שיש במטבח.

המוצרים הזמינים במלאי: $allNames

${expiringSoon.isNotEmpty ? 'המוצרים הבאים עומדים לפוג תוקף בקרוב ויש עדיפות לנצל אותם: ${expiringSoon.join(', ')}' : ''}

הצע 3 מתכונים שאפשר להכין בעיקר מהמוצרים הזמינים.
החזר JSON בלבד, ללא הסבר, בפורמט הבא:
{"recipes": [
  {
    "name": "שם המתכון",
    "usesExpiringSoon": true,
    "ingredientsFromInventory": ["מוצר 1", "מוצר 2"],
    "missingIngredients": ["מוצר שצריך לקנות"],
    "instructions": "הוראות הכנה קצרות וברורות, עד 5 שלבים"
  }
]}

כללים:
- usesExpiringSoon: true אם המתכון משתמש באחד מהמוצרים שעומדים לפוג
- missingIngredients: רק תבלינים/מרכיבים בסיסיים שסביר שחסרים, רשימה קצרה או ריקה
- עדיפות למתכונים פשוטים שדורשים כמה שפחות קניות נוספות''';

    final response = await model.generateContent([Content.text(prompt)]);
    final content = response.text ?? '';

    final jsonMatch = RegExp(r'\{.*\}', dotAll: true).firstMatch(content);
    if (jsonMatch == null) throw Exception('No JSON in response');

    final parsed = jsonDecode(jsonMatch.group(0)!);
    final recipes = parsed['recipes'] as List;
    return recipes.map((e) => RecipeSuggestion.fromJson(e)).toList();
  }
}
