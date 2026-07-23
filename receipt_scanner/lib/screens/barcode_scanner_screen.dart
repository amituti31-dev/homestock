import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/inventory_item.dart';
import '../services/barcode_lookup_service.dart';
import '../services/firestore_service.dart';
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
  final _lookup = BarcodeLookupService();
  bool _processing = false;

  @override
  void initState() {
    super.initState();
    _firestore = FirestoreService(widget.householdId);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_processing) return;
    final barcode = capture.barcodes.firstOrNull?.rawValue;
    if (barcode == null) return;

    setState(() => _processing = true);
    await _controller.stop();

    try {
      final existing = await _firestore.findItemByBarcode(barcode);
      if (!mounted) return;

      if (existing != null) {
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
    final product = await _lookup.lookup(barcode);

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddEditItemScreen(
          householdId: widget.householdId,
          prefillItem: InventoryItem(
            name: product?.name ?? '',
            barcode: barcode,
            source: 'barcode_scan',
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('סריקת ברקוד'),
          centerTitle: true,
          backgroundColor: const Color(0xFF4CAF50),
          foregroundColor: Colors.white,
          actions: [
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
                  border: Border.all(color: const Color(0xFF4CAF50), width: 3),
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
              bottom: 32,
              left: 0,
              right: 0,
              child: Text(
                'כוונו את המצלמה לברקוד המוצר',
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
