import 'package:flutter/material.dart';
import '../models/inventory_category.dart';
import '../models/inventory_item.dart';
import '../services/firestore_service.dart';
import 'inventory_list_screen.dart';
import 'recipe_suggestions_screen.dart';

class HomeOverviewScreen extends StatefulWidget {
  final String householdId;

  const HomeOverviewScreen({super.key, required this.householdId});

  @override
  State<HomeOverviewScreen> createState() => _HomeOverviewScreenState();
}

class _HomeOverviewScreenState extends State<HomeOverviewScreen> {
  late final FirestoreService _firestore;

  @override
  void initState() {
    super.initState();
    _firestore = FirestoreService(widget.householdId);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('HomeStock'),
          centerTitle: true,
          backgroundColor: const Color(0xFF4CAF50),
          foregroundColor: Colors.white,
        ),
        body: StreamBuilder<List<InventoryItem>>(
          stream: _firestore.streamItems(),
          builder: (context, snapshot) {
            final items = snapshot.data ?? [];
            final lowStock = items.where((i) => i.isLowStock).toList();

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  color: const Color(0xFF4CAF50),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => RecipeSuggestionsScreen(
                            householdId: widget.householdId),
                      ),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(Icons.restaurant_menu, color: Colors.white, size: 32),
                          SizedBox(width: 16),
                          Expanded(
                            child: Text('מה לבשל היום?',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold)),
                          ),
                          Icon(Icons.arrow_back_ios, color: Colors.white, size: 16),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                if (lowStock.isNotEmpty) ...[
                  Row(
                    children: [
                      const Text('מלאי נמוך',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () async {
                          await _firestore.addLowStockToShoppingList(lowStock);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('נוסף לרשימת הקניות'),
                              backgroundColor: Color(0xFF4CAF50),
                            ),
                          );
                        },
                        icon: const Icon(Icons.add_shopping_cart, size: 18),
                        label: const Text('הוסף לרשימה'),
                        style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF4CAF50)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...lowStock.map((i) => Card(
                        color: Colors.orange.shade50,
                        child: ListTile(
                          leading: const Icon(Icons.warning_amber, color: Colors.orange),
                          title: Text(i.name),
                          subtitle: Text('${i.quantity} ${i.unit} נותרו'),
                        ),
                      )),
                  const SizedBox(height: 24),
                ],
                const Text('קטגוריות',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.3,
                  children: InventoryCategory.values.map((c) {
                    final count = items.where((i) => i.category == c).length;
                    return _CategoryCard(
                      category: c,
                      count: count,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => InventoryListScreen(
                            householdId: widget.householdId,
                            initialCategory: c,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final InventoryCategory category;
  final int count;
  final VoidCallback onTap;

  const _CategoryCard({
    required this.category,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(category.icon, color: const Color(0xFF4CAF50), size: 28),
              const SizedBox(height: 8),
              Text(
                category.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              const SizedBox(height: 4),
              Text('$count פריטים',
                  style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
