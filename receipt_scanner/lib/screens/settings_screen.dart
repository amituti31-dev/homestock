import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/auth_service.dart';
import '../services/excel_export_service.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';

class SettingsScreen extends StatefulWidget {
  final String householdId;
  final VoidCallback onHouseholdChanged;

  const SettingsScreen({
    super.key,
    required this.householdId,
    required this.onHouseholdChanged,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _notifications = NotificationService();
  final _auth = AuthService();
  final _excelExport = ExcelExportService();
  late final FirestoreService _firestore;
  int _leadDays = 3;
  bool _loading = true;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _firestore = FirestoreService(widget.householdId);
    _loadLeadDays();
  }

  Future<void> _exportToExcel() async {
    setState(() => _exporting = true);
    try {
      final items = await _firestore.streamItems().first;
      if (items.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('אין פריטים לייצוא')),
        );
        return;
      }
      await _excelExport.exportAndShare(items);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('שגיאה בייצוא: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _loadLeadDays() async {
    final days = await _notifications.getLeadDays();
    if (!mounted) return;
    setState(() {
      _leadDays = days;
      _loading = false;
    });
  }

  Future<void> _updateLeadDays(int days) async {
    setState(() => _leadDays = days);
    await _notifications.setLeadDays(days);
  }

  Future<void> _signInWithGoogle() async {
    try {
      await _auth.signInWithGoogle();
      widget.onHouseholdChanged();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('שגיאה בהתחברות: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('התנתקות'),
          content: const Text('תתחיל משק בית חדש וריק. להמשיך?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('ביטול')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('התנתק', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    await _auth.signOut();
    widget.onHouseholdChanged();
  }

  Future<void> _renameHousehold(String currentName) async {
    final controller = TextEditingController(text: currentName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('שינוי שם משק הבית'),
          content: TextField(controller: controller, autofocus: true),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('ביטול')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4CAF50),
                  foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('שמור'),
            ),
          ],
        ),
      ),
    );
    if (newName == null || newName.isEmpty) return;
    await _auth.renameHousehold(widget.householdId, newName);
  }

  Future<void> _joinHouseholdDialog() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('הצטרפות למשק בית'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'הזן את קוד ההזמנה שקיבלת. שים לב: תעזוב את משק הבית הנוכחי שלך.',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                decoration: const InputDecoration(labelText: 'קוד הזמנה'),
                autofocus: true,
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('ביטול')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4CAF50),
                  foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('הצטרף'),
            ),
          ],
        ),
      ),
    );
    if (code == null || code.isEmpty) return;

    try {
      await _auth.joinHousehold(code);
      widget.onHouseholdChanged();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('שגיאה: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _leaveHousehold() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('עזיבת משק בית'),
          content: const Text('תעבור למשק בית חדש וריק משלך. להמשיך?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('ביטול')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('עזוב', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    await _auth.leaveHousehold(widget.householdId);
    widget.onHouseholdChanged();
  }

  void _copyInviteCode() {
    Clipboard.setData(ClipboardData(text: widget.householdId));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('קוד ההזמנה הועתק'),
        backgroundColor: Color(0xFF4CAF50),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('הגדרות'),
          centerTitle: true,
          backgroundColor: const Color(0xFF4CAF50),
          foregroundColor: Colors.white,
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text('חשבון',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Card(
                    child: _auth.isAnonymous
                        ? ListTile(
                            leading: const Icon(Icons.login, color: Color(0xFF4CAF50)),
                            title: const Text('התחבר עם Google'),
                            subtitle: const Text('כדי לשתף את המלאי עם המשפחה'),
                            onTap: _signInWithGoogle,
                          )
                        : ListTile(
                            leading: const Icon(Icons.account_circle,
                                color: Color(0xFF4CAF50)),
                            title: Text(_auth.displayName ?? _auth.email ?? 'מחובר'),
                            subtitle: Text(_auth.email ?? ''),
                            trailing: TextButton(
                              onPressed: _signOut,
                              child: const Text('התנתק'),
                            ),
                          ),
                  ),
                  const SizedBox(height: 24),
                  const Text('משק בית משותף',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  StreamBuilder<DocumentSnapshot>(
                    stream: _firestore.streamHousehold(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData || !snapshot.data!.exists) {
                        return const SizedBox();
                      }
                      final data = snapshot.data!.data() as Map<String, dynamic>;
                      final name = data['name'] ?? 'הבית שלי';
                      final members = List<String>.from(data['members'] ?? []);
                      final profiles = Map<String, dynamic>.from(
                          data['memberProfiles'] ?? {});

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Card(
                            child: ListTile(
                              title: Text(name,
                                  style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text('${members.length} חברים'),
                              trailing: IconButton(
                                icon: const Icon(Icons.edit, size: 20),
                                onPressed: () => _renameHousehold(name),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Card(
                            child: ListTile(
                              leading: const Icon(Icons.qr_code, color: Color(0xFF4CAF50)),
                              title: const Text('קוד הזמנה'),
                              subtitle: Text(widget.householdId,
                                  style: const TextStyle(fontSize: 12)),
                              trailing: IconButton(
                                icon: const Icon(Icons.copy, size: 20),
                                onPressed: _copyInviteCode,
                              ),
                            ),
                          ),
                          if (members.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Card(
                              child: Column(
                                children: members.map((uid) {
                                  final profile = profiles[uid] as Map<String, dynamic>?;
                                  return ListTile(
                                    leading: const Icon(Icons.person_outline),
                                    title: Text(profile?['displayName'] ?? 'אורח'),
                                    subtitle: profile?['email'] != null
                                        ? Text(profile!['email'])
                                        : null,
                                  );
                                }).toList(),
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: _joinHouseholdDialog,
                            icon: const Icon(Icons.group_add),
                            label: const Text('הצטרף למשק בית עם קוד'),
                          ),
                          if (members.length > 1) ...[
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: _leaveHousehold,
                              icon: const Icon(Icons.exit_to_app, color: Colors.red),
                              label: const Text('עזוב משק בית',
                                  style: TextStyle(color: Colors.red)),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  const Text('תזכורות תפוגה',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(
                    'כמה ימים לפני שהמוצר פג תוקף לקבל התראה',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: RadioGroup<int>(
                      groupValue: _leadDays,
                      onChanged: (v) => _updateLeadDays(v ?? _leadDays),
                      child: Column(
                        children: [1, 3, 5, 7, 14].map((days) {
                          return RadioListTile<int>(
                            title: Text('$days ימים לפני'),
                            value: days,
                            activeColor: const Color(0xFF4CAF50),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text('גיבוי נתונים',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(
                    'ייצוא כל המלאי לקובץ Excel לשיתוף או גיבוי',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: ListTile(
                      leading: _exporting
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Color(0xFF4CAF50)),
                            )
                          : const Icon(Icons.file_download, color: Color(0xFF4CAF50)),
                      title: const Text('ייצוא מלאי ל-Excel'),
                      onTap: _exporting ? null : _exportToExcel,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
