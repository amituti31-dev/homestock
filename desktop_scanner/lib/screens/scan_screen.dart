import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/inventory_category.dart';
import '../models/inventory_item.dart';
import '../services/category_classifier.dart';
import '../services/firestore_service.dart';
import '../services/product_index_service.dart';
import '../services/product_resolver.dart';
import '../services/update_service.dart';
import 'edit_item_dialog.dart';

/// Result of one scan, kept in memory for the session's activity list.
class ScanEvent {
  ScanEvent({
    required this.barcode,
    required this.item,
    required this.status,
    this.imageUrl,
    this.message,
  });

  final String barcode;
  final InventoryItem item;
  final ScanStatus status;
  final String? imageUrl;
  final String? message;
}

enum ScanStatus {
  /// New product, identified by one of the lookup sources.
  added,

  /// New product, but no source recognised the barcode.
  addedUnidentified,

  /// Barcode already in the inventory — quantity was bumped instead.
  incremented,

  /// Consume mode: quantity was bumped down by one.
  decremented,

  /// Consume mode: was down to the last unit, so the item was deleted.
  removed,

  /// Consume mode: barcode isn't in the inventory, so there's nothing to
  /// take off — unlike add mode, this doesn't create anything.
  notInInventory,

  failed,
}

/// The single screen of the desktop app: a permanently focused input that
/// catches the USB scanner's keystrokes, plus a log of what it did.
///
/// The scanner is an HID keyboard-wedge device — it types the digits and
/// presses Enter — so no driver or SDK is involved, only a focused TextField.
class ScanScreen extends StatefulWidget {
  const ScanScreen({
    super.key,
    required this.householdId,
    required this.firestore,
    required this.onUnlink,
  });

  final String householdId;
  final FirestoreService firestore;
  final Future<void> Function() onUnlink;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _index = ProductIndexService();
  late final _resolver = ProductResolver(index: _index);
  final _barcodeController = TextEditingController();
  final _barcodeFocus = FocusNode();

  final _updateService = UpdateService();
  final List<ScanEvent> _events = [];
  bool _busy = false;
  bool _refreshingIndex = false;
  String _householdName = '';

  /// Most scans are consuming something already in the house, not buying
  /// new — so a toggle switches what a scan *does*, with the whole input
  /// area tinted red/green so the current mode is unmistakable at a glance.
  bool _consumeMode = false;

  @override
  void initState() {
    super.initState();
    _loadHouseholdName();
    _loadIndex();
    _checkForUpdate();
  }

  Future<void> _checkForUpdate() async {
    final update = await _updateService.checkForUpdate();
    if (!mounted || update == null) return;

    ScaffoldMessenger.of(context).showMaterialBanner(
      MaterialBanner(
        content: Text('גרסה חדשה זמינה (${update.version})'),
        actions: [
          TextButton(
            onPressed: () {
              launchUrl(Uri.parse(update.downloadUrl),
                  mode: LaunchMode.externalApplication);
            },
            child: const Text('הורדה'),
          ),
          TextButton(
            onPressed: () =>
                ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
            child: const Text('סגירה'),
          ),
        ],
      ),
    );
  }

  /// Loads the cached price index and refreshes it in the background when it
  /// has gone stale. Scanning works throughout — a missing index only means
  /// falling back to Open Food Facts.
  Future<void> _loadIndex() async {
    await _index.load();
    if (mounted) setState(() {});
    if (_index.isStale) await _refreshIndex(silent: true);
  }

  Future<void> _refreshIndex({bool silent = false}) async {
    if (_refreshingIndex) return;
    setState(() => _refreshingIndex = true);
    try {
      final count = await _index.refresh();
      if (mounted && !silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('מדד המוצרים עודכן — $count מוצרים')),
        );
      }
    } catch (e) {
      if (mounted && !silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('עדכון המדד נכשל: ${e.toString().replaceFirst('Exception: ', '')}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _refreshingIndex = false);
        _refocus();
      }
    }
  }

  @override
  void dispose() {
    _barcodeController.dispose();
    _barcodeFocus.dispose();
    super.dispose();
  }

  Future<void> _loadHouseholdName() async {
    try {
      final fields = await widget.firestore.getHousehold(widget.householdId);
      if (mounted) {
        setState(() => _householdName = widget.firestore.householdName(fields));
      }
    } catch (_) {
      // A missing name is cosmetic; scanning still works.
    }
  }

  /// Returning focus after every interaction is what makes the scanner "just
  /// work" — a stray click elsewhere would otherwise swallow the next scan.
  void _refocus() => _barcodeFocus.requestFocus();

  Future<void> _handleScan(String raw) async {
    final barcode = raw.trim();
    _barcodeController.clear();
    _refocus();
    if (barcode.isEmpty || _busy) return;

    setState(() => _busy = true);
    try {
      final existing =
          await widget.firestore.findItemByBarcode(widget.householdId, barcode);

      if (_consumeMode) {
        await _handleConsumeScan(barcode, existing);
        return;
      }

      if (existing != null) {
        // The server computes the new quantity; trust it over a local guess.
        existing.quantity = await widget.firestore
            .incrementQuantity(widget.householdId, existing.id!, 1);
        _log(ScanEvent(
          barcode: barcode,
          item: existing,
          status: ScanStatus.incremented,
          imageUrl: existing.photoUrl,
        ));
        return;
      }

      final product = await _resolver.resolve(barcode);
      final item = InventoryItem(
        name: product?.name ?? 'מוצר לא מזוהה',
        category: product == null
            ? InventoryCategory.food
            : CategoryClassifier.classify(product.name),
        barcode: barcode,
        photoUrl: product?.imageUrl,
        price: product?.price,
        unit: 'יח\'',
      );
      item.id = await widget.firestore.addItem(widget.householdId, item);

      _log(ScanEvent(
        barcode: barcode,
        item: item,
        status: product == null
            ? ScanStatus.addedUnidentified
            : ScanStatus.added,
        imageUrl: product?.imageUrl,
        message: product?.sourceLabel,
      ));
    } catch (e) {
      _log(ScanEvent(
        barcode: barcode,
        item: InventoryItem(name: 'שגיאה', barcode: barcode),
        status: ScanStatus.failed,
        message: e.toString().replaceFirst('Exception: ', ''),
      ));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _refocus();
      }
    }
  }

  /// Consume mode: bumps the quantity down by one, or deletes the item once
  /// it's down to the last one — no confirmation, unlike the activity list's
  /// remove button, since the whole point is a fast scan-to-consume loop.
  /// A barcode with nothing in the inventory isn't an error, just a no-op:
  /// there's nothing to take off.
  Future<void> _handleConsumeScan(String barcode, InventoryItem? existing) async {
    if (existing == null) {
      _log(ScanEvent(
        barcode: barcode,
        item: InventoryItem(name: 'לא נמצא במלאי', barcode: barcode),
        status: ScanStatus.notInInventory,
      ));
      return;
    }

    if (existing.quantity <= 1) {
      await widget.firestore.deleteItem(widget.householdId, existing.id!);
      _log(ScanEvent(
        barcode: barcode,
        item: existing,
        status: ScanStatus.removed,
        imageUrl: existing.photoUrl,
      ));
    } else {
      existing.quantity = await widget.firestore
          .incrementQuantity(widget.householdId, existing.id!, -1);
      _log(ScanEvent(
        barcode: barcode,
        item: existing,
        status: ScanStatus.decremented,
        imageUrl: existing.photoUrl,
      ));
    }
  }

  void _log(ScanEvent event) {
    if (!mounted) return;
    setState(() => _events.insert(0, event));
  }

  Future<void> _edit(ScanEvent event) async {
    final updated = await showDialog<InventoryItem>(
      context: context,
      builder: (_) => EditItemDialog(item: event.item),
    );
    _refocus();
    if (updated == null) return;

    try {
      await widget.firestore.updateItem(widget.householdId, updated);
      setState(() {}); // The dialog mutated the item in place.
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('עדכון נכשל: ${e.toString().replaceFirst('Exception: ', '')}'),
        ));
      }
    }
  }

  /// Removes one unit of the scanned item — or, once it's down to the last
  /// one, the item itself. Mirrors the "הורד 1" flow on the phone: quantity
  /// never goes below zero, so at 1 unit the action is a delete, not a
  /// decrement to 0.
  Future<void> _removeUnit(ScanEvent event) async {
    final itemId = event.item.id;
    if (itemId == null) return;

    final willDelete = event.item.quantity <= 1;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('הסרה מהמלאי'),
        content: Text(willDelete
            ? '${event.item.name} יימחק לגמרי מהמלאי.'
            : 'הכמות של ${event.item.name} תרד ביחידה אחת (מ-${event.item.quantity.toStringAsFixed(0)}).'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('ביטול')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('הסר')),
        ],
      ),
    );
    _refocus();
    if (confirmed != true) return;

    try {
      if (willDelete) {
        await widget.firestore.deleteItem(widget.householdId, itemId);
        if (mounted) setState(() => _events.remove(event));
      } else {
        final newQuantity = await widget.firestore
            .incrementQuantity(widget.householdId, itemId, -1);
        if (mounted) setState(() => event.item.quantity = newQuantity);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('ההסרה נכשלה: ${e.toString().replaceFirst('Exception: ', '')}'),
        ));
      }
    }
  }

  Future<void> _confirmUnlink() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ניתוק מהבית'),
        content: const Text(
            'המוצרים שכבר נסרקו יישארו במלאי. תצטרך להזין את קוד הבית שוב כדי לסרוק.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('ביטול')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('נתק')),
        ],
      ),
    );
    if (confirmed == true) await widget.onUnlink();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_householdName.isEmpty ? 'סורק ברקודים' : 'סורק ברקודים · $_householdName'),
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        actions: [
          _IndexStatus(
            index: _index,
            refreshing: _refreshingIndex,
            onRefresh: _refreshIndex,
          ),
          IconButton(
            onPressed: _confirmUnlink,
            icon: const Icon(Icons.link_off),
            tooltip: 'ניתוק מהבית',
          ),
        ],
      ),
      // A tap anywhere hands focus back to the scanner input.
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _refocus,
        child: Column(
          children: [
            _ScannerInput(
              controller: _barcodeController,
              focusNode: _barcodeFocus,
              busy: _busy,
              consumeMode: _consumeMode,
              onModeChanged: (v) => setState(() {
                _consumeMode = v;
                _refocus();
              }),
              onSubmitted: _handleScan,
            ),
            const Divider(height: 1),
            Expanded(
              child: _events.isEmpty
                  ? const _EmptyState()
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _events.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, i) => _EventTile(
                        event: _events[i],
                        onEdit: () => _edit(_events[i]),
                        onRemove: () => _removeUnit(_events[i]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows how many products the local index holds and how old it is, with a
/// manual refresh. Worth surfacing: it is the difference between a scan being
/// named automatically and landing as 'מוצר לא מזוהה'.
class _IndexStatus extends StatelessWidget {
  const _IndexStatus({
    required this.index,
    required this.refreshing,
    required this.onRefresh,
  });

  final ProductIndexService index;
  final bool refreshing;
  final Future<void> Function() onRefresh;

  String get _tooltip {
    if (refreshing) return 'מעדכן את מדד המוצרים...';
    if (index.size == 0) return 'מדד המוצרים ריק — לחץ לעדכון';
    final days = DateTime.now().difference(index.updatedAt!).inDays;
    final age = days == 0 ? 'עודכן היום' : 'עודכן לפני $days ימים';
    return '${index.size} מוצרים במדד המקומי · $age · לחץ לעדכון';
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: _tooltip,
      child: TextButton.icon(
        onPressed: refreshing ? null : onRefresh,
        icon: refreshing
            ? const SizedBox(
                width: 14, height: 14,
                child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(index.size == 0 ? Icons.cloud_off : Icons.storage, size: 18),
        label: Text(index.size == 0 ? 'אין מדד' : '${index.size}'),
      ),
    );
  }
}

class _ScannerInput extends StatelessWidget {
  const _ScannerInput({
    required this.controller,
    required this.focusNode,
    required this.busy,
    required this.consumeMode,
    required this.onModeChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool busy;
  final bool consumeMode;
  final ValueChanged<bool> onModeChanged;
  final ValueChanged<String> onSubmitted;

  static const _addColor = Color(0xFF4CAF50);
  static const _consumeColor = Color(0xFFE53935);

  @override
  Widget build(BuildContext context) {
    final modeColor = consumeMode ? _consumeColor : _addColor;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      color: modeColor.withValues(alpha: 0.08),
      child: Column(
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  label: Text('הוספה למלאי'),
                  icon: Icon(Icons.add_shopping_cart),
                ),
                ButtonSegment(
                  value: true,
                  label: Text('צריכה מהמלאי'),
                  icon: Icon(Icons.remove_shopping_cart),
                ),
              ],
              selected: {consumeMode},
              onSelectionChanged: (s) => onModeChanged(s.first),
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: modeColor,
                selectedForegroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Icon(
            busy ? Icons.hourglass_top : Icons.qr_code_scanner,
            size: 48,
            color: modeColor,
          ),
          const SizedBox(height: 12),
          Text(
            busy
                ? 'מעבד...'
                : (consumeMode ? 'סרוק מוצר לצריכה' : 'סרוק מוצר להוספה'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 4),
          Text(
            consumeMode
                ? 'הכמות תרד ביחידה אחת, או שהמוצר יימחק אם זו היחידה האחרונה.'
                : 'הסורק מקליד את הברקוד לחלון הזה. אפשר גם להקליד ידנית וללחוץ Enter.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              autofocus: true,
              textAlign: TextAlign.center,
              textDirection: TextDirection.ltr,
              style: const TextStyle(fontSize: 20, letterSpacing: 2),
              // Scanners emit digits; blocking everything else keeps stray
              // keystrokes out of the field.
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onSubmitted: onSubmitted,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'ברקוד',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inventory_2_outlined,
              size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text('עדיין לא נסרקו מוצרים',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text('כל מוצר שתסרוק ייכנס ישירות למלאי הבית'),
        ],
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({
    required this.event,
    required this.onEdit,
    required this.onRemove,
  });

  final ScanEvent event;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  ({Color color, IconData icon, String label}) get _style {
    switch (event.status) {
      case ScanStatus.added:
        return (
          color: Colors.green,
          icon: Icons.check_circle,
          label: 'נוסף למלאי · זוהה מ${event.message == null ? '' : '־${event.message}'}'
        );
      case ScanStatus.addedUnidentified:
        return (
          color: Colors.orange,
          icon: Icons.help_outline,
          label: 'נוסף — אף מקור לא זיהה את הברקוד, תן לו שם'
        );
      case ScanStatus.incremented:
        return (
          color: Colors.blue,
          icon: Icons.add_circle,
          label: 'כבר במלאי — הכמות עודכנה ל-${event.item.quantity.toStringAsFixed(0)}'
        );
      case ScanStatus.decremented:
        return (
          color: Colors.deepOrange,
          icon: Icons.remove_circle,
          label: 'ירד מהמלאי — הכמות עודכנה ל-${event.item.quantity.toStringAsFixed(0)}'
        );
      case ScanStatus.removed:
        return (
          color: Colors.red,
          icon: Icons.delete,
          label: 'האחרון — הוסר לגמרי מהמלאי'
        );
      case ScanStatus.notInInventory:
        return (
          color: Colors.grey,
          icon: Icons.search_off,
          label: 'לא נמצא במלאי — אין מה להוריד'
        );
      case ScanStatus.failed:
        return (color: Colors.red, icon: Icons.error, label: event.message ?? 'שגיאה');
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = _style;
    // No item to act on: creation failed, the barcode wasn't in the
    // inventory to begin with, or it was just deleted by this very scan.
    final noActions = event.item.id == null || event.status == ScanStatus.removed;

    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: SizedBox(
          width: 48,
          height: 48,
          child: event.imageUrl != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.network(
                    event.imageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        Icon(style.icon, color: style.color),
                  ),
                )
              : Icon(style.icon, color: style.color, size: 32),
        ),
        title: Text(event.item.name,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(style.label, style: TextStyle(color: style.color)),
            Text(
              event.barcode,
              textDirection: TextDirection.ltr,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        trailing: noActions
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: onRemove,
                    icon: const Icon(Icons.remove_circle_outline),
                    tooltip: event.item.quantity <= 1
                        ? 'מחיקה מהמלאי'
                        : 'הסרת יחידה אחת',
                  ),
                  IconButton(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit),
                    tooltip: 'עריכה',
                  ),
                ],
              ),
      ),
    );
  }
}
