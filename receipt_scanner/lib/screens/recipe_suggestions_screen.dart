import 'package:flutter/material.dart';
import '../models/inventory_category.dart';
import '../models/recipe_suggestion.dart';
import '../services/firestore_service.dart';
import '../services/recipe_service.dart';

class RecipeSuggestionsScreen extends StatefulWidget {
  final String householdId;

  const RecipeSuggestionsScreen({super.key, required this.householdId});

  @override
  State<RecipeSuggestionsScreen> createState() =>
      _RecipeSuggestionsScreenState();
}

class _RecipeSuggestionsScreenState extends State<RecipeSuggestionsScreen> {
  final _recipeService = RecipeService();
  late final FirestoreService _firestore;
  bool _loading = true;
  String? _error;
  List<RecipeSuggestion> _recipes = [];

  @override
  void initState() {
    super.initState();
    _firestore = FirestoreService(widget.householdId);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _firestore
          .streamItems(category: InventoryCategory.food)
          .first;
      if (items.isEmpty) {
        setState(() {
          _error = 'אין מוצרי מזון במלאי כדי להציע מתכונים';
          _loading = false;
        });
        return;
      }
      final recipes = await _recipeService.suggestRecipes(items);
      if (!mounted) return;
      setState(() {
        _recipes = recipes;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'שגיאה בטעינת הצעות: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('מה לבשל היום?'),
          centerTitle: true,
          backgroundColor: const Color(0xFF4CAF50),
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loading ? null : _load,
            ),
          ],
        ),
        body: _loading
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: Color(0xFF4CAF50)),
                    SizedBox(height: 16),
                    Text('חושב על מתכונים...'),
                  ],
                ),
              )
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.grey)),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _recipes.length,
                    itemBuilder: (_, index) {
                      final recipe = _recipes[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(recipe.name,
                                        style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold)),
                                  ),
                                  if (recipe.usesExpiringSoon)
                                    const Icon(Icons.event_busy,
                                        color: Colors.orange, size: 20),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: recipe.ingredientsFromInventory
                                    .map((i) => Chip(
                                          label: Text(i, style: const TextStyle(fontSize: 12)),
                                          backgroundColor: const Color(0xFFE8F5E9),
                                          visualDensity: VisualDensity.compact,
                                        ))
                                    .toList(),
                              ),
                              if (recipe.missingIngredients.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text('חסר: ${recipe.missingIngredients.join(', ')}',
                                    style: TextStyle(
                                        fontSize: 12, color: Colors.grey.shade600)),
                              ],
                              const SizedBox(height: 12),
                              Text(recipe.instructions),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
