import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme/si_theme.dart';

/// Qué puede hacer Soli, leído de la propia función.
///
/// ─── Por qué pregunta a la función y no tiene su propia lista ───────────────
///
/// La configuración del agente vivía sólo dentro de `ai-assistant/index.ts`: para saber qué podía
/// hacer había que leer código, y en la práctica lo sabían dos personas. Esta página existe para que
/// cualquier administrador lo vea.
///
/// Podría llevar la lista escrita aquí en Dart, y sería más simple, pero se quedaría vieja en cuanto
/// alguien tocara la función —y una pantalla de configuración que miente es peor que no tenerla—. Así
/// que se le pregunta a la función, que es el único sitio donde está la verdad.
///
/// Es de sólo lectura a propósito. Decidido con el usuario: poder reasignar desde aquí qué permiso
/// exige cada herramienta permitiría abrir el acceso a datos de RH por error, sin revisión ni
/// despliegue. Para cambiar algo se toca el código, que deja rastro.
class AgenteConfigPage extends StatefulWidget {
  const AgenteConfigPage({super.key});

  @override
  State<AgenteConfigPage> createState() => _AgenteConfigPageState();
}

class _AgenteConfigPageState extends State<AgenteConfigPage> {
  static const _fnUrl =
      'https://zkmbebybyyefmqcxjqrg.supabase.co/functions/v1/ai-assistant';

  Map<String, dynamic>? _config;
  String? _error;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final sesion = Supabase.instance.client.auth.currentSession;
      if (sesion == null) throw Exception('Sin sesión activa');

      final resp = await http
          .post(
            Uri.parse(_fnUrl),
            headers: {
              'Authorization': 'Bearer ${sesion.accessToken}',
              'Content-Type': 'application/json',
            },
            // La función distingue esta petición de una conversación por esta bandera.
            body: jsonEncode({'configuracion': true, 'messages': []}),
          )
          .timeout(const Duration(seconds: 30));

      final cuerpo = jsonDecode(resp.body) as Map<String, dynamic>;
      if (resp.statusCode != 200) {
        throw Exception(cuerpo['error']?.toString() ?? 'Error ${resp.statusCode}');
      }
      if (!mounted) return;
      setState(() {
        _config = cuerpo;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _cargando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);

    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 40, color: c.danger),
              const SizedBox(height: 12),
              Text('No se pudo leer la configuración',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600, color: c.ink)),
              const SizedBox(height: 6),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: c.ink3)),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _cargar,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    final cfg = _config!;
    final herramientas =
        (cfg['herramientas'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final vias = (cfg['vias_directas'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _Encabezado(cfg: cfg, total: herramientas.length, c: c),
          const SizedBox(height: 20),
          _Seccion(
            titulo: 'Se resuelven sin pasar por el modelo',
            nota: 'Por eso son instantáneas, no gastan una llamada al modelo, y siguen '
                'funcionando si el proveedor está caído.',
            c: c,
            hijo: Column(
              children: vias
                  .map((v) => _FilaVia(
                      pregunta: '${v['pregunta']}',
                      resuelve: '${v['resuelve']}',
                      c: c))
                  .toList(),
            ),
          ),
          const SizedBox(height: 20),
          _Seccion(
            titulo: 'Herramientas',
            nota: 'Lo que Soli puede consultar o modificar. La columna de la derecha dice si '
                'TÚ la alcanzas con los permisos que tienes puestos ahora.',
            c: c,
            hijo: _TablaHerramientas(herramientas: herramientas, c: c),
          ),
          const SizedBox(height: 20),
          _Seccion(
            titulo: 'Cómo se cambia esto',
            nota: null,
            c: c,
            hijo: Text(
              'Esta página es de sólo lectura. Los permisos de cada persona se asignan en la '
              'página de Usuarios; lo que exige cada herramienta se define en el código de la '
              'función, para que todo cambio quede registrado y revisable.',
              style: TextStyle(fontSize: 13, height: 1.5, color: c.ink3),
            ),
          ),
        ],
      ),
    );
  }
}

class _Encabezado extends StatelessWidget {
  final Map<String, dynamic> cfg;
  final int total;
  final SiColors c;
  const _Encabezado({required this.cfg, required this.total, required this.c});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.smart_toy_outlined, size: 22, color: c.brand),
              const SizedBox(width: 10),
              Text('Configuración de Soli',
                  style: TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700, color: c.ink)),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 24,
            runSpacing: 12,
            children: [
              _Dato(etiqueta: 'Modelo', valor: '${cfg['modelo']}', c: c),
              _Dato(etiqueta: 'Proveedor', valor: '${cfg['proveedor']}', c: c),
              _Dato(etiqueta: 'Herramientas', valor: '$total', c: c),
            ],
          ),
          const SizedBox(height: 14),
          Text('${cfg['ambito']}',
              style: TextStyle(fontSize: 13, height: 1.5, color: c.ink3)),
        ],
      ),
    );
  }
}

class _Dato extends StatelessWidget {
  final String etiqueta;
  final String valor;
  final SiColors c;
  const _Dato({required this.etiqueta, required this.valor, required this.c});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(etiqueta.toUpperCase(),
            style: TextStyle(
                fontSize: 10,
                letterSpacing: 0.6,
                fontWeight: FontWeight.w700,
                color: c.ink3)),
        const SizedBox(height: 2),
        Text(valor,
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600, color: c.ink)),
      ],
    );
  }
}

class _Seccion extends StatelessWidget {
  final String titulo;
  final String? nota;
  final Widget hijo;
  final SiColors c;
  const _Seccion(
      {required this.titulo, required this.nota, required this.hijo, required this.c});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo,
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700, color: c.ink)),
          if (nota != null) ...[
            const SizedBox(height: 4),
            Text(nota!,
                style: TextStyle(fontSize: 12.5, height: 1.45, color: c.ink3)),
          ],
          const SizedBox(height: 14),
          hijo,
        ],
      ),
    );
  }
}

class _FilaVia extends StatelessWidget {
  final String pregunta;
  final String resuelve;
  final SiColors c;
  const _FilaVia({required this.pregunta, required this.resuelve, required this.c});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.bolt, size: 16, color: c.success),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(pregunta,
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: c.ink)),
                Text(resuelve,
                    style: TextStyle(fontSize: 12.5, color: c.ink3)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TablaHerramientas extends StatelessWidget {
  final List<Map<String, dynamic>> herramientas;
  final SiColors c;
  const _TablaHerramientas({required this.herramientas, required this.c});

  @override
  Widget build(BuildContext context) {
    // Las tablas anchas se desplazan dentro de su propio contenedor: si no, en una pantalla angosta
    // la página entera se va de lado.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 640),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  _celda('QUÉ HACE', 300, encabezado: true),
                  _celda('REQUIERE', 180, encabezado: true),
                  _celda('TÚ', 60, encabezado: true),
                ],
              ),
            ),
            Divider(height: 1, color: c.line),
            ...herramientas.map(_fila),
          ],
        ),
      ),
    );
  }

  Widget _fila(Map<String, dynamic> h) {
    final permiso = h['permiso'] as String?;
    final soloAdmin = h['solo_admin'] == true;
    final tuya = h['disponible_para_ti'] == true;

    // Se dice «cualquiera con acceso al asistente» y no «ninguno»: que no pida un permiso extra no
    // significa que esté abierta a todo el mundo, hace falta `show_ai` para llegar al asistente.
    final requiere = [
      if (permiso != null) permiso,
      if (soloAdmin) 'administrador',
    ].join(' + ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 300,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${h['que_hace']}',
                    style: TextStyle(fontSize: 13, color: c.ink)),
                Text('${h['nombre']}',
                    style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: c.ink3)),
              ],
            ),
          ),
          SizedBox(
            width: 180,
            child: Text(
              requiere.isEmpty ? 'Cualquiera con acceso al asistente' : requiere,
              style: TextStyle(
                  fontSize: 12,
                  color: requiere.isEmpty ? c.ink3 : c.ink,
                  fontStyle: requiere.isEmpty ? FontStyle.italic : FontStyle.normal),
            ),
          ),
          SizedBox(
            width: 60,
            child: Icon(
              tuya ? Icons.check_circle : Icons.remove_circle_outline,
              size: 18,
              color: tuya ? c.success : c.ink3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _celda(String texto, double ancho, {bool encabezado = false}) => SizedBox(
        width: ancho,
        child: Text(texto,
            style: TextStyle(
                fontSize: encabezado ? 10 : 13,
                letterSpacing: encabezado ? 0.6 : 0,
                fontWeight: encabezado ? FontWeight.w700 : FontWeight.w400,
                color: c.ink3)),
      );
}
