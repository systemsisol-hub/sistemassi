import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'theme/si_theme.dart';

/// Lo que SOL sabe del Drive, para revisarlo: cada carpeta y archivo que vio, qué leyó de cada PDF y
/// cuándo se actualizó por última vez.
///
/// Pedido del usuario el 23/09/2026: «que todo lo que lee se pueda ver en la pestaña de
/// configuración para revisarlo». Por eso el texto de cada PDF se abre aquí TAL CUAL lo tiene SOL, y
/// no un resumen: lo que se revisa tiene que ser lo mismo que SOL lee.
///
/// Lo llena la función `drive-sync`. Esta pantalla sólo la dispara y lo muestra; las tablas no se
/// pueden escribir desde la aplicación.
class SolDrivePanel extends StatefulWidget {
  const SolDrivePanel({super.key});

  @override
  State<SolDrivePanel> createState() => _SolDrivePanelState();
}

class _SolDrivePanelState extends State<SolDrivePanel> {
  final _supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _desarrollos = [];
  List<Map<String, dynamic>> _archivos = [];
  final Map<String, Map<String, dynamic>> _ultima = {};
  bool _cargando = true;
  bool _actualizando = false;
  String? _error;
  Timer? _sondeo;

  static const _pendientes = {'PENDIENTE', 'LEYENDO'};

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _sondeo?.cancel();
    super.dispose();
  }

  int get _porLeer =>
      _archivos.where((a) => _pendientes.contains(a['estado'])).length;

  Future<void> _cargar() async {
    try {
      final des = await _supabase
          .from('desarrollos')
          .select('id, nombre, drive_carpeta_id')
          .not('drive_carpeta_id', 'is', null)
          .order('nombre', ascending: true);
      // Sin el texto: son cientos de KB y aquí sólo hace falta al abrir un archivo.
      final arch = await _supabase
          .from('drive_archivos')
          .select('id, desarrollo_id, ruta, nombre, es_carpeta, enlace, modificado, tamano, '
              'estado, error, paginas, pagina_siguiente, leido_en')
          .order('ruta', ascending: true)
          .order('nombre', ascending: true);
      final sinc = await _supabase
          .from('drive_sincronizaciones')
          .select()
          .order('iniciada_en', ascending: false)
          .limit(20);
      final ultima = <String, Map<String, dynamic>>{};
      for (final s in (sinc as List).cast<Map<String, dynamic>>()) {
        ultima.putIfAbsent(s['desarrollo_id'].toString(), () => s);
      }
      if (!mounted) return;
      setState(() {
        _desarrollos = (des as List).cast<Map<String, dynamic>>();
        _archivos = (arch as List).cast<Map<String, dynamic>>();
        _ultima
          ..clear()
          ..addAll(ultima);
        _cargando = false;
        _error = null;
      });
      _vigilar();
    } catch (e) {
      debugPrint('Error al cargar el Drive de SOL: $e');
      if (mounted) setState(() { _cargando = false; _error = '$e'; });
    }
  }

  /// Mientras haya PDF por leer, la lectura sigue en el servidor sin esta pantalla. Esto sólo
  /// refresca para ver cómo avanza.
  void _vigilar() {
    _sondeo?.cancel();
    if (_porLeer > 0) {
      _sondeo = Timer(const Duration(seconds: 5), () {
        if (mounted) _cargar();
      });
    }
  }

  Future<void> _pedir(String accion) async {
    setState(() => _actualizando = true);
    try {
      final r = await _supabase.functions.invoke('drive-sync', body: {'accion': accion});
      final d = (r.data as Map?)?.cast<String, dynamic>() ?? {};
      if (d['error'] != null) throw d['error'];
      final fallos = ((d['resultados'] as List?) ?? const [])
          .cast<Map>()
          .where((x) => x['error'] != null)
          .map((x) => '${x['desarrollo']}: ${x['error']}')
          .toList();
      _aviso(fallos.isNotEmpty
          ? 'No se pudo actualizar. ${fallos.join(' · ')}'
          : accion == 'sincronizar'
              ? 'Carpeta actualizada. Los PDF se leen en segundo plano.'
              : 'Se reanudó la lectura.',
          error: fallos.isNotEmpty);
    } catch (e) {
      _aviso('No se pudo actualizar: $e', error: true);
    } finally {
      if (mounted) setState(() => _actualizando = false);
      await _cargar();
    }
  }

  void _aviso(String texto, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(texto),
      backgroundColor: error ? SiColors.of(context).danger : null,
    ));
  }

  Future<void> _abrirTexto(Map<String, dynamic> a) async {
    String? texto;
    String? falla;
    try {
      final r = await _supabase
          .from('drive_archivos')
          .select('texto')
          .eq('id', a['id'])
          .maybeSingle();
      texto = r?['texto'] as String?;
    } catch (e) {
      falla = '$e';
    }
    if (!mounted) return;
    final c = SiColors.of(context);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(a['nombre'].toString(),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        content: SizedBox(
          width: 720,
          height: 520,
          child: falla != null
              ? Text('No se pudo leer: $falla', style: TextStyle(color: c.danger))
              : (texto == null || texto.isEmpty)
                  ? Text(_explicacion(a), style: TextStyle(color: c.ink3))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Esto es exactamente lo que SOL tiene de este archivo: '
                          '${_numero(texto.length)} caracteres'
                          '${a['paginas'] != null ? ' de ${a['paginas']} páginas' : ''}.',
                          style: TextStyle(fontSize: 12, color: c.ink3),
                        ),
                        const SizedBox(height: SiSpace.x2),
                        Expanded(
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(SiSpace.x3),
                            decoration: BoxDecoration(
                              color: c.bg,
                              border: Border.all(color: c.line),
                              borderRadius: SiRadius.rSm,
                            ),
                            child: SingleChildScrollView(
                              child: SelectableText(texto,
                                  style: TextStyle(
                                      fontSize: 12, height: 1.45, color: c.ink2,
                                      fontFamily: 'monospace')),
                            ),
                          ),
                        ),
                      ],
                    ),
        ),
        actions: [
          TextButton(
            onPressed: () => launchUrl(Uri.parse(a['enlace'].toString()),
                mode: LaunchMode.externalApplication),
            child: const Text('Abrir en el Drive'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
        ],
      ),
    );
  }

  String _explicacion(Map<String, dynamic> a) {
    switch (a['estado']) {
      case 'PENDIENTE':
        return 'Todavía no se lee. De este archivo SOL sólo conoce el nombre.';
      case 'LEYENDO':
        return 'Se está leyendo: va en la página ${a['pagina_siguiente'] ?? '?'} de ${a['paginas'] ?? '?'}.';
      case 'SIN_TEXTO':
        return 'El PDF no tiene texto: es un escaneo o un plano hecho de imagen. SOL sólo conoce el nombre.';
      case 'NO_SE_LEE':
        return 'No es un PDF. SOL conoce el nombre y el enlace, no el contenido.';
      case 'ERROR':
        return 'No se pudo leer: ${a['error'] ?? 'sin detalle'}';
      default:
        return 'SOL no tiene texto de este archivo.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = SiColors.of(context);
    if (_cargando) {
      return const Padding(
        padding: EdgeInsets.all(SiSpace.x4),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Text('No se pudo leer el Drive de SOL: $_error',
          style: TextStyle(fontSize: 12.5, color: c.danger));
    }
    if (_desarrollos.isEmpty) {
      return Text('Ningún desarrollo tiene carpeta del Drive asignada.',
          style: TextStyle(fontSize: 12.5, color: c.ink3));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SOL recorre la carpeta pública de cada desarrollo y lee el texto de sus PDF. Lo que no '
          'aparece aquí, SOL no lo sabe.',
          style: TextStyle(fontSize: 12.5, color: c.ink3, height: 1.5),
        ),
        const SizedBox(height: SiSpace.x3),
        Wrap(
          spacing: SiSpace.x2,
          runSpacing: SiSpace.x2,
          children: [
            FilledButton.icon(
              onPressed: _actualizando ? null : () => _pedir('sincronizar'),
              icon: _actualizando
                  ? const SizedBox(
                      width: 14, height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.sync, size: 16),
              label: const Text('Actualizar desde el Drive'),
            ),
            // Por si la lectura se detuvo: la reanuda desde donde iba.
            if (_porLeer > 0)
              OutlinedButton.icon(
                onPressed: _actualizando ? null : () => _pedir('leer'),
                icon: const Icon(Icons.play_arrow, size: 16),
                label: const Text('Seguir leyendo'),
              ),
          ],
        ),
        for (final d in _desarrollos) ...[
          const SizedBox(height: SiSpace.x4),
          _desarrollo(c, d),
        ],
      ],
    );
  }

  Widget _desarrollo(SiColors c, Map<String, dynamic> d) {
    final id = d['id'].toString();
    final mios = _archivos.where((a) => a['desarrollo_id'].toString() == id).toList();
    final archivos = mios.where((a) => a['es_carpeta'] != true).toList();
    final cuenta = <String, int>{};
    for (final a in archivos) {
      final e = (a['estado'] ?? '').toString();
      cuenta[e] = (cuenta[e] ?? 0) + 1;
    }
    final u = _ultima[id];

    // Agrupados por la carpeta de primer nivel, que es como está organizado el Drive.
    final grupos = <String, List<Map<String, dynamic>>>{};
    for (final a in archivos) {
      final ruta = (a['ruta'] ?? '').toString();
      final raiz = ruta.isEmpty ? '(en la carpeta principal)' : ruta.split('/').first;
      grupos.putIfAbsent(raiz, () => []).add(a);
    }
    final nombres = grupos.keys.toList()..sort(_ordenNatural);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(d['nombre'].toString(),
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.ink)),
            const SizedBox(width: SiSpace.x2),
            TextButton.icon(
              onPressed: () => launchUrl(
                  Uri.parse('https://drive.google.com/drive/folders/${d['drive_carpeta_id']}'),
                  mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.open_in_new, size: 14),
              label: const Text('Abrir carpeta', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: SiSpace.x1),
        _ultimaVez(c, u),
        const SizedBox(height: SiSpace.x3),
        Wrap(
          spacing: SiSpace.x2,
          runSpacing: SiSpace.x2,
          children: [
            _chip(c, '${mios.length - archivos.length} carpetas', c.ink3, c.hover),
            _chip(c, '${archivos.length} archivos', c.ink3, c.hover),
            if ((cuenta['LEIDO'] ?? 0) > 0)
              _chip(c, '${cuenta['LEIDO']} leídos', c.success, c.successTint),
            if ((cuenta['PENDIENTE'] ?? 0) + (cuenta['LEYENDO'] ?? 0) > 0)
              _chip(c, '${(cuenta['PENDIENTE'] ?? 0) + (cuenta['LEYENDO'] ?? 0)} por leer',
                  c.warn, c.warnTint),
            if ((cuenta['SIN_TEXTO'] ?? 0) > 0)
              _chip(c, '${cuenta['SIN_TEXTO']} sin texto', c.ink3, c.hover),
            if ((cuenta['NO_SE_LEE'] ?? 0) > 0)
              _chip(c, '${cuenta['NO_SE_LEE']} no son PDF', c.ink3, c.hover),
            if ((cuenta['ERROR'] ?? 0) > 0)
              _chip(c, '${cuenta['ERROR']} con error', c.danger, c.dangerTint),
          ],
        ),
        const SizedBox(height: SiSpace.x3),
        if (archivos.isEmpty)
          Text('Todavía no se ha recorrido. Usa «Actualizar desde el Drive».',
              style: TextStyle(fontSize: 12.5, color: c.ink3))
        else
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: c.line),
              borderRadius: SiRadius.rSm,
            ),
            child: Column(
              children: [
                for (final g in nombres)
                  _grupo(c, g, grupos[g]!),
              ],
            ),
          ),
      ],
    );
  }

  Widget _ultimaVez(SiColors c, Map<String, dynamic>? u) {
    if (u == null) {
      return Text('Nunca se ha actualizado.', style: TextStyle(fontSize: 12.5, color: c.ink3));
    }
    final cuando = _fecha(u['terminada_en'] ?? u['iniciada_en']);
    if (u['error'] != null) {
      return Text('La última actualización ($cuando) FALLÓ: ${u['error']}',
          style: TextStyle(fontSize: 12.5, color: c.danger, fontWeight: FontWeight.w600));
    }
    if (u['terminada_en'] == null) {
      return Text('Actualizando desde $cuando…', style: TextStyle(fontSize: 12.5, color: c.warn));
    }
    return Text(
      'Actualizado $cuando: ${u['nuevos'] ?? 0} nuevos, ${u['cambiados'] ?? 0} cambiados, '
      '${u['quitados'] ?? 0} quitados.',
      style: TextStyle(fontSize: 12.5, color: c.ink2),
    );
  }

  Widget _grupo(SiColors c, String nombre, List<Map<String, dynamic>> archivos) {
    final leidos = archivos.where((a) => a['estado'] == 'LEIDO').length;
    final problemas = archivos.where((a) => a['estado'] == 'ERROR').length;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        dense: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: SiSpace.x3),
        leading: Icon(Icons.folder_outlined, size: 18, color: c.ink3),
        title: Text(nombre, style: TextStyle(fontSize: 13, color: c.ink)),
        subtitle: Text(
          '${archivos.length} archivos · $leidos leídos'
          '${problemas > 0 ? ' · $problemas con error' : ''}',
          style: TextStyle(fontSize: 11.5, color: problemas > 0 ? c.danger : c.ink3),
        ),
        children: [
          for (final a in archivos) _archivo(c, a),
        ],
      ),
    );
  }

  Widget _archivo(SiColors c, Map<String, dynamic> a) {
    final ruta = (a['ruta'] ?? '').toString();
    final sub = ruta.contains('/') ? ruta.substring(ruta.indexOf('/') + 1) : '';
    final detalle = [
      if (sub.isNotEmpty) sub,
      if (a['modificado'] != null) a['modificado'].toString(),
      if (a['tamano'] != null) _peso(a['tamano'] as num),
      if (a['paginas'] != null) '${a['paginas']} págs.',
    ].join(' · ');
    return InkWell(
      onTap: () => _abrirTexto(a),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(SiSpace.x8, SiSpace.x2, SiSpace.x3, SiSpace.x2),
        child: Row(
          children: [
            Icon(_icono(a), size: 16, color: c.ink3),
            const SizedBox(width: SiSpace.x2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a['nombre'].toString(),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: c.ink)),
                  if (detalle.isNotEmpty)
                    Text(detalle,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: c.ink4)),
                  if (a['estado'] == 'ERROR' && a['error'] != null)
                    Text(a['error'].toString(),
                        style: TextStyle(fontSize: 11, color: c.danger)),
                ],
              ),
            ),
            const SizedBox(width: SiSpace.x2),
            _estado(c, a),
          ],
        ),
      ),
    );
  }

  Widget _estado(SiColors c, Map<String, dynamic> a) {
    switch (a['estado']) {
      case 'LEIDO':
        return _chip(c, 'Leído', c.success, c.successTint);
      case 'LEYENDO':
        return _chip(c, 'Leyendo p. ${a['pagina_siguiente'] ?? '?'}', c.warn, c.warnTint);
      case 'PENDIENTE':
        return _chip(c, 'Por leer', c.warn, c.warnTint);
      case 'SIN_TEXTO':
        return _chip(c, 'Sin texto', c.ink3, c.hover);
      case 'NO_SE_LEE':
        return _chip(c, 'No es PDF', c.ink3, c.hover);
      case 'ERROR':
        return _chip(c, 'Error', c.danger, c.dangerTint);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _chip(SiColors c, String texto, Color tinta, Color fondo) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: SiSpace.x2, vertical: 2),
      decoration: BoxDecoration(color: fondo, borderRadius: SiRadius.rPill),
      child: Text(texto,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: tinta)),
    );
  }

  IconData _icono(Map<String, dynamic> a) {
    final n = a['nombre'].toString().toLowerCase();
    if (n.endsWith('.pdf')) return Icons.picture_as_pdf_outlined;
    if (n.endsWith('.png') || n.endsWith('.jpg') || n.endsWith('.jpeg')) return Icons.image_outlined;
    return Icons.insert_drive_file_outlined;
  }

  /// «1. Brochure» antes que «11. Checklist», y «2. Listas» antes que ambos: por el número.
  static int _ordenNatural(String a, String b) {
    final na = int.tryParse(RegExp(r'^\d+').stringMatch(a) ?? '');
    final nb = int.tryParse(RegExp(r'^\d+').stringMatch(b) ?? '');
    if (na != null && nb != null && na != nb) return na.compareTo(nb);
    if (na != null && nb == null) return -1;
    if (na == null && nb != null) return 1;
    return a.toLowerCase().compareTo(b.toLowerCase());
  }

  static String _peso(num bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / 1048576).toStringAsFixed(1)} MB';
  }

  static String _numero(int n) {
    final s = n.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }

  static String _fecha(dynamic iso) {
    final d = DateTime.tryParse(iso?.toString() ?? '')?.toLocal();
    if (d == null) return '—';
    String dos(int n) => n.toString().padLeft(2, '0');
    return '${dos(d.day)}/${dos(d.month)}/${d.year} ${dos(d.hour)}:${dos(d.minute)}';
  }
}
