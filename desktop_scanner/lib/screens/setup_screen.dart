import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart';
import '../services/firestore_service.dart';
import '../services/product_index_service.dart';

/// One-time linking of this machine to a household, using the household ID as
/// an invite code — the same code the mobile app's settings screen shows.
class SetupScreen extends StatefulWidget {
  const SetupScreen({
    super.key,
    required this.firestore,
    required this.onLinked,
  });

  final FirestoreService firestore;
  final void Function(String householdId) onLinked;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _link() async {
    final householdId = _controller.text.trim();
    if (householdId.isEmpty) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await widget.firestore.joinHousehold(householdId);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(householdIdKey, householdId);

      // Best-effort: seed the local barcode index from the maintainer's
      // pre-merged multi-chain dump, so this machine isn't limited to the
      // Shufersal-only weekly refresh. Setup succeeds either way.
      try {
        final index = ProductIndexService();
        await index.load();
        await index.downloadSeed();
      } catch (_) {}

      widget.onLinked(householdId);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.qr_code_scanner,
                    size: 64, color: Color(0xFF4CAF50)),
                const SizedBox(height: 24),
                Text('חיבור לבית',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(
                  'הזן את קוד הבית מהאפליקציה בנייד (הגדרות ← שיתוף הבית). '
                  'המוצרים שתסרוק כאן ייכנסו לאותו מלאי.',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _controller,
                  autofocus: true,
                  enabled: !_busy,
                  textDirection: TextDirection.ltr,
                  onSubmitted: (_) => _link(),
                  inputFormatters: [
                    FilteringTextInputFormatter.deny(RegExp(r'\s')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'קוד הבית',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.home),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error),
                      textAlign: TextAlign.center),
                ],
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _busy ? null : _link,
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.link),
                  label: Text(_busy ? 'מתחבר...' : 'התחבר'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
