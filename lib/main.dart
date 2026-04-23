import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'main_navigation.dart';
import 'login_page.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:syncfusion_localizations/syncfusion_localizations.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  runZonedGuarded(_init, (error, stack) {
    debugPrint('ZONE ERROR: $error');
    debugPrint('STACK: $stack');
  });
}

Future<void> _init() async {
  usePathUrlStrategy();
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es_MX', null);

  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint("Warning: .env file not found, falling back to environment variables");
  }

  final supabaseUrl =
      (dotenv.maybeGet('SB_URL') ?? const String.fromEnvironment('SB_URL')).trim();
  final supabaseAnonKey =
      (dotenv.maybeGet('SB_TOKEN') ?? const String.fromEnvironment('SB_TOKEN')).trim();

  debugPrint('SB_URL length: ${supabaseUrl.length}, starts: ${supabaseUrl.substring(0, supabaseUrl.length.clamp(0, 15))}');

  if (supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty) {
    try {
      await Supabase.initialize(
        url: supabaseUrl,
        anonKey: supabaseAnonKey,
      );
      debugPrint('Supabase initialized successfully');
    } catch (e) {
      debugPrint('ERROR initializing Supabase: $e');
    }
  } else {
    debugPrint('ERROR: Supabase URL or token empty');
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'App Sisol Auth',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        SfGlobalLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('es', 'MX'),
        Locale('en', 'US'),
      ],
      locale: const Locale('es', 'MX'),
      theme: ThemeData(
        useMaterial3: true,
        textTheme: GoogleFonts.interTextTheme(ThemeData().textTheme),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF344092),
          primary: const Color(0xFF344092),
          secondary: const Color(0xFFB1CB34),
          tertiary: const Color(0xFFEA54A4),
          surface: Colors.grey[50] ?? Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF344092),
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF344092),
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 50),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey[300] ?? Colors.grey),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF344092), width: 2),
          ),
        ),
      ),
      home: const AuthRouter(),
    );
  }
}

class AuthRouter extends StatefulWidget {
  const AuthRouter({super.key});

  @override
  State<AuthRouter> createState() => _AuthRouterState();
}

class _AuthRouterState extends State<AuthRouter> {
  User? _user;
  String? _role;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _listenToAuth();
  }

  void _listenToAuth() {
    try {
      Supabase.instance.client.auth.onAuthStateChange.listen((data) {
        final session = data.session;
        if (mounted) {
          setState(() {
            _user = session?.user;
            if (_user == null) {
              _role = null;
              _permissions = null;
              _isLoading = false;
            } else {
              _fetchData();
            }
          });
        }
      });
    } catch (e) {
      debugPrint('Supabase no inicializado: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchData() async {
    final userId = _user?.id;
    if (userId == null) return;

    setState(() => _isLoading = true);
    try {
      final data = await Supabase.instance.client
          .from('profiles')
          .select('role, permissions')
          .eq('id', userId)
          .single();
      if (mounted) {
        setState(() {
          _role = data['role'];
          _permissions = data['permissions'] as Map<String, dynamic>?;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error obteniendo datos: $e');
      if (mounted) {
        setState(() {
          _role = 'usuario';
          _permissions = null;
          _isLoading = false;
        });
      }
    }
  }

  Map<String, dynamic>? _permissions;

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_user == null) {
      return const LoginPage();
    }

    // Now everything returns MainNavigation, it handles the logic internally
    return MainNavigation(
      role: _role ?? 'usuario',
      permissions: _permissions ?? {},
    );
  }
}
