import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme/si_theme.dart';

// Navy constants (same as login page)
const _navyBg    = Color(0xFF1A2466);
const _navyBrand = Color(0xFF6B7BD6);

class ResetPasswordPage extends StatefulWidget {
  final ValueNotifier<ThemeMode>? themeNotifier;
  final VoidCallback onDone;
  const ResetPasswordPage({
    super.key,
    this.themeNotifier,
    required this.onDone,
  });

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage>
    with SingleTickerProviderStateMixin {
  final _passCtrl    = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _loading  = false;
  bool _obscure1 = true;
  bool _obscure2 = true;
  bool _done     = false;
  String? _error;

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
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final pass    = _passCtrl.text.trim();
    final confirm = _confirmCtrl.text.trim();

    if (pass.isEmpty) {
      setState(() => _error = 'Ingresa la nueva contraseña');
      return;
    }
    if (pass.length < 6) {
      setState(() => _error = 'La contraseña debe tener al menos 6 caracteres');
      return;
    }
    if (pass != confirm) {
      setState(() => _error = 'Las contraseñas no coinciden');
      return;
    }

    setState(() { _loading = true; _error = null; });
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: pass),
      );
      if (mounted) setState(() { _loading = false; _done = true; });
    } on AuthException catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.message; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  void _toggleTheme() {
    final n = widget.themeNotifier;
    if (n == null) return;
    n.value = n.value == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
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
              Row(children: [
                SizedBox(
                  width: size.width * 0.40,
                  child: _buildFormPanel(c, isDark),
                ),
                Expanded(child: _buildRightPanel(c, isDark)),
              ])
            else
              _buildNarrowForm(c, isDark),

            if (widget.themeNotifier != null)
              Positioned(
                top: 18, right: 22,
                child: _ThemeToggleMin(isDark: isDark, c: c, onTap: _toggleTheme),
              ),
          ],
        ),
      ),
    );
  }

  // ── Desktop left panel ────────────────────────────────────────────────────

  Widget _buildFormPanel(SiColors c, bool isDark) {
    return AnimatedContainer(
      duration: SiMotion.normal,
      color: c.panel,
      padding: const EdgeInsets.symmetric(horizontal: 52, vertical: 44),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _BrandMarkMin(c: c),
          const Spacer(),
          ..._formContent(c),
          const Spacer(),
          _buildFooter(c),
        ],
      ),
    );
  }

  // ── Narrow form ───────────────────────────────────────────────────────────

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
                _BrandMarkMin(c: c),
                const SizedBox(height: SiSpace.x8),
                ..._formContent(c),
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

  List<Widget> _formContent(SiColors c) {
    if (_done) return _doneContent(c);
    return [
      // Header
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.brandTint,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.lock_reset_outlined, size: 28, color: c.brand),
      ),
      const SizedBox(height: SiSpace.x4),
      Text('Nueva contraseña',
          style: SiType.sans(
              size: 22, weight: FontWeight.w700,
              color: c.ink, letterSpacing: -0.5)),
      const SizedBox(height: 6),
      Text('Elige una contraseña segura para tu cuenta.',
          style: SiType.sans(size: 13, color: c.ink3, height: 1.55)),
      const SizedBox(height: SiSpace.x6),

      // Error
      if (_error != null) ...[
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: SiColors.light.dangerTint,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: SiColors.light.danger.withOpacity(0.3)),
          ),
          child: Row(children: [
            Icon(Icons.error_outline, size: 15, color: SiColors.light.danger),
            const SizedBox(width: 8),
            Expanded(child: Text(_error!,
                style: TextStyle(fontSize: 12, color: SiColors.light.danger))),
          ]),
        ),
        const SizedBox(height: SiSpace.x3),
      ],

      // Password field
      _label('NUEVA CONTRASEÑA', c),
      const SizedBox(height: 5),
      _passField(
        ctrl: _passCtrl,
        hint: 'Mínimo 6 caracteres',
        obscure: _obscure1,
        onToggle: () => setState(() => _obscure1 = !_obscure1),
        onSubmitted: (_) => FocusScope.of(context).nextFocus(),
        c: c,
      ),
      const SizedBox(height: SiSpace.x3),

      // Confirm field
      _label('CONFIRMAR CONTRASEÑA', c),
      const SizedBox(height: 5),
      _passField(
        ctrl: _confirmCtrl,
        hint: 'Repite la contraseña',
        obscure: _obscure2,
        onToggle: () => setState(() => _obscure2 = !_obscure2),
        onSubmitted: (_) => _save(),
        c: c,
      ),
      const SizedBox(height: SiSpace.x5),

      // Button
      SizedBox(
        width: double.infinity,
        height: 42,
        child: ElevatedButton(
          onPressed: _loading ? null : _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: c.brand,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: SiRadius.rMd),
            elevation: 0,
          ),
          child: _loading
              ? const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
              : Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Guardar contraseña',
                        style: SiType.sans(
                            size: 14,
                            weight: FontWeight.w600,
                            color: Colors.white)),
                    const Icon(Icons.arrow_forward_rounded,
                        size: 16, color: Colors.white),
                  ],
                ),
        ),
      ),
    ];
  }

  List<Widget> _doneContent(SiColors c) => [
    Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.successTint,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(Icons.check_circle_outline, size: 28, color: c.success),
    ),
    const SizedBox(height: SiSpace.x4),
    Text('¡Contraseña actualizada!',
        style: SiType.sans(
            size: 22, weight: FontWeight.w700,
            color: c.ink, letterSpacing: -0.5)),
    const SizedBox(height: 6),
    Text('Tu contraseña ha sido cambiada exitosamente.',
        style: SiType.sans(size: 13, color: c.ink3, height: 1.55)),
    const SizedBox(height: SiSpace.x6),
    SizedBox(
      width: double.infinity,
      height: 42,
      child: ElevatedButton(
        onPressed: () {
          Supabase.instance.client.auth.signOut();
          widget.onDone();
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: c.brand,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: SiRadius.rMd),
          elevation: 0,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Ir al inicio de sesión',
                style: SiType.sans(
                    size: 14,
                    weight: FontWeight.w600,
                    color: Colors.white)),
            const Icon(Icons.login_rounded,
                size: 16, color: Colors.white),
          ],
        ),
      ),
    ),
  ];

  // ── Right decorative panel ─────────────────────────────────────────────────

  Widget _buildRightPanel(SiColors c, bool isDark) {
    if (isDark) {
      return AnimatedContainer(
        duration: SiMotion.normal,
        color: c.bg,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_reset_outlined, size: 80,
                  color: c.brand.withOpacity(0.18)),
              const SizedBox(height: 20),
              Text('Recuperación\nde acceso',
                  textAlign: TextAlign.center,
                  style: SiType.sans(
                      size: 40,
                      weight: FontWeight.w700,
                      color: c.ink.withOpacity(0.08),
                      height: 1.1,
                      letterSpacing: -2.0)),
            ],
          ),
        ),
      );
    }
    return Container(
      color: _navyBg,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.lock_reset_outlined, size: 56,
                  color: _navyBrand.withOpacity(0.7)),
            ),
            const SizedBox(height: 28),
            Text('Recuperación\nde acceso',
                textAlign: TextAlign.center,
                style: SiType.sans(
                    size: 38,
                    weight: FontWeight.w700,
                    color: Colors.white.withOpacity(0.12),
                    height: 1.1,
                    letterSpacing: -2.0)),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter(SiColors c) => Row(
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

  // ── Helpers ────────────────────────────────────────────────────────────────

  Widget _label(String text, SiColors c) =>
      Text(text, style: SiType.mono(size: 10, color: c.ink3, letterSpacing: 1.0));

  Widget _passField({
    required TextEditingController ctrl,
    required String hint,
    required bool obscure,
    required VoidCallback onToggle,
    required ValueChanged<String> onSubmitted,
    required SiColors c,
  }) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: c.hover,
        borderRadius: SiRadius.rMd,
        border: Border.all(color: c.line),
      ),
      child: Row(children: [
        const SizedBox(width: 12),
        Icon(Icons.key_outlined, size: 14, color: c.ink4),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: ctrl,
            obscureText: obscure,
            textInputAction: TextInputAction.done,
            onSubmitted: onSubmitted,
            autocorrect: false,
            enableSuggestions: false,
            style: SiType.sans(size: 13, color: c.ink),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: SiType.sans(size: 13, color: c.ink4),
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
        IconButton(
          icon: Icon(
            obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
            size: 15, color: c.ink3,
          ),
          onPressed: onToggle,
          splashRadius: 16,
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Minimal brand mark (reused from login_page concept)
// ─────────────────────────────────────────────────────────────────────────────

class _BrandMarkMin extends StatelessWidget {
  final SiColors c;
  const _BrandMarkMin({required this.c});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 30, height: 30,
          decoration: BoxDecoration(color: c.brand, borderRadius: SiRadius.rMd),
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
                    size: 13.5, weight: FontWeight.w600, letterSpacing: -0.2)),
            Text('SISOL · INTRANET',
                style: SiType.mono(size: 10, letterSpacing: 1.2)),
          ],
        ),
      ],
    );
  }
}

class _ThemeToggleMin extends StatelessWidget {
  final bool isDark;
  final SiColors c;
  final VoidCallback onTap;
  const _ThemeToggleMin(
      {required this.isDark, required this.c, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isDark
              ? c.panel.withOpacity(0.88)
              : Colors.white.withOpacity(0.90),
          borderRadius: SiRadius.rPill,
          border: Border.all(color: c.line),
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
            Text(
              isDark ? 'Oscuro' : 'Claro',
              style: SiType.mono(
                  size: 10.5, color: c.ink2,
                  weight: FontWeight.w500, letterSpacing: 1.0),
            ),
          ],
        ),
      ),
    );
  }
}
