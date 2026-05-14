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
import 'theme/si_theme.dart';

void main() {
  runZonedGuarded(_init, (error, stack) {
    debugPrint('Unhandled error: $error');
  });
}

Future<void> _init() async {
  usePathUrlStrategy();
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es_MX', null);

  // dart-define values (CI/CD), overridden by .env in local dev
  var supabaseUrl = const String.fromEnvironment('SB_URL');
  var supabaseAnonKey = const String.fromEnvironment('SB_TOKEN');

  try {
    await dotenv.load(fileName: ".env");
    supabaseUrl = dotenv.maybeGet('SB_URL')?.trim() ?? supabaseUrl;
    supabaseAnonKey = dotenv.maybeGet('SB_TOKEN')?.trim() ?? supabaseAnonKey;
  } catch (_) {}

  if (supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty) {
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  }

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _themeMode = ValueNotifier<ThemeMode>(ThemeMode.light);

  @override
  void dispose() {
    _themeMode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: _themeMode,
      builder: (_, mode, __) => MaterialApp(
        title: 'Sistemassi',
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
        theme: SiTheme.light,
        darkTheme: SiTheme.dark,
        themeMode: mode,
        home: AuthRouter(themeNotifier: _themeMode),
      ),
    );
  }
}

class AuthRouter extends StatefulWidget {
  final ValueNotifier<ThemeMode> themeNotifier;
  const AuthRouter({super.key, required this.themeNotifier});

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
      return Scaffold(
        backgroundColor: SiColors.light.bg,
        body: Center(
          child: CircularProgressIndicator(
            color: SiColors.light.brand,
            strokeWidth: 2,
          ),
        ),
      );
    }

    if (_user == null) {
      return LoginPage(themeNotifier: widget.themeNotifier);
    }

    // Now everything returns MainNavigation, it handles the logic internally
    return MainNavigation(
      role: _role ?? 'usuario',
      permissions: _permissions ?? {},
    );
  }
}
