import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/gemini_service.dart';
import 'items_confirmation_screen.dart';

class ReceiptScannerScreen extends StatefulWidget {
  final String householdId;

  const ReceiptScannerScreen({super.key, required this.householdId});

  @override
  State<ReceiptScannerScreen> createState() => _ReceiptScannerScreenState();
}

class _ReceiptScannerScreenState extends State<ReceiptScannerScreen> {
  final _picker = ImagePicker();
  final _gemini = GeminiService();

  bool _loading = false;
  String _status = '';

  Future<void> _scanReceipt(ImageSource source) async {
    final picked = await _picker.pickImage(
      source: source,
      imageQuality: 90,
    );
    if (picked == null) return;

    setState(() {
      _loading = true;
      _status = 'מנתח את הקבלה עם AI...';
    });

    try {
      final file = File(picked.path);
      final items = await _gemini.parseReceiptImage(file);

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ItemsConfirmationScreen(
            items: items,
            householdId: widget.householdId,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('שגיאה: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('סריקת קבלה'),
        centerTitle: true,
        backgroundColor: const Color(0xFF4CAF50),
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(color: Color(0xFF4CAF50)),
                  const SizedBox(height: 20),
                  Text(_status, style: const TextStyle(fontSize: 16)),
                ],
              ),
            )
          : Directionality(
              textDirection: TextDirection.rtl,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.receipt_long,
                        size: 100, color: Color(0xFF4CAF50)),
                    const SizedBox(height: 24),
                    const Text(
                      'סרקו את הקבלה',
                      style: TextStyle(
                          fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'המוצרים יתווספו אוטומטית למלאי',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                    const SizedBox(height: 48),
                    _ActionButton(
                      icon: Icons.camera_alt,
                      label: 'צלם קבלה',
                      onTap: () => _scanReceipt(ImageSource.camera),
                    ),
                    const SizedBox(height: 16),
                    _ActionButton(
                      icon: Icons.photo_library,
                      label: 'בחר מהגלריה',
                      onTap: () => _scanReceipt(ImageSource.gallery),
                      outlined: true,
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool outlined;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: outlined
          ? OutlinedButton.icon(
              onPressed: onTap,
              icon: Icon(icon),
              label: Text(label, style: const TextStyle(fontSize: 16)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF4CAF50)),
                foregroundColor: const Color(0xFF4CAF50),
              ),
            )
          : ElevatedButton.icon(
              onPressed: onTap,
              icon: Icon(icon),
              label: Text(label, style: const TextStyle(fontSize: 16)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4CAF50),
                foregroundColor: Colors.white,
              ),
            ),
    );
  }
}
