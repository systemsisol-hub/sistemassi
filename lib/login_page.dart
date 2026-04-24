import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme/si_theme.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: SiMotion.normal)
      ..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: SiMotion.easeOut);
  }

  Future<void> _authenticate() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor llena todos los campos')),
      );
      return;
    }

    try {
      Supabase.instance.client.auth.currentUser;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error de configuración: $e'),
            backgroundColor: SiColors.light.danger,
          ),
        );
      }
      return;
    }

    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      await Supabase.instance.client.rpc('log_event', params: {
        'action_type_param': 'INICIO DE SESIÓN',
        'target_info_param': 'Usuario: ${_emailController.text.trim()}',
      });
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: SiColors.light.danger,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: SiColors.light.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    final isWide = MediaQuery.of(context).size.width >= 1024;

    return Scaffold(
      backgroundColor: c.bg,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: isWide ? _buildWide(c) : _buildNarrow(c),
      ),
    );
  }

  Widget _buildWide(SiColors c) {
    return Row(
      children: [
        Expanded(flex: 5, child: Center(child: _buildForm(c))),
        Expanded(flex: 4, child: _buildArtPanel(c)),
      ],
    );
  }

  Widget _buildNarrow(SiColors c) => Center(child: _buildForm(c));

  Widget _buildForm(SiColors c) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 400),
      padding: const EdgeInsets.symmetric(
          horizontal: SiSpace.x6, vertical: SiSpace.x8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Image.asset('assets/logo.png', height: 36),
          ),

          const SizedBox(height: SiSpace.x8),

          Text('Bienvenido de vuelta',
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: c.ink,
                  letterSpacing: -0.36,
                  height: 1.2)),
          const SizedBox(height: SiSpace.x1),
          Text(
            'Accede a la plataforma operativa de\nSisol Soluciones Inmobiliarias.',
            style: TextStyle(fontSize: 13, color: c.ink2, height: 1.5),
          ),

          const SizedBox(height: SiSpace.x6),

          _FieldLabel(label: 'Correo corporativo', c: c),
          const SizedBox(height: SiSpace.x1),
          _SiTextField(
            controller: _emailController,
            hint: 'nombre@sisol.com.mx',
            icon: Icons.mail_outline,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => FocusScope.of(context).nextFocus(),
          ),

          const SizedBox(height: SiSpace.x4),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _FieldLabel(label: 'Contraseña', c: c),
              TextButton(
                onPressed: () {},
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text('¿Olvidaste tu contraseña?',
                    style: TextStyle(
                        fontSize: 12,
                        color: c.brand,
                        fontWeight: FontWeight.w400)),
              ),
            ],
          ),
          const SizedBox(height: SiSpace.x1),
          _SiTextField(
            controller: _passwordController,
            icon: Icons.key_outlined,
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _authenticate(),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 16,
                color: c.ink3,
              ),
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
              splashRadius: 16,
            ),
          ),

          const SizedBox(height: SiSpace.x5),

          _SubmitButton(isLoading: _isLoading, onPressed: _authenticate),

          const SizedBox(height: SiSpace.x5),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Acceso restringido a personal autorizado.',
                  style: TextStyle(fontSize: 11, color: c.ink4)),
              Text('v2.4.0', style: SiType.mono(size: 11, color: c.ink4)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildArtPanel(SiColors c) {
    const modules = [
      'MI PERFIL', 'CALENDARIO', 'INCIDENCIAS', 'INVENTARIO',
      'ASISTENCIA', 'FIRMAS', 'BI', 'USUARIOS', 'LOGS', 'CONTACTOS',
    ];
    const stats = [
      ('248', 'Colaboradores activos'),
      ('12.4k', 'Eventos registrados'),
      ('99.98%', 'Uptime 30 días'),
    ];

    return Container(
      height: double.infinity,
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: c.brandHover, width: 1)),
      ),
      child: Stack(
        children: [
          // Capa 1 — gradiente base
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [Color(0xFF1A2466), Color(0xFF0F1640)],
                ),
              ),
            ),
          ),
          // Capa 2 — grid de líneas 48×48
          Positioned.fill(
            child: CustomPaint(
              painter: _GridPainter(
                color: Colors.white.withValues(alpha: 0.06),
                step: 48,
              ),
            ),
          ),
          // Capa 3 — contenido
          Padding(
            padding: const EdgeInsets.all(SiSpace.x8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: SiRadius.rPill,
                  ),
                  child: Text('Sistema interno · Release 2026.Q2',
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.7))),
                ),
                const SizedBox(height: SiSpace.x4),
                RichText(
                  text: TextSpan(
                    style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        height: 1.25,
                        letterSpacing: -0.56),
                    children: [
                      const TextSpan(text: 'Opera tu día desde\nun solo lugar '),
                      TextSpan(
                          text: 'ordenado',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontStyle: FontStyle.italic)),
                      const TextSpan(text: '.'),
                    ],
                  ),
                ),
                const SizedBox(height: SiSpace.x6),
                Wrap(
                  spacing: SiSpace.x1,
                  runSpacing: SiSpace.x1,
                  children: modules
                      .map((m) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: SiSpace.x2, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.10),
                              borderRadius: SiRadius.rSm,
                              border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.15),
                                  width: 1),
                            ),
                            child: Text(m,
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white.withValues(alpha: 0.8),
                                    letterSpacing: 0.5)),
                          ))
                      .toList(),
                ),
                const SizedBox(height: SiSpace.x5),
                Row(
                  children: stats
                      .map((s) => Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(s.$1,
                                    style: const TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                        height: 1.1)),
                                Text(s.$2,
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.white
                                            .withValues(alpha: 0.55))),
                              ],
                            ),
                          ))
                      .toList(),
                ),
                const SizedBox(height: SiSpace.x8),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Grid painter para el panel azul ──────────────────────────────────────────

class _GridPainter extends CustomPainter {
  final Color color;
  final double step;
  _GridPainter({required this.color, required this.step});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (double x = 0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Sub-widgets ──────────────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.label, required this.c});
  final String label;
  final SiColors c;

  @override
  Widget build(BuildContext context) => Text(label,
      style: TextStyle(
          fontSize: 12, fontWeight: FontWeight.w500, color: c.ink2));
}

class _SiTextField extends StatelessWidget {
  const _SiTextField({
    required this.controller,
    required this.icon,
    this.hint,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
    this.suffixIcon,
  });

  final TextEditingController controller;
  final IconData icon;
  final String? hint;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final Widget? suffixIcon;

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      autocorrect: false,
      enableSuggestions: false,
      style: TextStyle(fontSize: 14, color: c.ink),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 14, right: 10),
          child: Icon(icon, size: 16, color: c.ink3),
        ),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 40, minHeight: 44,
        ),
        suffixIcon: suffixIcon,
        suffixIconConstraints: const BoxConstraints(
          minWidth: 44, minHeight: 44,
        ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14, vertical: 12,
        ),
        filled: true,
        fillColor: c.panel,
        hintStyle: TextStyle(color: c.ink4, fontSize: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: SiRadius.rMd,
          borderSide: BorderSide(color: c.line, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: SiRadius.rMd,
          borderSide: BorderSide(color: c.brand, width: 1.5),
        ),
      ),
    );
  }
}

class _SubmitButton extends StatelessWidget {
  const _SubmitButton({required this.isLoading, required this.onPressed});
  final bool isLoading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    return SizedBox(
      width: double.infinity,
      height: 38,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: c.brand,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: const RoundedRectangleBorder(borderRadius: SiRadius.rMd),
          textStyle:
              const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        child: isLoading
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white.withOpacity(0.8),
                ),
              )
            : const Text('Iniciar sesión'),
      ),
    );
  }
}
