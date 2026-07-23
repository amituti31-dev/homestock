import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../models/inventory_category.dart';
import '../models/inventory_item.dart';
import '../models/shopping_list_item.dart';
import '../services/firestore_service.dart';

class ShoppingListScreen extends StatefulWidget {
  final String householdId;

  const ShoppingListScreen({super.key, required this.householdId});

  @override
  State<ShoppingListScreen> createState() => _ShoppingListScreenState();
}

class _ShoppingListScreenState extends State<ShoppingListScreen> {
  late final FirestoreService _firestore;

  @override
  void initState() {
    super.initState();
    _firestore = FirestoreService(widget.householdId);
  }

  void _shareList(List<ShoppingListItem> items) {
    if (items.isEmpty) return;

    final groups = <String, List<ShoppingListItem>>{};
    for (final item in items) {
      final key = item.store ?? 'ללא חנות';
      groups.putIfAbsent(key, () => []).add(item);
    }

    final buffer = StringBuffer('רשימת קניות:\n\n');
    for (final entry in groups.entries) {
      buffer.writeln('${entry.key}:');
      for (final item in entry.value) {
        buffer.writeln('- ${item.name} (${item.quantity} ${item.unit})');
      }
      buffer.writeln();
    }

    Share.share(buffer.toString());
  }

  Future<void> _addItemDialog() async {
    final inventoryItems = await _firestore.streamItems().first;
    if (!mounted) return;

    final nameController = TextEditingController();
    final storeController = TextEditingController();
    var category = InventoryCategory.food;
    InventoryItem? linkedItem;

    final added = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('פריט חדש לרשימה'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (inventoryItems.isNotEmpty) ...[
                    const Text('בחר מוצר קיים מהמלאי (אופציונלי)',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 4),
                    Autocomplete<InventoryItem>(
                      displayStringForOption: (item) => item.name,
                      optionsBuilder: (value) {
                        if (value.text.isEmpty) return inventoryItems;
                        return inventoryItems.where((i) =>
                            i.name.contains(value.text));
                      },
                      fieldViewBuilder:
                          (ctx, controller, focusNode, onSubmit) {
                        return TextField(
                          controller: controller,
                          focusNode: focusNode,
                          decoration: const InputDecoration(
                            labelText: 'חיפוש במלאי',
                            prefixIcon: Icon(Icons.inventory_2, size: 20),
                          ),
                        );
                      },
                      onSelected: (item) {
                        setDialogState(() {
                          linkedItem = item;
                          nameController.text = item.name;
                          category = item.category;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                  ],
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'שם המוצר'),
                    autofocus: inventoryItems.isEmpty,
                    onChanged: (_) => setDialogState(() => linkedItem = null),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: storeController,
                    decoration:
                        const InputDecoration(labelText: 'חנות (אופציונלי)'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<InventoryCategory>(
                    initialValue: category,
                    decoration: const InputDecoration(labelText: 'קטגוריה'),
                    items: InventoryCategory.values
                        .map((c) =>
                            DropdownMenuItem(value: c, child: Text(c.label)))
                        .toList(),
                    onChanged: (c) =>
                        setDialogState(() => category = c ?? category),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('ביטול'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4CAF50),
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('הוסף'),
              ),
            ],
          ),
        ),
      ),
    );

    if (added == true && nameController.text.trim().isNotEmpty) {
      await _firestore.addShoppingListItem(ShoppingListItem(
        name: nameController.text.trim(),
        unit: linkedItem?.unit ?? 'יח\'',
        store: storeController.text.trim().isEmpty ? null : storeController.text.trim(),
        category: category,
        inventoryItemId: linkedItem?.id,
      ));
    }
  }

  Future<void> _markBought(ShoppingListItem item) async {
    await _firestore.markShoppingListItemBought(item);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('"${item.name}" נוסף למלאי'),
        backgroundColor: const Color(0xFF4CAF50),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: StreamBuilder<List<ShoppingListItem>>(
        stream: _firestore.streamShoppingList(),
        builder: (context, snapshot) {
          final items = snapshot.data ?? [];
          final loading = snapshot.connectionState == ConnectionState.waiting;

          final groups = <String, List<ShoppingListItem>>{};
          for (final item in items) {
            final key = item.store ?? 'ללא חנות';
            groups.putIfAbsent(key, () => []).add(item);
          }

          return Scaffold(
            appBar: AppBar(
              title: const Text('רשימת קניות'),
              centerTitle: true,
              backgroundColor: const Color(0xFF4CAF50),
              foregroundColor: Colors.white,
              actions: [
                IconButton(
                  icon: const Icon(Icons.share),
                  onPressed: items.isEmpty ? null : () => _shareList(items),
                ),
              ],
            ),
            floatingActionButton: FloatingActionButton(
              heroTag: 'shopping_list_fab',
              onPressed: _addItemDialog,
              backgroundColor: const Color(0xFF4CAF50),
              child: const Icon(Icons.add, color: Colors.white),
            ),
            body: loading
                ? const Center(child: CircularProgressIndicator())
                : items.isEmpty
                    ? const Center(
                        child: Text('רשימת הקניות ריקה',
                            style: TextStyle(color: Colors.grey, fontSize: 16)),
                      )
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: groups.entries.expand((entry) {
                          return [
                            Padding(
                              padding: const EdgeInsets.only(top: 8, bottom: 4),
                              child: Text(
                                entry.key,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF4CAF50)),
                              ),
                            ),
                            ...entry.value.map((item) => Card(
                                  child: CheckboxListTile(
                                    value: false,
                                    onChanged: (_) => _markBought(item),
                                    activeColor: const Color(0xFF4CAF50),
                                    title: Text(item.name),
                                    subtitle: Text(
                                      '${item.quantity} ${item.unit}'
                                      '${item.autoGenerated ? ' • מלאי נמוך' : ''}',
                                    ),
                                    secondary: IconButton(
                                      icon: const Icon(Icons.delete_outline,
                                          color: Colors.grey),
                                      onPressed: () => _firestore
                                          .deleteShoppingListItem(item.id!),
                                    ),
                                  ),
                                )),
                          ];
                        }).toList(),
                      ),
          );
        },
      ),
    );
  }
}
