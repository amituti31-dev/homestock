import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../models/inventory_category.dart';
import '../models/inventory_item.dart';
import '../models/storage_location.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';

class AddEditItemScreen extends StatefulWidget {
  final String householdId;
  final InventoryItem? existingItem;
  final InventoryItem? prefillItem;

  const AddEditItemScreen({
    super.key,
    required this.householdId,
    this.existingItem,
    this.prefillItem,
  });

  @override
  State<AddEditItemScreen> createState() => _AddEditItemScreenState();
}

class _AddEditItemScreenState extends State<AddEditItemScreen> {
  final _formKey = GlobalKey<FormState>();
  late final FirestoreService _firestore;
  final _notifications = NotificationService();

  late TextEditingController _nameController;
  late TextEditingController _quantityController;
  late TextEditingController _unitController;
  late TextEditingController _minQuantityController;
  late TextEditingController _customLocationController;
  late InventoryCategory _category;
  StorageLocation? _location;
  DateTime? _expiryDate;
  File? _newPhotoFile;
  String? _photoUrl;
  bool _saving = false;

  bool get _isEditing => widget.existingItem != null;

  @override
  void initState() {
    super.initState();
    _firestore = FirestoreService(widget.householdId);
    final item = widget.existingItem ?? widget.prefillItem;
    _nameController = TextEditingController(text: item?.name ?? '');
    _quantityController =
        TextEditingController(text: (item?.quantity ?? 1).toString());
    _unitController = TextEditingController(text: item?.unit ?? 'יח\'');
    _minQuantityController =
        TextEditingController(text: (item?.minQuantity ?? 0).toString());
    _customLocationController =
        TextEditingController(text: item?.customLocationName ?? '');
    _category = item?.category ?? InventoryCategory.food;
    _location = item?.location;
    _expiryDate = item?.expiryDate;
    _photoUrl = item?.photoUrl;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _quantityController.dispose();
    _unitController.dispose();
    _minQuantityController.dispose();
    _customLocationController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final picked =
        await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked != null) {
      setState(() => _newPhotoFile = File(picked.path));
    }
  }

  Future<void> _pickExpiryDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiryDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (picked != null) setState(() => _expiryDate = picked);
  }

  Future<String?> _uploadPhotoIfNeeded() async {
    if (_newPhotoFile == null) return _photoUrl;
    final ref = FirebaseStorage.instance.ref(
      'households/${widget.householdId}/items/${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    await ref.putFile(_newPhotoFile!);
    return ref.getDownloadURL();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final photoUrl = await _uploadPhotoIfNeeded();
      final item = InventoryItem(
        id: widget.existingItem?.id,
        name: _nameController.text.trim(),
        category: _category,
        quantity: double.tryParse(_quantityController.text) ?? 1,
        unit: _unitController.text.trim(),
        minQuantity: double.tryParse(_minQuantityController.text) ?? 0,
        expiryDate: _expiryDate,
        photoUrl: photoUrl,
        location: _location,
        customLocationName: _location == StorageLocation.other
            ? _customLocationController.text.trim()
            : null,
        barcode: widget.existingItem?.barcode ?? widget.prefillItem?.barcode,
        source: widget.existingItem?.source ??
            widget.prefillItem?.source ??
            'manual',
      );

      if (_isEditing) {
        await _firestore.updateItem(item);
        await _notifications.scheduleExpiryReminder(item);
      } else {
        final newId = await _firestore.addItem(item);
        await _notifications.scheduleExpiryReminder(InventoryItem(
          id: newId,
          name: item.name,
          category: item.category,
          quantity: item.quantity,
          unit: item.unit,
          expiryDate: item.expiryDate,
        ));
      }

      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('שגיאה בשמירה: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('מחיקת פריט'),
        content: Text('למחוק את "${_nameController.text}" מהמלאי?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: const Text('ביטול')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('מחק', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _firestore.deleteItem(widget.existingItem!.id!);
    await _notifications.cancelExpiryReminder(widget.existingItem!.id!);
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isEditing ? 'עריכת פריט' : 'פריט חדש'),
          centerTitle: true,
          backgroundColor: const Color(0xFF4CAF50),
          foregroundColor: Colors.white,
          actions: [
            if (_isEditing)
              IconButton(onPressed: _delete, icon: const Icon(Icons.delete)),
          ],
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Center(
                child: GestureDetector(
                  onTap: _pickPhoto,
                  child: CircleAvatar(
                    radius: 48,
                    backgroundColor: const Color(0xFFE8F5E9),
                    backgroundImage: _newPhotoFile != null
                        ? FileImage(_newPhotoFile!)
                        : (_photoUrl != null ? NetworkImage(_photoUrl!) : null)
                            as ImageProvider?,
                    child: _newPhotoFile == null && _photoUrl == null
                        ? const Icon(Icons.add_a_photo, color: Color(0xFF4CAF50), size: 32)
                        : null,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'שם המוצר'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'נדרש שם' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<InventoryCategory>(
                initialValue: _category,
                decoration: const InputDecoration(labelText: 'קטגוריה'),
                items: InventoryCategory.values
                    .map((c) => DropdownMenuItem(
                          value: c,
                          child: Row(
                            children: [
                              Icon(c.icon, size: 18, color: const Color(0xFF4CAF50)),
                              const SizedBox(width: 8),
                              Text(c.label),
                            ],
                          ),
                        ))
                    .toList(),
                onChanged: (c) => setState(() => _category = c ?? _category),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<StorageLocation?>(
                initialValue: _location,
                decoration: const InputDecoration(labelText: 'מיקום אחסון (אופציונלי)'),
                items: [
                  const DropdownMenuItem<StorageLocation?>(
                    value: null,
                    child: Text('ללא'),
                  ),
                  ...StorageLocation.values.map((l) => DropdownMenuItem(
                        value: l,
                        child: Row(
                          children: [
                            Icon(l.icon, size: 18, color: const Color(0xFF4CAF50)),
                            const SizedBox(width: 8),
                            Text(l.label),
                          ],
                        ),
                      )),
                ],
                onChanged: (l) => setState(() => _location = l),
              ),
              if (_location == StorageLocation.other) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _customLocationController,
                  decoration: const InputDecoration(labelText: 'שם המיקום'),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _quantityController,
                      decoration: const InputDecoration(labelText: 'כמות'),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _unitController,
                      decoration: const InputDecoration(labelText: 'יחידה'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _minQuantityController,
                decoration: const InputDecoration(
                  labelText: 'כמות מינימלית להתראה',
                  helperText: 'נקבל התראה כשהכמות יורדת לרמה זו',
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event, color: Color(0xFF4CAF50)),
                title: Text(
                  _expiryDate != null
                      ? 'תוקף: ${DateFormat('dd/MM/yyyy').format(_expiryDate!)}'
                      : 'הוספת תאריך תפוגה',
                ),
                trailing: _expiryDate != null
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() => _expiryDate = null),
                      )
                    : null,
                onTap: _pickExpiryDate,
              ),
              const SizedBox(height: 32),
              SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4CAF50),
                    foregroundColor: Colors.white,
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : Text(_isEditing ? 'שמור שינויים' : 'הוסף למלאי'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
