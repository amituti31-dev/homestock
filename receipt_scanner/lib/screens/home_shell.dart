import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/update_service.dart';
import 'add_edit_item_screen.dart';
import 'barcode_scanner_screen.dart';
import 'home_overview_screen.dart';
import 'inventory_list_screen.dart';
import 'receipt_scanner_screen.dart';
import 'settings_screen.dart';
import 'shopping_list_screen.dart';

class HomeShell extends StatefulWidget {
  final String householdId;
  final VoidCallback onHouseholdChanged;

  const HomeShell({
    super.key,
    required this.householdId,
    required this.onHouseholdChanged,
  });

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  final _updateService = UpdateService();

  @override
  void initState() {
    super.initState();
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

  late final List<Widget> _screens = [
    HomeOverviewScreen(householdId: widget.householdId),
    InventoryListScreen(householdId: widget.householdId),
    ShoppingListScreen(householdId: widget.householdId),
    SettingsScreen(
      householdId: widget.householdId,
      onHouseholdChanged: widget.onHouseholdChanged,
    ),
  ];

  void _openAddSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.receipt_long, color: Color(0xFF4CAF50)),
                title: const Text('סרוק קבלה'),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          ReceiptScannerScreen(householdId: widget.householdId),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.qr_code_scanner, color: Color(0xFF4CAF50)),
                title: const Text('סרוק ברקוד'),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          BarcodeScannerScreen(householdId: widget.householdId),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit, color: Color(0xFF4CAF50)),
                title: const Text('הוסף פריט ידנית'),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          AddEditItemScreen(householdId: widget.householdId),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      floatingActionButton: FloatingActionButton(
        heroTag: 'home_shell_fab',
        onPressed: _openAddSheet,
        backgroundColor: const Color(0xFF4CAF50),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            Expanded(
              child: _NavButton(
                icon: Icons.home,
                label: 'בית',
                selected: _index == 0,
                onTap: () => setState(() => _index = 0),
              ),
            ),
            Expanded(
              child: _NavButton(
                icon: Icons.inventory_2,
                label: 'מלאי',
                selected: _index == 1,
                onTap: () => setState(() => _index = 1),
              ),
            ),
            const SizedBox(width: 40),
            Expanded(
              child: _NavButton(
                icon: Icons.shopping_cart,
                label: 'קניות',
                selected: _index == 2,
                onTap: () => setState(() => _index = 2),
              ),
            ),
            Expanded(
              child: _NavButton(
                icon: Icons.settings,
                label: 'הגדרות',
                selected: _index == 3,
                onTap: () => setState(() => _index = 3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? const Color(0xFF4CAF50) : Colors.grey;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
