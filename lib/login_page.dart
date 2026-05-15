import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme/si_theme.dart';

// Navy constants used only by the light visual panel
const _navyBg    = Color(0xFF1A2466);
const _navyBrand = Color(0xFF6B7BD6);

// ─────────────────────────────────────────────────────────────────────────────
// LoginPage
// ─────────────────────────────────────────────────────────────────────────────
class LoginPage extends StatefulWidget {
  final ValueNotifier<ThemeMode>? themeNotifier;
  const LoginPage({super.key, this.themeNotifier});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  final _emailController    = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading      = false;
  bool _obscurePassword = true;
  bool _rememberMe     = true;

  late final AnimationController _fadeCtrl;
  late final Animation<double>   _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: SiMotion.normal)
      ..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: SiMotion.easeOut);
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _toggleTheme() {
    final n = widget.themeNotifier;
    if (n == null) return;
    n.value = n.value == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
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
  Widget build(BuildContext context) {
    final c      = SiColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size   = MediaQuery.of(context).size;
    final isWide = size.width >= 720;

    return Scaffold(
      backgroundColor: c.bg,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: Stack(
          children: [
            if (isWide)
              Row(
                children: [
                  SizedBox(
                    width: size.width * 0.40,
                    child: _buildFormPanel(c, isDark),
                  ),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: SiMotion.slow,
                      child: isDark
                          ? _DarkPanel(c: c, key: const ValueKey('dark'))
                          : const _LightPanel(key: ValueKey('light')),
                    ),
                  ),
                ],
              )
            else
              _buildNarrowForm(c, isDark),

            if (widget.themeNotifier != null)
              Positioned(
                top: 18,
                right: 22,
                child: _ThemeToggle(isDark: isDark, c: c, onTap: _toggleTheme),
              ),
          ],
        ),
      ),
    );
  }

  // ── Desktop form panel (left 40%) ──────────────────────────────────────────

  Widget _buildFormPanel(SiColors c, bool isDark) {
    return AnimatedContainer(
      duration: SiMotion.normal,
      color: c.panel,
      padding: const EdgeInsets.symmetric(horizontal: 52, vertical: 44),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _BrandMark(c: c),
          const Spacer(),
          ..._formContent(c, isDark),
          const Spacer(),
          _buildFooter(c),
        ],
      ),
    );
  }

  // ── Narrow (< 720px): centered scrollable form ─────────────────────────────

  Widget _buildNarrowForm(SiColors c, bool isDark) {
    return Container(
      color: c.bg,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _BrandMark(c: c),
                const SizedBox(height: SiSpace.x8),
                ..._formContent(c, isDark),
                const SizedBox(height: SiSpace.x6),
                _buildFooter(c),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Shared form content ────────────────────────────────────────────────────

  List<Widget> _formContent(SiColors c, bool isDark) => [
    Image.asset('assets/logo.png', height: 60),
    const SizedBox(height: SiSpace.x6),

    _LoginField(
      label: 'CORREO CORPORATIVO',
      controller: _emailController,
      icon: Icons.mail_outline_rounded,
      keyboardType: TextInputType.emailAddress,
      textInputAction: TextInputAction.next,
      onSubmitted: (_) => FocusScope.of(context).nextFocus(),
      c: c,
    ),
    const SizedBox(height: SiSpace.x3),

    _LoginField(
      label: 'CONTRASEÑA',
      controller: _passwordController,
      icon: Icons.key_outlined,
      obscureText: _obscurePassword,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _authenticate(),
      c: c,
      labelAction: GestureDetector(
        onTap: () {},
        child: Text(
          '¿Olvidaste?',
          style: SiType.sans(
              size: 11.5, color: c.brand, weight: FontWeight.w500),
        ),
      ),
      suffixIcon: IconButton(
        icon: Icon(
          _obscurePassword
              ? Icons.visibility_outlined
              : Icons.visibility_off_outlined,
          size: 15,
          color: c.ink3,
        ),
        onPressed: () =>
            setState(() => _obscurePassword = !_obscurePassword),
        splashRadius: 16,
      ),
    ),
    const SizedBox(height: SiSpace.x3),

    Row(
      children: [
        SizedBox(
          width: 18,
          height: 18,
          child: Checkbox(
            value: _rememberMe,
            onChanged: (v) => setState(() => _rememberMe = v ?? true),
            activeColor: c.brand,
            side: BorderSide(color: c.line2, width: 1.5),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4)),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        const SizedBox(width: SiSpace.x2),
        Text('Mantener sesión iniciada',
            style: SiType.sans(size: 12.5, color: c.ink2)),
      ],
    ),
    const SizedBox(height: SiSpace.x5),

    _LoginButton(c: c, loading: _isLoading, onTap: _authenticate, isDark: isDark),
  ];

  Widget _buildFooter(SiColors c) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(children: [
          Icon(Icons.shield_outlined, size: 11, color: c.success),
          const SizedBox(width: 5),
          Text('Acceso seguro',
              style: SiType.mono(size: 10, color: c.success)),
        ]),
        Text('v2.4.0', style: SiType.mono(size: 10, color: c.ink4)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _LightPanel — right panel, light theme (navy background)
// ─────────────────────────────────────────────────────────────────────────────
class _LightPanel extends StatelessWidget {
  const _LightPanel({super.key});

  static const _modules = [
    'MI PERFIL', 'CALENDARIO', 'INCIDENCIAS', 'INVENTARIO',
    'ASISTENCIA', 'BI', 'FIRMAS', 'LOGS', 'USUARIOS', 'CONTACTOS',
  ];

  static const _stats = [
    _Stat('248',    'Colaboradores activos', false),
    _Stat('12.4k',  'Eventos · últimos 30d', false),
    _Stat('99.98%', 'Uptime · 30d',          true),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _navyBg,
      padding: const EdgeInsets.all(52),
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _RuledLinesPainter())),

          Positioned(
            right: -24, top: 0, bottom: 0,
            child: Center(
              child: Text(
                '248',
                style: SiType.mono(
                  size: 280, weight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: 0.032),
                  letterSpacing: -16.8,
                ),
              ),
            ),
          ),

          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                    width: 20, height: 1,
                    color: Colors.white.withValues(alpha: 0.18)),
                const SizedBox(width: 10),
                Text(
                  'Sistema interno · Release 2026.Q2',
                  style: SiType.mono(
                      size: 10,
                      color: Colors.white.withValues(alpha: 0.24),
                      letterSpacing: 1.8),
                ),
              ]),
              const Spacer(),

              Text(
                'Opera tu empresa\ndesde un solo\nlugar.',
                style: SiType.sans(
                  size: 50, weight: FontWeight.w700,
                  color: Colors.white, height: 0.97, letterSpacing: -2.0,
                ),
              ),
              const SizedBox(height: SiSpace.x5),
              Text(
                'Incidencias, inventario, asistencia, BI y más.\nCentralizado, rápido y siempre disponible.',
                style: SiType.sans(
                    size: 14,
                    color: Colors.white.withValues(alpha: 0.34),
                    height: 1.65),
              ),
              const SizedBox(height: SiSpace.x5),

              Wrap(
                spacing: 5, runSpacing: 5,
                children: _modules
                    .map((m) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.09)),
                            borderRadius: SiRadius.rSm,
                          ),
                          child: Text(m,
                              style: SiType.mono(
                                  size: 9.5,
                                  color: Colors.white.withValues(alpha: 0.24),
                                  letterSpacing: 0.7)),
                        ))
                    .toList(),
              ),
              const Spacer(),

              ClipRRect(
                borderRadius: SiRadius.rLg,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: SiRadius.rLg,
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.07)),
                  ),
                  child: IntrinsicHeight(
                    child: Row(
                      children: _stats.asMap().entries.map((e) {
                        final idx = e.key;
                        final s   = e.value;
                        return Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 14),
                            decoration: BoxDecoration(
                              color: s.hi
                                  ? _navyBrand.withValues(alpha: 0.14)
                                  : Colors.white.withValues(alpha: 0.05),
                              border: idx < 2
                                  ? Border(
                                      right: BorderSide(
                                          color: Colors.white
                                              .withValues(alpha: 0.06)))
                                  : null,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(s.v,
                                    style: SiType.mono(
                                        size: 22,
                                        weight: FontWeight.w600,
                                        color: s.hi
                                            ? _navyBrand
                                            : Colors.white,
                                        letterSpacing: -0.55)),
                                const SizedBox(height: 3),
                                Text(s.l,
                                    style: SiType.sans(
                                        size: 11,
                                        color: Colors.white
                                            .withValues(alpha: 0.26))),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat {
  final String v, l;
  final bool hi;
  const _Stat(this.v, this.l, this.hi);
}

// ─────────────────────────────────────────────────────────────────────────────
// _DarkPanel — right panel, dark theme (KPI bands)
// ─────────────────────────────────────────────────────────────────────────────
class _DarkPanel extends StatelessWidget {
  final SiColors c;
  const _DarkPanel({required this.c, super.key});

  @override
  Widget build(BuildContext context) {
    final bands = [
      (n: '248',    label: 'COLABORADORES ACTIVOS',     color: c.brand),
      (n: '12.4k',  label: 'EVENTOS · ÚLTIMOS 30 DÍAS', color: c.warn),
      (n: '99.98%', label: 'UPTIME · ÚLTIMOS 30 DÍAS',  color: c.success),
    ];

    return AnimatedContainer(
      duration: SiMotion.normal,
      color: c.bg,
      padding: const EdgeInsets.all(52),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(width: 20, height: 1, color: c.line),
            const SizedBox(width: 10),
            Text('Operacional · Release 2026.Q2',
                style: SiType.mono(
                    size: 10, color: c.ink4, letterSpacing: 1.8)),
          ]),
          const Spacer(),

          ...bands.asMap().entries.expand((entry) {
            final i    = entry.key;
            final band = entry.value;
            return [
              if (i > 0)
                Container(
                  height: 1,
                  color: c.line,
                  margin: const EdgeInsets.only(left: 24),
                ),
              Container(
                decoration: BoxDecoration(
                  border:
                      Border(left: BorderSide(color: band.color, width: 2)),
                ),
                padding: const EdgeInsets.only(
                    left: 22, top: 22, bottom: 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(band.label,
                        style: SiType.mono(
                            size: 10,
                            weight: FontWeight.w500,
                            color: band.color,
                            letterSpacing: 1.5)),
                    const SizedBox(height: SiSpace.x1),
                    Text(band.n,
                        style: SiType.mono(
                            size: 80,
                            weight: FontWeight.w700,
                            color: band.color,
                            letterSpacing: -4.0)),
                  ],
                ),
              ),
            ];
          }),

          const Spacer(),

          Row(children: [
            Container(
              width: 6, height: 6,
              decoration: BoxDecoration(
                color: c.success,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: c.success.withValues(alpha: 0.5),
                      blurRadius: 8)
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text('Todos los sistemas operacionales',
                style:
                    SiType.mono(size: 10, color: c.ink4, letterSpacing: 1.0)),
            const Spacer(),
            Text('CDMX · MX',
                style: SiType.mono(size: 10, color: c.ink4)),
          ]),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Auxiliary widgets
// ─────────────────────────────────────────────────────────────────────────────

class _BrandMark extends StatelessWidget {
  final SiColors c;
  const _BrandMark({required this.c});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 30, height: 30,
          decoration:
              BoxDecoration(color: c.brand, borderRadius: SiRadius.rMd),
          child: const Center(
            child: Text('S',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    letterSpacing: -0.6,
                    fontFamily: 'Geist')),
          ),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sistemassi',
                style: SiType.sans(
                    size: 13.5,
                    weight: FontWeight.w600,
                    letterSpacing: -0.2)),
            Text('SISOL · INTRANET',
                style: SiType.mono(size: 10, letterSpacing: 1.2)),
          ],
        ),
      ],
    );
  }
}

class _LoginField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final IconData icon;
  final SiColors c;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final Widget? suffixIcon;
  final Widget? labelAction;

  const _LoginField({
    required this.label,
    required this.controller,
    required this.icon,
    required this.c,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
    this.suffixIcon,
    this.labelAction,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (labelAction != null)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _FieldLabel(label, c: c),
              labelAction!,
            ],
          )
        else
          _FieldLabel(label, c: c),
        const SizedBox(height: 5),
        AnimatedContainer(
          duration: SiMotion.fast,
          height: 40,
          decoration: BoxDecoration(
            color: c.hover,
            border: Border.all(color: c.line, width: 1.5),
            borderRadius: SiRadius.rMd,
          ),
          child: Row(
            children: [
              const SizedBox(width: 12),
              Icon(icon, size: 14, color: c.ink4),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: controller,
                  obscureText: obscureText,
                  keyboardType: keyboardType,
                  textInputAction: textInputAction,
                  onSubmitted: onSubmitted,
                  autocorrect: false,
                  enableSuggestions: false,
                  style: SiType.sans(size: 13, color: c.ink),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    filled: false,
                  ),
                ),
              ),
              if (suffixIcon != null) ...[suffixIcon!, const SizedBox(width: 4)],
            ],
          ),
        ),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  final SiColors c;
  const _FieldLabel(this.text, {required this.c});

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: SiType.mono(size: 10, color: c.ink3, letterSpacing: 1.0));
  }
}

class _LoginButton extends StatelessWidget {
  final SiColors c;
  final bool loading, isDark;
  final VoidCallback onTap;

  const _LoginButton({
    required this.c,
    required this.loading,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 42,
      child: AnimatedContainer(
        duration: SiMotion.fast,
        decoration: BoxDecoration(
          color: c.brand,
          borderRadius: SiRadius.rMd,
          boxShadow: isDark
              ? [
                  BoxShadow(
                      color: c.brand.withValues(alpha: 0.38),
                      blurRadius: 24,
                      offset: const Offset(0, 4))
                ]
              : [
                  BoxShadow(
                      color: c.brandInk.withValues(alpha: 1),
                      offset: const Offset(0, 1),
                      blurRadius: 0),
                  BoxShadow(
                      color: c.brand.withValues(alpha: 0.22),
                      blurRadius: 14,
                      offset: const Offset(0, 4)),
                ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: loading ? null : onTap,
            borderRadius: SiRadius.rMd,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: loading
                  ? const Center(
                      child: SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Iniciar sesión',
                            style: SiType.sans(
                                size: 14,
                                weight: FontWeight.w600,
                                color: Colors.white,
                                letterSpacing: -0.14)),
                        const Icon(Icons.arrow_forward_rounded,
                            size: 16, color: Colors.white),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ThemeToggle extends StatelessWidget {
  final bool isDark;
  final VoidCallback onTap;
  final SiColors c;

  const _ThemeToggle(
      {required this.isDark, required this.onTap, required this.c});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: SiMotion.normal,
        padding:
            const EdgeInsets.only(left: 8, right: 12, top: 6, bottom: 6),
        decoration: BoxDecoration(
          color: isDark
              ? c.panel.withValues(alpha: 0.88)
              : Colors.white.withValues(alpha: 0.90),
          borderRadius: SiRadius.rPill,
          border: Border.all(color: c.line),
          boxShadow: [
            BoxShadow(
              color:
                  Colors.black.withValues(alpha: isDark ? 0.35 : 0.10),
              blurRadius: isDark ? 16 : 12,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isDark ? Icons.wb_sunny_outlined : Icons.dark_mode_outlined,
              size: 13,
              color: isDark ? c.warn : c.ink3,
            ),
            const SizedBox(width: 6),
            AnimatedContainer(
              duration: SiMotion.normal,
              width: 28, height: 16,
              decoration: BoxDecoration(
                color: isDark ? c.brand : c.ink4,
                borderRadius: SiRadius.rPill,
              ),
              padding: const EdgeInsets.all(2),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOut,
                alignment: isDark
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: Container(
                  width: 12, height: 12,
                  decoration: const BoxDecoration(
                      color: Colors.white, shape: BoxShape.circle),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              isDark ? 'Oscuro' : 'Claro',
              style: SiType.mono(
                  size: 10.5,
                  color: c.ink2,
                  weight: FontWeight.w500,
                  letterSpacing: 1.0),
            ),
          ],
        ),
      ),
    );
  }
}

class _RuledLinesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.038)
      ..strokeWidth = 1.0;
    for (double y = 0; y < size.height; y += 32.0) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
