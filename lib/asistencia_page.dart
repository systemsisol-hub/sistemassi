import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'checador_panel.dart';
import 'schedules_page.dart';
import 'theme/si_theme.dart';
import 'widgets/carga_reportes.dart';

/// Asistencia, en dos pestañas: el Panel para mirar y Configuración para administrar.
///
/// La pestaña de Configuración sólo existe para administradores, y no por estética: crear horarios,
/// cargar reportes y mover los umbrales están reservados a administrador en la base. Mostrarla a
/// quien no puede usarla sería ofrecer botones que responden 403.
class AsistenciaPage extends StatefulWidget {
  const AsistenciaPage({super.key});

  @override
  State<AsistenciaPage> createState() => _AsistenciaPageState();
}

class _AsistenciaPageState extends State<AsistenciaPage>
    with SingleTickerProviderStateMixin {
  TabController? _tabs;
  bool _cargando = true;
  bool _esAdmin = false;

  /// Cambiar esta llave vuelve a montar el panel, que recarga al inicializarse. Es la forma más
  /// simple de refrescarlo cuando se acaba de subir un reporte en la otra pestaña.
  int _version = 0;

  @override
  void initState() {
    super.initState();
    _resolverRol();
  }

  @override
  void dispose() {
    _tabs?.dispose();
    super.dispose();
  }

  Future<void> _resolverRol() async {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid != null) {
        final perfil = await Supabase.instance.client
            .from('profiles').select('role').eq('id', uid).maybeSingle();
        _esAdmin = perfil?['role'] == 'admin';
      }
    } catch (e) {
      debugPrint('asistencia: no se pudo leer el rol: $e');
    }
    if (!mounted) return;
    setState(() {
      _tabs = TabController(length: _esAdmin ? 2 : 1, vsync: this);
      _cargando = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);

    if (_cargando || _tabs == null) {
      return Scaffold(
        backgroundColor: c.bg,
        body: Center(child: CircularProgressIndicator(color: c.brand)),
      );
    }

    return Scaffold(
      backgroundColor: c.bg,
      body: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: c.panel,
              border: Border(bottom: BorderSide(color: c.line)),
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TabBar(
                controller: _tabs,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: c.brand,
                unselectedLabelColor: c.ink3,
                indicatorColor: c.brand,
                indicatorSize: TabBarIndicatorSize.label,
                labelStyle:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                unselectedLabelStyle: const TextStyle(fontSize: 13),
                tabs: [
                  const Tab(
                    height: 42,
                    icon: Icon(Icons.insights_outlined, size: 16),
                    iconMargin: EdgeInsets.zero,
                    text: 'Panel',
                  ),
                  if (_esAdmin)
                    const Tab(
                      height: 42,
                      icon: Icon(Icons.settings_outlined, size: 16),
                      iconMargin: EdgeInsets.zero,
                      text: 'Configuración',
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                ChecadorPanel(key: ValueKey(_version)),
                if (_esAdmin)
                  _Configuracion(
                    alCargarReporte: () => setState(() => _version++),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _Configuracion extends StatelessWidget {
  const _Configuracion({required this.alCargarReporte});

  final VoidCallback alCargarReporte;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(SiSpace.x6),
      child: LayoutBuilder(
        builder: (context, box) {
          final izquierda = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CargaReportes(alCargar: alCargarReporte),
              const SizedBox(height: SiSpace.x4),
              const _Umbrales(),
            ],
          );
          const derecha = SchedulesPage();

          if (box.maxWidth < 900) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                izquierda,
                const SizedBox(height: SiSpace.x4),
                derecha,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: izquierda),
              const SizedBox(width: SiSpace.x4),
              const Expanded(flex: 2, child: derecha),
            ],
          );
        },
      ),
    );
  }
}

/// Cortes del semáforo. Se guardan en la base y no en el código para no tener que desplegar cuando
/// cambie el criterio: mover el corte reclasifica a todos de inmediato.
class _Umbrales extends StatefulWidget {
  const _Umbrales();

  @override
  State<_Umbrales> createState() => _UmbralesState();
}

class _UmbralesState extends State<_Umbrales> {
  final _supabase = Supabase.instance.client;

  double _critico = 70;
  double _atencion = 90;
  int _retardosPorDescuento = 3;
  bool _cargando = true;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _leer();
  }

  Future<void> _leer() async {
    try {
      final fila = await _supabase
          .from('checador_umbrales')
          .select('critico_max, atencion_max, retardos_por_descuento')
          .maybeSingle();
      if (fila != null && mounted) {
        setState(() {
          _critico = (fila['critico_max'] as num).toDouble();
          _atencion = (fila['atencion_max'] as num).toDouble();
          _retardosPorDescuento =
              ((fila['retardos_por_descuento'] as num?)?.toInt() ?? 3)
                  .clamp(1, 20);
          _cargando = false;
        });
        return;
      }
    } catch (e) {
      debugPrint('umbrales: $e');
    }
    if (mounted) setState(() => _cargando = false);
  }

  Future<void> _guardar() async {
    setState(() => _guardando = true);
    try {
      await _supabase.from('checador_umbrales').update({
        'critico_max': _critico,
        'atencion_max': _atencion,
        'retardos_por_descuento': _retardosPorDescuento,
        'actualizado_en': DateTime.now().toIso8601String(),
        'actualizado_por': _supabase.auth.currentUser?.id,
      }).eq('id', true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Configuración guardada. El panel la toma al recargar.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudieron guardar: $e')),
        );
      }
    }
    if (mounted) setState(() => _guardando = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);

    return Container(
      padding: const EdgeInsets.all(SiSpace.x4),
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: SiRadius.rMd,
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Icon(Icons.tune, size: 16, color: c.brand),
            const SizedBox(width: SiSpace.x2),
            Text('Semáforo y descuentos',
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600, color: c.ink)),
          ]),
          const SizedBox(height: SiSpace.x2),
          Text(
            'Definen cuándo una persona aparece en rojo, amarillo o verde según su porcentaje de '
            'puntualidad.',
            style: TextStyle(fontSize: 12, color: c.ink3, height: 1.4),
          ),
          if (_cargando)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: SiSpace.x5),
              child: Center(
                child: SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            )
          else ...[
            const SizedBox(height: SiSpace.x4),
            _regla(c, 'Crítico', 'por debajo de', _critico, c.danger, (v) {
              // El corte de crítico nunca puede rebasar al de atención: la base lo rechazaría y
              // además dejaría un rango imposible.
              setState(() => _critico = v.clamp(0, _atencion - 1));
            }),
            const SizedBox(height: SiSpace.x3),
            _regla(c, 'Atención', 'hasta', _atencion, c.warn, (v) {
              setState(() => _atencion = v.clamp(_critico + 1, 100));
            }),
            const SizedBox(height: SiSpace.x3),
            Row(children: [
              Container(
                width: 9, height: 9,
                decoration:
                    BoxDecoration(color: c.success, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(
                  'Puntual: más de ${_atencion.toStringAsFixed(0)}%',
                  style: TextStyle(fontSize: 12.5, color: c.ink2)),
            ]),
            const SizedBox(height: SiSpace.x5),
            Divider(height: 1, color: c.line),
            const SizedBox(height: SiSpace.x4),
            Row(children: [
              Icon(Icons.money_off, size: 16, color: c.brand),
              const SizedBox(width: SiSpace.x2),
              Text('Días a descontar',
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600, color: c.ink)),
            ]),
            const SizedBox(height: SiSpace.x2),
            Text(
              'Cada falta sin justificar es 1 día. Los retardos se acumulan y el cociente se '
              'redondea hacia abajo POR PERSONA: dos personas con 2 retardos cada una no hacen un '
              'día de descuento.',
              style: TextStyle(fontSize: 12, color: c.ink3, height: 1.4),
            ),
            const SizedBox(height: SiSpace.x3),
            Row(children: [
              Icon(Icons.alarm, size: 15, color: c.warn),
              const SizedBox(width: 8),
              SizedBox(
                width: 118,
                child: Text('Retardos por día:',
                    style: TextStyle(fontSize: 12.5, color: c.ink2)),
              ),
              Expanded(
                child: Slider(
                  value: _retardosPorDescuento.toDouble(),
                  min: 1,
                  max: 10,
                  divisions: 9,
                  activeColor: c.warn,
                  label: '$_retardosPorDescuento',
                  onChanged: (v) =>
                      setState(() => _retardosPorDescuento = v.round()),
                ),
              ),
              SizedBox(
                width: 44,
                child: Text('$_retardosPorDescuento',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: c.warn,
                        fontFeatures: const [FontFeature.tabularFigures()])),
              ),
            ]),
            const SizedBox(height: SiSpace.x2),
            Text('$_retardosPorDescuento retardos = 1 día de descuento.',
                style: TextStyle(fontSize: 11.5, color: c.ink3)),
            const SizedBox(height: SiSpace.x4),
            SizedBox(
              height: 38,
              child: ElevatedButton(
                onPressed: _guardando ? null : _guardar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.brand,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: SiRadius.rMd),
                ),
                child: Text(_guardando ? 'Guardando…' : 'Guardar configuración'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _regla(SiColors c, String etiqueta, String preposicion, double valor,
      Color color, ValueChanged<double> alCambiar) {
    return Row(children: [
      Container(
        width: 9, height: 9,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 8),
      SizedBox(
        width: 118,
        child: Text('$etiqueta: $preposicion',
            style: TextStyle(fontSize: 12.5, color: c.ink2)),
      ),
      Expanded(
        child: Slider(
          value: valor,
          min: 0,
          max: 100,
          divisions: 100,
          activeColor: color,
          label: '${valor.toStringAsFixed(0)}%',
          onChanged: alCambiar,
        ),
      ),
      SizedBox(
        width: 44,
        child: Text('${valor.toStringAsFixed(0)}%',
            textAlign: TextAlign.right,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()])),
      ),
    ]);
  }
}
