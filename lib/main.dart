import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:supabase_flutter/supabase_flutter.dart';
import 'main_navigation.dart';
import 'login_page.dart';
import 'reset_password_page.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:syncfusion_localizations/syncfusion_localizations.dart';
import 'theme/si_theme.dart';

// Importación condicional para web
import 'web_url_strategy_stub.dart'
    if (dart.library.html) 'package:flutter_web_plugins/url_strategy.dart';

void main() {
  runZonedGuarded(_init, (error, stack) {
    debugPrint('Unhandled error: $error');
  });
}

Future<void> _init() async {
  if (kIsWeb) {
    usePathUrlStrategy();
  }
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es_MX', null);

  // dart-define values (CI/CD), overridden by .env in local dev
  var supabaseUrl = const String.fromEnvironment('SB_URL');
  var supabaseAnonKey = const String.fromEnvironment('SB_TOKEN');

  // Try the asset-bundled .env first (works on all platforms including Android)
  // then fall back to a root .env for local web dev.
  for (final path in ['assets/.env', '.env']) {
    try {
      await dotenv.load(fileName: path);
      supabaseUrl = dotenv.maybeGet('SB_URL')?.trim() ?? supabaseUrl;
      supabaseAnonKey = dotenv.maybeGet('SB_TOKEN')?.trim() ?? supabaseAnonKey;
      if (supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty) break;
    } catch (_) {}
  }

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
  bool _isLoading  = true;
  bool _isRecovery = false;

  @override
  void initState() {
    super.initState();
    _listenToAuth();
    // Procesar el ?code= del enlace de recuperación (flujo PKCE en web)
    if (kIsWeb) _handleWebAuthCallback();
  }

  /// Intercambia el `?code=` del enlace de recuperación por una sesión.
  /// Cubre el caso en que supabase_flutter no detectó el parámetro automáticamente.
  Future<void> _handleWebAuthCallback() async {
    final code = Uri.base.queryParameters['code'];
    if (code == null || code.isEmpty) return;
    try {
      // Esto dispara onAuthStateChange con AuthChangeEvent.passwordRecovery
      await Supabase.instance.client.auth.exchangeCodeForSession(code);
    } catch (_) {
      // Si el SDK ya procesó el código automáticamente y hay sesión activa,
      // marcamos como recuperación de contraseña.
      final session = Supabase.instance.client.auth.currentSession;
      if (session != null && mounted) {
        setState(() { _isRecovery = true; _isLoading = false; });
      }
    }
  }

  void _listenToAuth() {
    try {
      Supabase.instance.client.auth.onAuthStateChange.listen((data) {
        // Enlace de recuperación de contraseña clickeado
        if (data.event == AuthChangeEvent.passwordRecovery) {
          if (mounted) setState(() { _isRecovery = true; _isLoading = false; });
          return;
        }

        final session = data.session;
        if (mounted) {
          setState(() {
            final newUser = session?.user;
            if (newUser == null) {
              // Sign-out: clear everything
              _user = null;
              _role = null;
              _permissions = null;
              _isLoading   = false;
              _isRecovery  = false;
            } else if (_user?.id != newUser.id) {
              // Different user logged in: fetch fresh data
              _user = newUser;
              // No llamar _fetchData durante la recuperación: evita que
              // _isLoading=true destruya ResetPasswordPage y borre _done=true
              if (!_isRecovery) _fetchData();
            } else {
              // Same user — token refresh or minor event: just update the user
              // object without re-fetching or showing loading (preserves navigation)
              _user = newUser;
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

    // Only show loading spinner on the very first load (no role yet)
    if (_role == null) setState(() => _isLoading = true);
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

    if (_isRecovery) {
      return ResetPasswordPage(
        themeNotifier: widget.themeNotifier,
        onDone: () => setState(() {
          _isRecovery  = false;
          _user        = null;
          _role        = null;
          _permissions = null;
        }),
      );
    }

    if (_user == null) {
      return LoginPage(themeNotifier: widget.themeNotifier);
    }

    // Now everything returns MainNavigation, it handles the logic internally
    return MainNavigation(
      role: _role ?? 'usuario',
      permissions: _permissions ?? {},
      themeNotifier: widget.themeNotifier,
    );
  }
}
