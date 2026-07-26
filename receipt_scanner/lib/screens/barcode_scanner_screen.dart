import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/inventory_category.dart';
import '../models/inventory_item.dart';
import '../services/category_classifier.dart';
import '../services/firestore_service.dart';
import '../services/gemini_service.dart';
import '../services/product_index_service.dart';
import '../services/product_resolver.dart';
import 'add_edit_item_screen.dart';

class BarcodeScannerScreen extends StatefulWidget {
  final String householdId;

  const BarcodeScannerScreen({super.key, required this.householdId});

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  final _controller = MobileScannerController();
  late final FirestoreService _firestore;
  final _index = ProductIndexService();
  late final _resolver = ProductResolver(index: _index);
  final _gemini = GeminiService();
  bool _processing = false;

  /// Most scans are using something up, not buying it — this switches what a
  /// scan *does*: in consume mode it bumps the quantity straight down (or
  /// deletes at the last unit) with no sheet or confirmation, for a fast
  /// scan-to-consume loop. The tinted app bar and frame are what stop you
  /// from doing it in the wrong mode by mistake.
  bool _consumeMode = false;

  static const _addColor = Color(0xFF4CAF50);
  static const _consumeColor = Color(0xFFE53935);
  Color get _modeColor => _consumeMode ? _consumeColor : _addColor;

  @override
  void initState() {
    super.initState();
    _firestore = FirestoreService(widget.householdId);
    _loadIndex();
  }

  /// Loads the cached local price index and refreshes it in the background
  /// when it's gone stale. Scanning works throughout — a missing index just
  /// means falling back to Open Food Facts, same as before this existed.
  Future<void> _loadIndex() async {
    await _index.load();
    if (_index.isStale) {
      try {
        await _index.refresh();
      } catch (_) {
        // Best-effort — see BarcodeLookupService.
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    final barcode = capture.barcodes.firstOrNull?.rawValue;
    if (barcode == null) return;
    await _handleBarcode(barcode);
  }

  /// Shared by both the camera detector and manual entry, so a typed-in
  /// barcode goes through the exact same lookup/classify/consume-mode flow
  /// as a scanned one.
  Future<void> _handleBarcode(String barcode) async {
    if (_processing) return;
    setState(() => _processing = true);
    await _controller.stop();

    try {
      final existing = await _firestore.findItemByBarcode(barcode);
      if (!mounted) return;

      if (_consumeMode) {
        await _handleConsumeScan(existing);
      } else if (existing != null) {
        await _showExistingItemSheet(existing);
      } else {
        await _showNewItemFlow(barcode);
      }
    } finally {
      if (mounted) {
        setState(() => _processing = false);
        await _controller.start();
      }
    }
  }

  Future<void> _showManualEntryDialog() async {
    final controller = TextEditingController();
    final barcode = await showDialog<String>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('הזנת ברקוד ידנית'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(hintText: 'מספר ברקוד'),
            onSubmitted: (value) => Navigator.pop(ctx, value.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('ביטול'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('אישור'),
            ),
          ],
        ),
      ),
    );
    if (barcode == null || barcode.isEmpty) return;
    await _handleBarcode(barcode);
  }

  /// Consume mode: bumps the quantity down by one, or deletes the item once
  /// it's down to the last one. A barcode with nothing in the inventory is a
  /// no-op, not a create — there's nothing to take off.
  Future<void> _handleConsumeScan(InventoryItem? existing) async {
    if (existing == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('לא נמצא במלאי — אין מה להוריד')),
      );
      return;
    }

    if (existing.quantity <= 1) {
      // Ran out entirely — suggest buying more before the record disappears.
      await _firestore.addLowStockToShoppingList([existing]);
      await _firestore.deleteItem(existing.id!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${existing.name} נגמר — נוסף לרשימת הקניות')),
        );
      }
    } else {
      await _firestore.incrementQuantity(existing.id!, -1);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${existing.name} — הכמות ירדה ל-${existing.quantity - 1}')),
        );
      }
    }
  }

  Future<void> _showExistingItemSheet(InventoryItem item) async {
    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('כמות נוכחית: ${item.quantity} ${item.unit}',
                    style: TextStyle(color: Colors.grey.shade600)),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        // A product can't go below zero units.
                        onPressed: item.quantity <= 0
                            ? null
                            : () async {
                                await _firestore.incrementQuantity(item.id!, -1);
                                if (item.quantity <= 1) {
                                  // Ran out entirely — suggest buying more.
                                  await _firestore.addLowStockToShoppingList([item]);
                                }
                                if (ctx.mounted) Navigator.pop(ctx);
                              },
                        icon: const Icon(Icons.remove),
                        label: const Text('הורד 1'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4CAF50),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () async {
                          await _firestore.incrementQuantity(item.id!, 1);
                          if (ctx.mounted) Navigator.pop(ctx);
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('הוסף 1'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AddEditItemScreen(
                          householdId: widget.householdId,
                          existingItem: item,
                        ),
                      ),
                    );
                  },
                  child: const Text('ערוך פרטים מלאים'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showNewItemFlow(String barcode) async {
    final product = await _resolver.resolve(barcode);
    final category = product == null
        ? InventoryCategory.food
        : await _classify(product.name);

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddEditItemScreen(
          householdId: widget.householdId,
          prefillItem: InventoryItem(
            name: product?.name ?? '',
            category: category,
            barcode: barcode,
            photoUrl: product?.imageUrl,
            source: 'barcode_scan',
          ),
        ),
      ),
    );
  }

  /// AI classification first (handles cases the keyword list can't), falling
  /// back to the instant local [CategoryClassifier] whenever Gemini is
  /// unavailable, over quota, or times out — a scan must never hang waiting
  /// on the network.
  Future<InventoryCategory> _classify(String name) async {
    final aiCategory = await _gemini.classifyProduct(name);
    return aiCategory ?? CategoryClassifier.classify(name);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('סריקת ברקוד'),
          centerTitle: true,
          backgroundColor: _modeColor,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: const Icon(Icons.keyboard),
              tooltip: 'הזנת ברקוד ידנית',
              onPressed: _showManualEntryDialog,
            ),
            IconButton(
              icon: const Icon(Icons.flash_on),
              onPressed: () => _controller.toggleTorch(),
            ),
          ],
        ),
        body: Stack(
          children: [
            MobileScanner(controller: _controller, onDetect: _onDetect),
            Center(
              child: Container(
                width: 260,
                height: 160,
                decoration: BoxDecoration(
                  border: Border.all(color: _modeColor, width: 3),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            if (_processing)
              Container(
                color: Colors.black54,
                child: const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
            Positioned(
              top: 16,
              left: 16,
              right: 16,
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
                selected: {_consumeMode},
                onSelectionChanged: (s) => setState(() => _consumeMode = s.first),
                style: SegmentedButton.styleFrom(
                  backgroundColor: Colors.white,
                  selectedBackgroundColor: _modeColor,
                  selectedForegroundColor: Colors.white,
                ),
              ),
            ),
            Positioned(
              bottom: 32,
              left: 0,
              right: 0,
              child: Text(
                _consumeMode
                    ? 'כוונו את המצלמה לברקוד — הכמות תרד ביחידה אחת'
                    : 'כוונו את המצלמה לברקוד המוצר',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  shadows: [Shadow(blurRadius: 4, color: Colors.black.withValues(alpha: 0.7))],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
