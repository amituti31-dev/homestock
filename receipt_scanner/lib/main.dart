import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'firebase_options.dart';
import 'screens/home_shell.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await NotificationService().init();
  runApp(const HomeStockApp());
}

class HomeStockApp extends StatelessWidget {
  const HomeStockApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HomeStock',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4CAF50)),
        useMaterial3: true,
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
  late Future<String> _householdFuture;

  @override
  void initState() {
    super.initState();
    _householdFuture = AuthService().ensureHousehold();
  }

  void _refreshHousehold() {
    setState(() {
      _householdFuture = AuthService().ensureHousehold();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _householdFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator(color: Color(0xFF4CAF50))),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(child: Text('שגיאה בהתחברות: ${snapshot.error}')),
          );
        }
        return HomeShell(
          key: ValueKey(snapshot.data!),
          householdId: snapshot.data!,
          onHouseholdChanged: _refreshHousehold,
        );
      },
    );
  }
}
