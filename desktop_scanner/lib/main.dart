import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/scan_screen.dart';
import 'screens/setup_screen.dart';
import 'services/auth_service.dart';
import 'services/firestore_service.dart';

const householdIdKey = 'household_id';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DesktopScannerApp());
}

class DesktopScannerApp extends StatelessWidget {
  const DesktopScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HomeStock סורק',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4CAF50)),
        useMaterial3: true,
      ),
      // The whole app is Hebrew and there is no localization layer to derive
      // this from, so the direction is forced at the root.
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child!,
      ),
      home: const _AppBootstrap(),
    );
  }
}

class _AppBootstrap extends StatefulWidget {
  const _AppBootstrap();

  @override
  State<_AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<_AppBootstrap> {
  final _auth = AuthService();
  late final _firestore = FirestoreService(_auth);

  late Future<String?> _bootFuture;

  @override
  void initState() {
    super.initState();
    _bootFuture = _boot();
  }

  /// Signs in (anonymously, cached across restarts) and returns the household
  /// this machine is linked to, or null when it hasn't been linked yet.
  Future<String?> _boot() async {
    await _auth.loadCachedUid();
    await _auth.idToken();
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(householdIdKey);
  }

  void _onLinked(String householdId) {
    setState(() {
      _bootFuture = Future.value(householdId);
    });
  }

  Future<void> _unlink() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(householdIdKey);
    setState(() {
      _bootFuture = Future.value(null);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _bootFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(
                child: CircularProgressIndicator(color: Color(0xFF4CAF50))),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
                    const SizedBox(height: 16),
                    Text('שגיאה בהתחברות: ${snapshot.error}',
                        textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => setState(() => _bootFuture = _boot()),
                      child: const Text('נסה שוב'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final householdId = snapshot.data;
        if (householdId == null) {
          return SetupScreen(firestore: _firestore, onLinked: _onLinked);
        }

        return ScanScreen(
          key: ValueKey(householdId),
          householdId: householdId,
          firestore: _firestore,
          onUnlink: _unlink,
        );
      },
    );
  }
}
