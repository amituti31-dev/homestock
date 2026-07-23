import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../models/inventory_category.dart';
import '../models/inventory_item.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';
import 'add_edit_item_screen.dart';

class InventoryListScreen extends StatefulWidget {
  final String householdId;
  final InventoryCategory? initialCategory;

  const InventoryListScreen({
    super.key,
    required this.householdId,
    this.initialCategory,
  });

  @override
  State<InventoryListScreen> createState() => _InventoryListScreenState();
}

class _InventoryListScreenState extends State<InventoryListScreen> {
  late final FirestoreService _firestore;
  final _notifications = NotificationService();
  InventoryCategory? _categoryFilter;
  String _search = '';
  final Set<String> _selectedIds = {};
  late Stream<List<InventoryItem>> _itemsStream;

  bool get _selectionMode => _selectedIds.isNotEmpty;

  void _toggleSelected(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  Future<void> _deleteSelected() async {
    final count = _selectedIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('מחיקת פריטים'),
          content: Text('למחוק $count פריטים מהמלאי?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false), child: const Text('ביטול')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('מחק', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    final ids = List<String>.from(_selectedIds);
    for (final id in ids) {
      await _firestore.deleteItem(id);
      await _notifications.cancelExpiryReminder(id);
    }
    if (!mounted) return;
    setState(() => _selectedIds.clear());
  }

  @override
  void initState() {
    super.initState();
    _firestore = FirestoreService(widget.householdId);
    _categoryFilter = widget.initialCategory;
    _itemsStream = _firestore.streamItems(category: _categoryFilter);
  }

  void _setCategoryFilter(InventoryCategory? category) {
    setState(() {
      _categoryFilter = category;
      _itemsStream = _firestore.streamItems(category: _categoryFilter);
    });
  }

  Future<void> _adjustQuantity(InventoryItem item, double delta) async {
    final newQuantity = (item.quantity + delta).clamp(0, double.infinity).toDouble();
    if (newQuantity == item.quantity) return;
    await _firestore.updateQuantity(item.id!, newQuantity);

    final crossedIntoLowStock = item.minQuantity > 0 &&
        item.quantity > item.minQuantity &&
        newQuantity <= item.minQuantity;
    if (crossedIntoLowStock) {
      await _notifications.showLowStockAlert(InventoryItem(
        id: item.id,
        name: item.name,
        category: item.category,
        quantity: newQuantity,
        unit: item.unit,
        minQuantity: item.minQuantity,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_selectionMode ? '${_selectedIds.length} נבחרו' : 'המלאי שלי'),
          centerTitle: true,
          backgroundColor: const Color(0xFF4CAF50),
          foregroundColor: Colors.white,
          leading: _selectionMode
              ? IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => _selectedIds.clear()),
                )
              : null,
          actions: _selectionMode
              ? [
                  IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: _deleteSelected,
                  ),
                ]
              : null,
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'חיפוש מוצר...',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (v) => setState(() => _search = v.trim()),
              ),
            ),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _CategoryChip(
                    label: 'הכל',
                    selected: _categoryFilter == null,
                    onTap: () => _setCategoryFilter(null),
                  ),
                  ...InventoryCategory.values.map(
                    (c) => _CategoryChip(
                      label: c.label,
                      selected: _categoryFilter == c,
                      onTap: () => _setCategoryFilter(c),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: StreamBuilder<List<InventoryItem>>(
                stream: _itemsStream,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text('שגיאה: ${snapshot.error}'));
                  }
                  var items = snapshot.data ?? [];
                  if (_search.isNotEmpty) {
                    items = items
                        .where((i) => i.name.contains(_search))
                        .toList();
                  }
                  items = [...items]..sort((a, b) {
                      if (a.expiryDate == null && b.expiryDate == null) return 0;
                      if (a.expiryDate == null) return 1;
                      if (b.expiryDate == null) return -1;
                      return a.expiryDate!.compareTo(b.expiryDate!);
                    });
                  if (items.isEmpty) {
                    return const Center(
                      child: Text('אין פריטים במלאי',
                          style: TextStyle(color: Colors.grey, fontSize: 16)),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, index) {
                      final item = items[index];
                      final selected = _selectedIds.contains(item.id);
                      return ListTile(
                        selected: selected,
                        selectedTileColor: const Color(0xFFE8F5E9),
                        leading: selected
                            ? const CircleAvatar(
                                backgroundColor: Color(0xFF4CAF50),
                                child: Icon(Icons.check, color: Colors.white),
                              )
                            : CircleAvatar(
                                backgroundColor: const Color(0xFFE8F5E9),
                                backgroundImage: item.photoUrl != null
                                    ? NetworkImage(item.photoUrl!)
                                    : null,
                                child: item.photoUrl == null
                                    ? Icon(item.category.icon,
                                        color: const Color(0xFF4CAF50))
                                    : null,
                              ),
                        title: Text(item.name,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${item.quantity} ${item.unit}'
                              '${item.locationLabel != null ? ' • ${item.locationLabel}' : ''}',
                            ),
                            if (item.expiryDate != null) ...[
                              const SizedBox(height: 4),
                              if (item.isExpired || item.isExpiringSoon)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: item.isExpired
                                        ? Colors.red
                                        : Colors.orange,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    item.isExpired
                                        ? 'פג תוקף! ${DateFormat('dd/MM/yyyy').format(item.expiryDate!)}'
                                        : 'תוקף בקרוב: ${DateFormat('dd/MM/yyyy').format(item.expiryDate!)}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                )
                              else
                                Text(
                                  'תוקף: ${DateFormat('dd/MM/yyyy').format(item.expiryDate!)}',
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.grey),
                                ),
                            ],
                          ],
                        ),
                        trailing: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (item.isLowStock ||
                                item.isExpired ||
                                item.isExpiringSoon)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (item.isExpired || item.isExpiringSoon)
                                      Icon(Icons.event_busy,
                                          color: item.isExpired
                                              ? Colors.red
                                              : Colors.orange,
                                          size: 18),
                                    if (item.isLowStock) ...[
                                      const SizedBox(width: 4),
                                      const Icon(Icons.warning_amber,
                                          color: Colors.orange, size: 18),
                                    ],
                                  ],
                                ),
                              ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _QtyButton(
                                  icon: Icons.remove,
                                  onTap: () => _adjustQuantity(item, -1),
                                ),
                                const SizedBox(width: 4),
                                _QtyButton(
                                  icon: Icons.add,
                                  onTap: () => _adjustQuantity(item, 1),
                                ),
                              ],
                            ),
                          ],
                        ),
                        onTap: () {
                          if (_selectionMode) {
                            _toggleSelected(item.id!);
                          } else {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => AddEditItemScreen(
                                  householdId: widget.householdId,
                                  existingItem: item,
                                ),
                              ),
                            );
                          }
                        },
                        onLongPress: () => _toggleSelected(item.id!),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QtyButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _QtyButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: const Color(0xFFE8F5E9),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, size: 16, color: const Color(0xFF4CAF50)),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        selectedColor: const Color(0xFF4CAF50),
        labelStyle: TextStyle(color: selected ? Colors.white : Colors.black87),
        onSelected: (_) => onTap(),
      ),
    );
  }
}
