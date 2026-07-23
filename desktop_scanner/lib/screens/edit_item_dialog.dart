import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/inventory_category.dart';
import '../models/inventory_item.dart';
import '../models/storage_location.dart';

/// Fixes up an item right after it was scanned — mainly to name products Open
/// Food Facts didn't recognise, and to file them under a storage location.
///
/// Mutates the item in place and pops it on save, or pops null on cancel.
class EditItemDialog extends StatefulWidget {
  const EditItemDialog({super.key, required this.item});

  final InventoryItem item;

  @override
  State<EditItemDialog> createState() => _EditItemDialogState();
}

class _EditItemDialogState extends State<EditItemDialog> {
  late final _nameController = TextEditingController(text: widget.item.name);
  late final _unitController = TextEditingController(text: widget.item.unit);
  late final _quantityController =
      TextEditingController(text: _formatNumber(widget.item.quantity));
  late final _minQuantityController =
      TextEditingController(text: _formatNumber(widget.item.minQuantity));
  late final _customLocationController =
      TextEditingController(text: widget.item.customLocationName ?? '');

  late InventoryCategory _category = widget.item.category;
  late StorageLocation? _location = widget.item.location;
  late DateTime? _expiryDate = widget.item.expiryDate;

  static String _formatNumber(double value) =>
      value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toString();

  @override
  void dispose() {
    _nameController.dispose();
    _unitController.dispose();
    _quantityController.dispose();
    _minQuantityController.dispose();
    _customLocationController.dispose();
    super.dispose();
  }

  Future<void> _pickExpiryDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiryDate ?? now.add(const Duration(days: 7)),
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365 * 10)),
    );
    if (picked != null) setState(() => _expiryDate = picked);
  }

  void _save() {
    final item = widget.item;
    item.name = _nameController.text.trim().isEmpty
        ? 'מוצר לא מזוהה'
        : _nameController.text.trim();
    item.category = _category;
    item.quantity = double.tryParse(_quantityController.text) ?? item.quantity;
    item.unit = _unitController.text.trim().isEmpty
        ? 'יח\''
        : _unitController.text.trim();
    item.minQuantity =
        double.tryParse(_minQuantityController.text) ?? item.minQuantity;
    item.location = _location;
    item.customLocationName = _customLocationController.text.trim();
    item.expiryDate = _expiryDate;
    Navigator.pop(context, item);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('עריכת מוצר'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'שם המוצר',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<InventoryCategory>(
                initialValue: _category,
                decoration: const InputDecoration(
                  labelText: 'קטגוריה',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final category in InventoryCategory.values)
                    DropdownMenuItem(
                      value: category,
                      child: Row(
                        children: [
                          Icon(category.icon, size: 18),
                          const SizedBox(width: 8),
                          Text(category.label),
                        ],
                      ),
                    ),
                ],
                onChanged: (value) =>
                    setState(() => _category = value ?? _category),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _quantityController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'כמות',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _unitController,
                      decoration: const InputDecoration(
                        labelText: 'יחידה',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _minQuantityController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'מינימום',
                        border: OutlineInputBorder(),
                        helperText: 'להתראה',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<StorageLocation?>(
                initialValue: _location,
                decoration: const InputDecoration(
                  labelText: 'מיקום אחסון',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('ללא')),
                  for (final location in StorageLocation.values)
                    DropdownMenuItem(
                      value: location,
                      child: Row(
                        children: [
                          Icon(location.icon, size: 18),
                          const SizedBox(width: 8),
                          Text(location.label),
                        ],
                      ),
                    ),
                ],
                onChanged: (value) => setState(() => _location = value),
              ),
              if (_location == StorageLocation.other) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _customLocationController,
                  decoration: const InputDecoration(
                    labelText: 'שם המיקום',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event),
                title: Text(_expiryDate == null
                    ? 'ללא תאריך תפוגה'
                    : 'תפוגה: ${DateFormat('dd/MM/yyyy').format(_expiryDate!)}'),
                trailing: _expiryDate == null
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() => _expiryDate = null),
                      ),
                onTap: _pickExpiryDate,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('ביטול')),
        FilledButton(onPressed: _save, child: const Text('שמור')),
      ],
    );
  }
}
