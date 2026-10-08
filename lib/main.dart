import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:supabase_flutter/supabase_flutter.dart';
import 'main_navigation.dart';
import 'utils/enlace_inicial.dart';
import 'login_page.dart';
import 'reset_password_page.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart' show FlutterQuillLocalizations;
import 'package:syncfusion_localizations/syncfusion_localizations.dart';
import 'theme/si_theme.dart';

// Importación condicional para web
import 'web_url_strategy_stub.dart'
    if (dart.library.html) 'package:flutter_web_plugins/url_strategy.dart';
import 'utils/limpiar_url_stub.dart'
    if (dart.library.js_interop) 'utils/limpiar_url_web.dart';

void main() {
  runZonedGuarded(_init, (error, stack) {
    debugPrint('Unhandled error: $error');
  });
}

Future<void> _init() async {
  if (kIsWeb) {
    // Antes de que Flutter reescriba la dirección a `/` (ver enlace_inicial.dart).
    final inv = Uri.base.queryParameters['inv'];
    if (inv != null && inv.isNotEmpty) equipoDelEnlace = inv.toUpperCase();
    usePathUrlStrategy();
  }
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es_MX', null);

  // En TELÉFONOS la app va solo en vertical: en horizontal un teléfono mide más de 800 de ancho y la
  // app lo tomaba por computadora (menú lateral sin lugar, calendario aplastado con errores), y son
  // decenas de pantallas que eligen su diseño por el ancho. Tablets y computadora siguen girando.
  // En el iPhone lo fija también el Info.plist; esto cubre los teléfonos Android.
  if (!kIsWeb) {
    final vista = WidgetsBinding.instance.platformDispatcher.views.first;
    final ladoCorto = (vista.physicalSize / vista.devicePixelRatio).shortestSide;
    if (ladoCorto < 600) {
      await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    }
  }

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
        title: 'SistemasSI',
        debugShowCheckedModeBanner: false,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          SfGlobalLocalizations.delegate,
          // El editor de Correspondencia la exige: sin ella su barra de herramientas no encuentra sus
          // textos y la pagina revienta al abrirse, sin ningun error en la compilacion.
          FlutterQuillLocalizations.delegate,
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

  /// Aviso para la pantalla de inicio de sesión: el enlace de recuperación ya no sirve.
  String? _avisoLogin;

  /// Intercambia el enlace de recuperación por una sesión.
  ///
  /// Dos formas de enlace:
  ///
  ///   * `?token_hash=…&type=recovery` — la de la plantilla del correo desde el 28/09/2026. Se verifica
  ///     directo con Supabase, así que sirve abierto en CUALQUIER navegador o teléfono.
  ///   * `?code=…` — la de antes (PKCE). Solo sirve en el navegador que pidió el correo, porque la
  ///     clave para canjearlo se guardó ahí. Por eso no servía para mandar el correo a todos desde el
  ///     servidor: nadie lo abre en el navegador que lo pidió. Se conserva para los correos que ya
  ///     estén en camino.
  Future<void> _handleWebAuthCallback() async {
    final params = Uri.base.queryParameters;
    final tokenHash = params['token_hash'];
    if (tokenHash != null && tokenHash.isNotEmpty && params['type'] == 'recovery') {
      await _canjearTokenHash(tokenHash);
      return;
    }
    final code = params['code'];
    if (code == null || code.isEmpty) return;
    try {
      await Supabase.instance.client.auth.exchangeCodeForSession(code);
      // exchangeCodeForSession puede disparar signedIn en vez de passwordRecovery
      // según la versión de supabase_flutter. Forzamos el modo recuperación aquí.
      if (mounted) setState(() { _isRecovery = true; _isLoading = false; });
    } catch (_) {
      // Código ya canjeado (el SDK lo procesó en initialize) — verificar si
      // hay sesión activa. En cualquier caso limpiar _isLoading.
      final session = Supabase.instance.client.auth.currentSession;
      if (mounted) {
        setState(() {
          _isRecovery = session != null;
          _isLoading  = false;
        });
      }
    }
  }

  Future<void> _canjearTokenHash(String tokenHash) async {
    // Antes de verificar: el inicio de sesión que dispara la verificación no debe ir a cargar el menú
    // (ver `_listenToAuth`), sino quedarse en la pantalla de nueva contraseña.
    setState(() => _isRecovery = true);
    try {
      await Supabase.instance.client.auth.verifyOTP(
        type: OtpType.recovery,
        tokenHash: tokenHash,
      );
      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('Enlace de recuperación inválido: $e');
      if (mounted) {
        setState(() {
          _isRecovery = false;
          _isLoading = false;
          _avisoLogin = 'Ese enlace ya se usó o caducó. Pide uno nuevo en «¿Olvidaste?» '
              'o escríbele a Sistemas (mam@sisol.com.mx, ave@sisol.com.mx).';
        });
      }
    } finally {
      quitarParametrosDeLaUrl();
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
    final auth = Supabase.instance.client.auth;
    // Al abrir la app despues de una hora, la sesion guardada trae el token vencido y Supabase lo
    // renueva por su lado, sin esperar. Si se consulta antes, la base contesta «JWT expired», el
    // perfil cae a 'usuario' sin permisos y asi se queda (visto en Android el 01/10/2026). Se
    // renueva aqui primero; las paginas cargan despues y ya usan el token nuevo.
    Future<Map<String, dynamic>> leerPerfil() => Supabase.instance.client
        .from('profiles')
        .select('role, permissions')
        .eq('id', userId)
        .single();
    try {
      if (auth.currentSession?.isExpired ?? false) await auth.refreshSession();
    } catch (e) {
      debugPrint('No se pudo renovar la sesion: $e');
    }
    try {
      Map<String, dynamic> data;
      try {
        data = await leerPerfil();
      } on PostgrestException catch (e) {
        // Vencio entre la revision y la consulta: se renueva y se intenta una vez mas.
        if (e.code != 'PGRST303' && e.code != '401') rethrow;
        await auth.refreshSession();
        data = await leerPerfil();
      }
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
      return LoginPage(themeNotifier: widget.themeNotifier, aviso: _avisoLogin);
    }

    // Now everything returns MainNavigation, it handles the logic internally
    return MainNavigation(
      role: _role ?? 'usuario',
      permissions: _permissions ?? {},
      themeNotifier: widget.themeNotifier,
    );
  }
}
