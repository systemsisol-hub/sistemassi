import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'services/telefono_whatsapp.dart';
import 'theme/si_theme.dart';

/// Panel del puente de WhatsApp: qué números atiende Soli y qué pasó con cada mensaje.
///
/// ─── Dos cosas que no son evidentes ──────────────────────────────────────────
///
/// **La resolución del teléfono la hace la base, no esta pantalla.** Se llama a
/// `whatsapp_resolver_telefono`, la misma función que usa el webhook al recibir un mensaje. Si el
/// panel resolviera por su cuenta podrían discrepar, y alguien quedaría autorizado en la lista pero
/// sin respuesta en el teléfono —o al revés—.
///
/// **La bitácora es la única forma de explicar un rechazo.** A un número no autorizado no se le
/// contesta nada, por decisión tomada: no se le confirma que del otro lado hay un sistema con datos
/// de empleados. Eso significa que quien escribió no recibe explicación, y la llamada llega a
/// Sistemas. Aquí está la respuesta.
class WhatsappPage extends StatefulWidget {
  const WhatsappPage({super.key});

  @override
  State<WhatsappPage> createState() => _WhatsappPageState();
}

class _WhatsappPageState extends State<WhatsappPage> {
  final _supabase = Supabase.instance.client;

  bool _cargando = true;
  String? _error;
  List<Map<String, dynamic>> _autorizados = [];
  List<Map<String, dynamic>> _bitacora = [];
  int _pestana = 0;
  bool _activandoFirma = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  /// Le pide a la función que registre el secreto de firma en el webhook de OpenWA.
  ///
  /// Se hace por la función y no desde aquí porque los dos secretos que hacen falta —la llave de la
  /// API de OpenWA y el secreto de firma— viven en Supabase, y no tienen por qué salir. La función ya
  /// usa los dos: con la llave manda las respuestas y con el secreto verifica lo que entra.
  ///
  /// Es idempotente: actualiza el webhook que ya existe en lugar de crear otro. Crear uno segundo
  /// haría llegar cada mensaje dos veces, que es un fallo que ya se arregló una vez.
  Future<void> _activarFirma() async {
    setState(() => _activandoFirma = true);
    try {
      final r = await _supabase.functions.invoke(
        'whatsapp-openwa',
        body: {'accion': 'activar_firma'},
      );
      final datos = (r.data as Map?)?.cast<String, dynamic>() ?? {};
      if (!mounted) return;
      final ok = datos['ok'] == true;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: ok ? null : Theme.of(context).colorScheme.error,
        duration: Duration(seconds: ok ? 10 : 8),
        content: Text(ok
            ? '${datos['mensaje']}'
            : 'No se pudo: ${datos['error'] ?? 'error desconocido'}'),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Theme.of(context).colorScheme.error,
        content: Text('No se pudo activar la firma: $e'),
      ));
    } finally {
      if (mounted) setState(() => _activandoFirma = false);
    }
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final aut = await _supabase
          .from('whatsapp_autorizados')
          // El perfil se trae anidado para mostrar a quién pertenece el número sin una segunda
          // consulta por cada renglón.
          .select('telefono, activo, notas, creado_en, profile_id, '
              'profiles!whatsapp_autorizados_profile_id_fkey('
              'nombre, paterno, materno, full_name, puesto, permissions, role)')
          .order('creado_en', ascending: false);
      _autorizados = List<Map<String, dynamic>>.from(aut);

      final bit = await _supabase
          .from('whatsapp_bitacora')
          .select('telefono, resultado, pregunta, detalle, creado_en')
          .order('creado_en', ascending: false)
          .limit(200);
      _bitacora = List<Map<String, dynamic>>.from(bit);

      if (mounted) setState(() => _cargando = false);
    } catch (e) {
      debugPrint('whatsapp: $e');
      if (mounted) {
        setState(() {
          _cargando = false;
          _error = '$e';
        });
      }
    }
  }

  Future<void> _alternarActivo(Map<String, dynamic> fila) async {
    try {
      await _supabase
          .from('whatsapp_autorizados')
          .update({'activo': fila['activo'] != true})
          .eq('telefono', fila['telefono']);
      await _cargar();
    } catch (e) {
      _avisar('No se pudo cambiar: $e', esError: true);
    }
  }

  Future<void> _borrar(Map<String, dynamic> fila) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Quitar el número?'),
        content: Text(
            'Soli dejará de responderle a ${TelefonoWhatsApp.bonito(fila['telefono'])}. '
            'Si sólo quieres pausarlo, apágalo en lugar de quitarlo.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Quitar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _supabase
          .from('whatsapp_autorizados')
          .delete()
          .eq('telefono', fila['telefono']);
      await _cargar();
    } catch (e) {
      _avisar('No se pudo quitar: $e', esError: true);
    }
  }

  void _avisar(String texto, {bool esError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(texto),
      backgroundColor: esError ? Colors.red : null,
    ));
  }

  Future<void> _abrirAlta() async {
    final guardado = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _AltaNumero(),
    );
    if (guardado == true) await _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);

    return Scaffold(
      backgroundColor: c.bg,
      body: _cargando
          ? Center(child: CircularProgressIndicator(color: c.brand))
          : _error != null
              ? Padding(
                  padding: const EdgeInsets.all(SiSpace.x6),
                  child: Text('No se pudo leer la configuración: $_error',
                      style: TextStyle(fontSize: 13, color: c.danger)),
                )
              : Column(
                  children: [
                    _barra(c),
                    Expanded(
                        child: _pestana == 0 ? _listaAutorizados(c) : _listaBitacora(c)),
                  ],
                ),
    );
  }

  Widget _barra(SiColors c) {
    final activos = _autorizados.where((a) => a['activo'] == true).length;
    return Container(
      padding: const EdgeInsets.fromLTRB(
          SiSpace.x5, SiSpace.x3, SiSpace.x5, SiSpace.x3),
      decoration: BoxDecoration(
        color: c.panel,
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: Row(
        children: [
          Icon(Icons.chat, size: 18, color: c.brand),
          const SizedBox(width: SiSpace.x2),
          Text('WhatsApp',
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700, color: c.ink)),
          const SizedBox(width: SiSpace.x5),
          _chip(c, 0, 'Autorizados', activos),
          const SizedBox(width: SiSpace.x2),
          _chip(c, 1, 'Bitácora', _bitacora.length),
          const Spacer(),
          // Activar la firma del webhook.
          //
          // Comprobado en los registros: al webhook le falta el campo `secret`, así que OpenWA no
          // firma sus entregas y la única credencial que llega es el `?k=` de la URL — que acaba
          // escrito en los registros de quien la llama. Esto se lo pide a la función, que ya tiene la
          // llave de OpenWA y el secreto: así ninguno de los dos sale de Supabase ni pasa por unas
          // manos. El panel de OpenWA no expone ese campo, de modo que por ahí no hay forma.
          Tooltip(
            message: 'Le pone el secreto de firma al webhook, para dejar de depender del ?k=',
            child: OutlinedButton.icon(
              onPressed: _activandoFirma ? null : _activarFirma,
              icon: _activandoFirma
                  ? const SizedBox(
                      width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.lock_outline, size: 16),
              label: const Text('Activar firma'),
            ),
          ),
          const SizedBox(width: SiSpace.x2),
          if (_pestana == 0)
            FilledButton.icon(
              onPressed: _abrirAlta,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Autorizar número'),
            )
          else
            OutlinedButton.icon(
              onPressed: _cargar,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Actualizar'),
            ),
        ],
      ),
    );
  }

  Widget _chip(SiColors c, int valor, String etiqueta, int n) {
    final activo = _pestana == valor;
    return InkWell(
      onTap: () => setState(() => _pestana = valor),
      borderRadius: SiRadius.rPill,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: activo ? c.brand : c.panel,
          borderRadius: SiRadius.rPill,
          border: Border.all(color: activo ? c.brand : c.line),
        ),
        child: Text('$etiqueta ($n)',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: activo ? Colors.white : c.ink2)),
      ),
    );
  }

  // ── Autorizados ────────────────────────────────────────────────────────────

  Widget _listaAutorizados(SiColors c) {
    if (_autorizados.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(SiSpace.x10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.chat_outlined, size: 36, color: c.ink4),
              const SizedBox(height: SiSpace.x3),
              Text(
                  'Todavía no hay números autorizados.\nSoli no responde a nadie por WhatsApp.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: c.ink3)),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(SiSpace.x5),
      itemCount: _autorizados.length,
      separatorBuilder: (_, __) => const SizedBox(height: SiSpace.x2),
      itemBuilder: (_, i) => _tarjetaAutorizado(c, _autorizados[i]),
    );
  }

  Widget _tarjetaAutorizado(SiColors c, Map<String, dynamic> a) {
    final perfil = a['profiles'] as Map<String, dynamic>?;
    final activo = a['activo'] == true;
    final nombre = _nombreDe(perfil);

    // Sin `show_ai` ni rol de administrador, Soli rechaza igual: es la puerta que ya tenía. Se avisa
    // aquí para que nadie dé de alta un número y luego no entienda por qué no contesta.
    final tienePuerta = perfil != null &&
        (perfil['role'] == 'admin' ||
            (perfil['permissions'] as Map?)?['show_ai'] == true);

    return Opacity(
      opacity: activo ? 1 : 0.55,
      child: Container(
        padding: const EdgeInsets.all(SiSpace.x4),
        decoration: BoxDecoration(
          color: c.panel,
          borderRadius: SiRadius.rMd,
          border: Border.all(color: c.line),
        ),
        child: Row(
          children: [
            Icon(activo ? Icons.check_circle : Icons.pause_circle_outline,
                size: 20, color: activo ? c.success : c.ink4),
            const SizedBox(width: SiSpace.x3),
            SizedBox(
              width: 120,
              child: Text(TelefonoWhatsApp.bonito(a['telefono'].toString()),
                  style: SiType.mono(size: 12.5, color: c.ink)),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(nombre ?? 'Sin colaborador asociado',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: nombre == null ? c.danger : c.ink)),
                  if (perfil?['puesto'] != null)
                    Text(perfil!['puesto'].toString(),
                        style: TextStyle(fontSize: 11.5, color: c.ink3),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  if (nombre != null && !tienePuerta)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                          'No tiene el permiso de Asistente IA: Soli no le va a responder.',
                          style: TextStyle(fontSize: 11, color: c.warn)),
                    ),
                ],
              ),
            ),
            IconButton(
              onPressed: () => _alternarActivo(a),
              icon: Icon(activo ? Icons.toggle_on : Icons.toggle_off, size: 26),
              color: activo ? c.success : c.ink4,
              tooltip: activo ? 'Apagar' : 'Prender',
            ),
            IconButton(
              onPressed: () => _borrar(a),
              icon: const Icon(Icons.delete_outline, size: 18),
              color: c.danger,
              tooltip: 'Quitar',
            ),
          ],
        ),
      ),
    );
  }

  static String? _nombreDe(Map<String, dynamic>? p) {
    if (p == null) return null;
    final partes = [p['nombre'], p['paterno'], p['materno']]
        .map((x) => (x ?? '').toString().trim())
        .where((x) => x.isNotEmpty)
        .join(' ');
    if (partes.isNotEmpty) return partes;
    final full = (p['full_name'] ?? '').toString().trim();
    return full.isEmpty ? null : full;
  }

  // ── Bitácora ───────────────────────────────────────────────────────────────

  Widget _listaBitacora(SiColors c) {
    if (_bitacora.isEmpty) {
      return Center(
        child: Text('Sin mensajes todavía',
            style: TextStyle(fontSize: 13, color: c.ink3)),
      );
    }
    final fmt = DateFormat('d MMM HH:mm', 'es_MX');

    return ListView.separated(
      padding: const EdgeInsets.all(SiSpace.x5),
      itemCount: _bitacora.length,
      separatorBuilder: (_, __) => Divider(height: 1, color: c.line2),
      itemBuilder: (_, i) {
        final b = _bitacora[i];
        final (color, etiqueta) = _estiloResultado(c, b['resultado'].toString());
        final fecha = DateTime.tryParse((b['creado_en'] ?? '').toString());

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: SiSpace.x2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 96,
                child: Text(
                    fecha == null ? '' : fmt.format(fecha.toLocal()),
                    style: TextStyle(fontSize: 11.5, color: c.ink3)),
              ),
              SizedBox(
                width: 110,
                child: Text(
                    TelefonoWhatsApp.bonito(b['telefono'].toString()),
                    style: SiType.mono(size: 11.5, color: c.ink2)),
              ),
              SizedBox(
                width: 116,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: SiRadius.rPill,
                  ),
                  child: Text(etiqueta,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: color)),
                ),
              ),
              const SizedBox(width: SiSpace.x2),
              Expanded(
                child: Text(
                    [
                      if ((b['pregunta'] ?? '').toString().isNotEmpty)
                        '«${b['pregunta']}»',
                      if ((b['detalle'] ?? '').toString().isNotEmpty)
                        b['detalle'].toString(),
                    ].join(' · '),
                    style: TextStyle(fontSize: 12, color: c.ink3),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Color y etiqueta de cada resultado. Los rechazos se distinguen entre sí a propósito: «no está
  /// en la lista» y «su teléfono empata con cinco personas» se arreglan de formas muy distintas.
  (Color, String) _estiloResultado(SiColors c, String r) => switch (r) {
        'ATENDIDO' => (c.success, 'Atendido'),
        'NO_AUTORIZADO' => (c.warn, 'No autorizado'),
        'SIN_REGISTRO' => (c.warn, 'Sin registro'),
        'AMBIGUO' => (c.danger, 'Teléfono repetido'),
        'SIN_PERMISO' => (c.warn, 'Sin permiso IA'),
        'LIMITE' => (c.warn, 'Límite'),
        // En gris y no en rojo: no es un fallo, es la decisión de no contestar en grupos. Sin este
        // caso caía en el `_` y salía como «Error», que manda a buscar una avería que no existe.
        // Se registra uno por grupo y por hora, así que un grupo activo no inunda esta lista.
        'GRUPO' => (c.ink3, 'Grupo (no se contesta)'),
        _ => (c.danger, 'Error'),
      };
}

// ── Alta de un número ────────────────────────────────────────────────────────

class _AltaNumero extends StatefulWidget {
  const _AltaNumero();

  @override
  State<_AltaNumero> createState() => _AltaNumeroState();
}

class _AltaNumeroState extends State<_AltaNumero> {
  final _tel = TextEditingController();
  final _notas = TextEditingController();

  String? _normalizado;
  bool _resolviendo = false;
  bool _guardando = false;

  /// Resultado de `whatsapp_resolver_telefono`: cuántos perfiles vigentes empatan.
  int? _coincidencias;
  String? _nombre;
  String? _profileId;
  bool _tienePuerta = false;

  @override
  void dispose() {
    _tel.dispose();
    _notas.dispose();
    super.dispose();
  }

  /// Resuelve con la MISMA función que usará el webhook.
  ///
  /// No se replica la consulta aquí: si el panel resolviera por su cuenta y las dos reglas se
  /// separaran, un número podría quedar autorizado en la lista y sin respuesta en el teléfono.
  Future<void> _resolver() async {
    final n = TelefonoWhatsApp.normalizar(_tel.text);
    setState(() {
      _normalizado = n;
      _coincidencias = null;
      _nombre = null;
      _profileId = null;
      _tienePuerta = false;
    });
    if (n == null) return;

    setState(() => _resolviendo = true);
    try {
      final r = await Supabase.instance.client
          .rpc('whatsapp_resolver_telefono', params: {'p_telefono': n});
      final filas = List<Map<String, dynamic>>.from(r as List);
      final fila = filas.isEmpty ? null : filas.first;
      final id = fila?['profile_id']?.toString();
      final n0 = (fila?['coincidencias'] as num?)?.toInt() ?? 0;

      Map<String, dynamic>? perfil;
      if (id != null) {
        perfil = await Supabase.instance.client
            .from('profiles')
            .select('nombre, paterno, materno, full_name, permissions, role')
            .eq('id', id)
            .maybeSingle();
      }
      if (!mounted) return;
      setState(() {
        _coincidencias = n0;
        _profileId = id;
        _nombre = perfil == null
            ? null
            : [perfil['nombre'], perfil['paterno'], perfil['materno']]
                .map((x) => (x ?? '').toString().trim())
                .where((x) => x.isNotEmpty)
                .join(' ');
        _tienePuerta = perfil != null &&
            (perfil['role'] == 'admin' ||
                (perfil['permissions'] as Map?)?['show_ai'] == true);
      });
    } catch (e) {
      if (mounted) setState(() => _coincidencias = -1);
      debugPrint('whatsapp: no se pudo resolver: $e');
    } finally {
      if (mounted) setState(() => _resolviendo = false);
    }
  }

  Future<void> _guardar() async {
    final n = _normalizado;
    if (n == null) return;
    setState(() => _guardando = true);
    try {
      await Supabase.instance.client.from('whatsapp_autorizados').insert({
        'telefono': n,
        'profile_id': _profileId,
        'notas': _notas.text.trim().isEmpty ? null : _notas.text.trim(),
        'creado_por': Supabase.instance.client.auth.currentUser?.id,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _guardando = false);
        final msg = '$e'.contains('duplicate') || '$e'.contains('23505')
            ? 'Ese número ya está en la lista.'
            : 'No se pudo guardar: $e';
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    final puedeGuardar = _normalizado != null && _coincidencias == 1;

    return Dialog(
      backgroundColor: c.panel,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(SiSpace.x5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Icon(Icons.chat_outlined, size: 18, color: c.brand),
                const SizedBox(width: SiSpace.x2),
                Text('Autorizar número',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: c.ink)),
              ]),
              const SizedBox(height: SiSpace.x4),
              TextField(
                controller: _tel,
                keyboardType: TextInputType.phone,
                onChanged: (_) => _resolver(),
                decoration: InputDecoration(
                  labelText: 'Teléfono',
                  hintText: '55 8018 0569',
                  helperText: 'Diez dígitos, con o sin lada de país',
                  border: OutlineInputBorder(borderRadius: SiRadius.rMd),
                  suffixIcon: _resolviendo
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                              width: 16,
                              height: 16,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : null,
                ),
              ),
              const SizedBox(height: SiSpace.x3),
              _resultado(c),
              const SizedBox(height: SiSpace.x3),
              TextField(
                controller: _notas,
                decoration: InputDecoration(
                  labelText: 'Notas (opcional)',
                  border: OutlineInputBorder(borderRadius: SiRadius.rMd),
                ),
              ),
              const SizedBox(height: SiSpace.x4),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                      onPressed: _guardando
                          ? null
                          : () => Navigator.pop(context, false),
                      child: const Text('Cancelar')),
                  const SizedBox(width: SiSpace.x2),
                  FilledButton(
                    onPressed: _guardando || !puedeGuardar ? null : _guardar,
                    child: Text(_guardando ? 'Guardando…' : 'Autorizar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Lo que se encontró, dicho con el detalle suficiente para poder actuar.
  Widget _resultado(SiColors c) {
    if (_tel.text.trim().isEmpty) return const SizedBox.shrink();

    if (_normalizado == null) {
      return _caja(c, c.warn, Icons.info_outline,
          'No parecen diez dígitos. Escribe el número completo, con o sin el 52.');
    }
    if (_coincidencias == null) return const SizedBox.shrink();

    return switch (_coincidencias!) {
      1 => _caja(
          c,
          _tienePuerta ? c.success : c.warn,
          _tienePuerta ? Icons.check_circle_outline : Icons.warning_amber_rounded,
          _tienePuerta
              ? 'Es ${_nombre ?? 'un colaborador vigente'}. Soli le responderá con sus datos.'
              : 'Es ${_nombre ?? 'un colaborador vigente'}, pero NO tiene el permiso de '
                  'Asistente IA. Puedes autorizarlo, y Soli no le contestará hasta que se '
                  'lo concedas en Usuarios.'),
      0 => _caja(
          c,
          c.danger,
          Icons.person_off_outlined,
          'Ese teléfono no está registrado con ningún colaborador vigente. Captúralo primero '
              'en su perfil; si no, Soli no sabría de quién son los datos.'),
      -1 => _caja(c, c.danger, Icons.error_outline,
          'No se pudo consultar. Revisa tu conexión e inténtalo de nuevo.'),
      _ => _caja(
          c,
          c.danger,
          Icons.groups_outlined,
          'Ese teléfono aparece en ${_coincidencias} perfiles vigentes. No se puede autorizar: '
              'no habría forma de saber a quién contestarle. Corrige los teléfonos duplicados '
              'en Colaboradores.'),
    };
  }

  Widget _caja(SiColors c, Color color, IconData icono, String texto) =>
      Container(
        padding: const EdgeInsets.all(SiSpace.x3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: SiRadius.rSm,
          border: Border.all(color: color),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icono, size: 16, color: color),
            const SizedBox(width: SiSpace.x2),
            Expanded(
              child: Text(texto,
                  style: TextStyle(fontSize: 12, height: 1.4, color: c.ink2)),
            ),
          ],
        ),
      );
}
