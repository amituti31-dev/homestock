import 'package:flutter/material.dart';
import '../models/inventory_category.dart';
import '../models/inventory_item.dart';
import '../services/firestore_service.dart';

class ItemsConfirmationScreen extends StatefulWidget {
  final List<InventoryItem> items;
  final String householdId;

  const ItemsConfirmationScreen({
    super.key,
    required this.items,
    required this.householdId,
  });

  @override
  State<ItemsConfirmationScreen> createState() =>
      _ItemsConfirmationScreenState();
}

class _ItemsConfirmationScreenState extends State<ItemsConfirmationScreen> {
  late List<InventoryItem> _items;
  late final FirestoreService _firestore;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _items = widget.items;
    _firestore = FirestoreService(widget.householdId);
  }

  int get _selectedCount => _items.where((i) => i.selected).length;

  Future<void> _addToInventory() async {
    final selected = _items.where((i) => i.selected).toList();
    setState(() => _saving = true);
    try {
      await _firestore.addItems(selected);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${selected.length} מוצרים נוספו למלאי!'),
          backgroundColor: const Color(0xFF4CAF50),
        ),
      );
      Navigator.popUntil(context, (route) => route.isFirst);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('שגיאה בשמירה: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${_items.length} מוצרים זוהו'),
          centerTitle: true,
          backgroundColor: const Color(0xFF4CAF50),
          foregroundColor: Colors.white,
          actions: [
            TextButton(
              onPressed: () {
                setState(() {
                  final allSelected = _items.every((item) => item.selected);
                  for (final item in _items) {
                    item.selected = !allSelected;
                  }
                });
              },
              child: Text(
                _items.every((i) => i.selected) ? 'בטל הכל' : 'בחר הכל',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _items.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (_, index) {
                  final item = _items[index];
                  return CheckboxListTile(
                    value: item.selected,
                    onChanged: (v) =>
                        setState(() => item.selected = v ?? false),
                    activeColor: const Color(0xFF4CAF50),
                    title: Text(
                      item.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${item.quantity} ${item.unit}'
                          '${item.price != null ? ' • ₪${item.price!.toStringAsFixed(2)}' : ''}',
                        ),
                        const SizedBox(height: 4),
                        DropdownButton<InventoryCategory>(
                          value: item.category,
                          isDense: true,
                          underline: const SizedBox(),
                          style: const TextStyle(fontSize: 12, color: Colors.black87),
                          items: InventoryCategory.values
                              .map((c) => DropdownMenuItem(
                                    value: c,
                                    child: Text(c.label),
                                  ))
                              .toList(),
                          onChanged: (c) =>
                              setState(() => item.category = c ?? item.category),
                        ),
                      ],
                    ),
                    secondary: CircleAvatar(
                      backgroundColor: const Color(0xFFE8F5E9),
                      child: Icon(item.category.icon, color: const Color(0xFF4CAF50)),
                    ),
                  );
                },
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _selectedCount > 0 && !_saving ? _addToInventory : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4CAF50),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey.shade300,
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          )
                        : Text(
                            'הוסף $_selectedCount מוצרים למלאי',
                            style: const TextStyle(fontSize: 16),
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
