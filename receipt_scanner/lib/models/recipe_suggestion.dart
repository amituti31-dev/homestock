class RecipeSuggestion {
  final String name;
  final List<String> ingredientsFromInventory;
  final List<String> missingIngredients;
  final String instructions;
  final bool usesExpiringSoon;

  RecipeSuggestion({
    required this.name,
    required this.ingredientsFromInventory,
    required this.missingIngredients,
    required this.instructions,
    required this.usesExpiringSoon,
  });

  factory RecipeSuggestion.fromJson(Map<String, dynamic> json) {
    return RecipeSuggestion(
      name: json['name'] ?? '',
      ingredientsFromInventory:
          List<String>.from(json['ingredientsFromInventory'] ?? []),
      missingIngredients: List<String>.from(json['missingIngredients'] ?? []),
      instructions: json['instructions'] ?? '',
      usesExpiringSoon: json['usesExpiringSoon'] ?? false,
    );
  }
}
