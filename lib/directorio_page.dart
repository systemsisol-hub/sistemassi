import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'theme/si_theme.dart';

/// Directorio interno: nombre, ubicación y cómo contactar a cada quien.
///
/// ─── Sólo personal vigente ───────────────────────────────────────────────────
///
/// `profiles` tiene 2488 registros, pero **2192 son bajas**. Un directorio con todos sería 88% de
/// exempleados —inútil para buscar a un compañero, y además publicaría el celular de gente que ya
/// no trabaja aquí.
///
/// Se filtra por las DOS señales a la vez: `status_rh` vigente **y** sin `fecha_baja`. Las dos se
/// contradicen en unos 45 casos, así que se toma la intersección: quedan 283 personas. Omitir a
/// alguien vigente por un dato mal capturado se nota y se corrige; publicar a quien ya se fue, no.
class DirectorioPage extends StatefulWidget {
  const DirectorioPage({super.key});

  @override
  State<DirectorioPage> createState() => _DirectorioPageState();
}

class _DirectorioPageState extends State<DirectorioPage> {
  final _supabase = Supabase.instance.client;
  final _buscarCtrl = TextEditingController();

  bool _cargando = true;
  String? _error;
  List<_Persona> _personas = [];
  String _busqueda = '';
  String _ubicacion = 'todas';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _buscarCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final datos = await _supabase
          .from('profiles')
          .select('numero_empleado, nombre, paterno, materno, full_name, puesto, area, '
              'ubicacion, empresa, telefono, celular, mail_user, email, foto_url')
          .inFilter('status_rh', ['ACTIVO', 'CAMBIO', 'REINGRESO'])
          .isFilter('fecha_baja', null)
          .order('nombre');

      _personas = [
        for (final p in List<Map<String, dynamic>>.from(datos)) _Persona.de(p),
      ]..sort((a, b) => a.nombre.compareTo(b.nombre));

      if (mounted) setState(() => _cargando = false);
    } catch (e) {
      debugPrint('directorio: $e');
      if (mounted) {
        setState(() {
          _cargando = false;
          _error = '$e';
        });
      }
    }
  }

  List<String> get _ubicaciones {
    final u = _personas
        .map((p) => p.ubicacion)
        .where((x) => x.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return u;
  }

  List<_Persona> get _filtradas {
    final q = _busqueda.trim().toLowerCase();
    return _personas.where((p) {
      if (_ubicacion != 'todas' && p.ubicacion != _ubicacion) return false;
      if (q.isEmpty) return true;
      return p.coincide(q);
    }).toList();
  }

  Future<void> _copiar(String valor, String que) async {
    await Clipboard.setData(ClipboardData(text: valor));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$que copiado'), duration: const Duration(seconds: 2)),
    );
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
                  child: Text('No se pudo cargar el directorio: $_error',
                      style: TextStyle(fontSize: 13, color: c.danger)),
                )
              : Column(
                  children: [
                    _barraBusqueda(c),
                    Expanded(child: _lista(c)),
                  ],
                ),
    );
  }

  Widget _barraBusqueda(SiColors c) {
    final total = _personas.length;
    final visibles = _filtradas.length;

    return Container(
      padding: const EdgeInsets.fromLTRB(
          SiSpace.x6, SiSpace.x4, SiSpace.x6, SiSpace.x3),
      decoration: BoxDecoration(
        color: c.panel,
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: TextField(
                controller: _buscarCtrl,
                onChanged: (v) => setState(() => _busqueda = v),
                style: const TextStyle(fontSize: 13.5),
                decoration: InputDecoration(
                  hintText: 'Buscar por nombre, puesto, área, ubicación, teléfono o correo…',
                  hintStyle: TextStyle(fontSize: 13, color: c.ink4),
                  prefixIcon: Icon(Icons.search, size: 18, color: c.ink3),
                  suffixIcon: _busqueda.isEmpty
                      ? null
                      : IconButton(
                          icon: Icon(Icons.close, size: 17, color: c.ink3),
                          onPressed: () {
                            _buscarCtrl.clear();
                            setState(() => _busqueda = '');
                          },
                        ),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: SiRadius.rMd),
                ),
              ),
            ),
            const SizedBox(width: SiSpace.x3),
            Text(
              visibles == total ? '$total personas' : '$visibles de $total',
              style: TextStyle(fontSize: 12, color: c.ink3),
            ),
          ]),
          const SizedBox(height: SiSpace.x3),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _chipUbicacion(c, 'todas', 'Todas'),
              for (final u in _ubicaciones) _chipUbicacion(c, u, u),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _chipUbicacion(SiColors c, String valor, String etiqueta) {
    final activo = _ubicacion == valor;
    return Padding(
      padding: const EdgeInsets.only(right: SiSpace.x2),
      child: InkWell(
        onTap: () => setState(() => _ubicacion = valor),
        borderRadius: SiRadius.rPill,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: activo ? c.brand : c.bg,
            borderRadius: SiRadius.rPill,
            border: Border.all(color: activo ? c.brand : c.line),
          ),
          child: Text(
            etiqueta.replaceAll('_', ' '),
            style: TextStyle(
                fontSize: 12,
                fontWeight: activo ? FontWeight.w600 : FontWeight.normal,
                color: activo ? Colors.white : c.ink2),
          ),
        ),
      ),
    );
  }

  Widget _lista(SiColors c) {
    final filas = _filtradas;
    if (filas.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(SiSpace.x8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.person_search_outlined, size: 44, color: c.line),
              const SizedBox(height: SiSpace.x3),
              Text('Nadie coincide con la búsqueda',
                  style: TextStyle(fontSize: 13, color: c.ink3)),
            ],
          ),
        ),
      );
    }

    // SelectionArea para poder copiar a mano un fragmento; además cada dato de contacto se copia
    // completo con un toque, que es lo que uno quiere de un directorio.
    return SelectionArea(
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(
            horizontal: SiSpace.x6, vertical: SiSpace.x4),
        itemCount: filas.length,
        separatorBuilder: (_, __) => Divider(height: 1, color: c.line2),
        itemBuilder: (ctx, i) => _fila(c, filas[i]),
      ),
    );
  }

  Widget _fila(SiColors c, _Persona p) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SiSpace.x3),
      child: LayoutBuilder(
        builder: (context, box) {
          final identidad = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _avatar(c, p),
              const SizedBox(width: SiSpace.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.nombre,
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: c.ink)),
                    if (p.puesto.isNotEmpty)
                      Text(p.puesto,
                          style: TextStyle(fontSize: 12, color: c.ink2)),
                    Text(
                      [
                        if (p.numero.isNotEmpty) '#${p.numero}',
                        if (p.area.isNotEmpty) p.area,
                        if (p.ubicacion.isNotEmpty) p.ubicacion.replaceAll('_', ' '),
                      ].join(' · '),
                      style: TextStyle(fontSize: 11, color: c.ink3),
                    ),
                  ],
                ),
              ),
            ],
          );

          final contacto = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (p.correo.isNotEmpty)
                _contacto(c, Icons.mail_outline, p.correo, 'Correo'),
              if (p.celular.isNotEmpty)
                _contacto(c, Icons.smartphone_outlined, p.celular, 'Celular'),
              if (p.telefono.isNotEmpty)
                _contacto(c, Icons.phone_outlined, p.telefono, 'Teléfono'),
              if (p.correo.isEmpty && p.celular.isEmpty && p.telefono.isEmpty)
                Text('Sin datos de contacto',
                    style: TextStyle(fontSize: 11.5, color: c.ink4)),
            ],
          );

          // Abajo de 760px el contacto no cabe al lado sin cortar los correos.
          if (box.maxWidth < 760) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                identidad,
                const SizedBox(height: SiSpace.x2),
                Padding(
                  padding: const EdgeInsets.only(left: 46),
                  child: contacto,
                ),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: identidad),
              const SizedBox(width: SiSpace.x4),
              Expanded(flex: 2, child: contacto),
            ],
          );
        },
      ),
    );
  }

  Widget _avatar(SiColors c, _Persona p) {
    if (p.fotoUrl.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          p.fotoUrl,
          width: 34, height: 34, fit: BoxFit.cover,
          // Si la foto no carga se cae a las iniciales, en lugar de dejar el hueco roto.
          errorBuilder: (_, __, ___) => _iniciales(c, p),
        ),
      );
    }
    return _iniciales(c, p);
  }

  Widget _iniciales(SiColors c, _Persona p) {
    return Container(
      width: 34, height: 34,
      decoration: BoxDecoration(color: c.brandTint, shape: BoxShape.circle),
      child: Center(
        child: Text(p.iniciales,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: c.brand)),
      ),
    );
  }

  Widget _contacto(SiColors c, IconData icono, String valor, String que) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: InkWell(
        onTap: () => _copiar(valor, que),
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
          child: Row(children: [
            Icon(icono, size: 13, color: c.ink4),
            const SizedBox(width: 7),
            Expanded(
              child: Text(valor,
                  style: TextStyle(fontSize: 12, color: c.ink2),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 4),
            Tooltip(
              message: 'Copiar $que'.toLowerCase(),
              child: Icon(Icons.copy_rounded, size: 12, color: c.ink4),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Persona {
  _Persona({
    required this.nombre,
    required this.numero,
    required this.puesto,
    required this.area,
    required this.ubicacion,
    required this.telefono,
    required this.celular,
    required this.correo,
    required this.fotoUrl,
  });

  factory _Persona.de(Map<String, dynamic> p) {
    String t(dynamic v) => (v ?? '').toString().trim();

    // El nombre completo se arma con los componentes y no con `full_name`, porque 24 de los 2488
    // perfiles lo tienen desfasado —hay quien guarda el materno pero no lo refleja ahí—.
    final partes = [t(p['nombre']), t(p['paterno']), t(p['materno'])]
        .where((x) => x.isNotEmpty)
        .join(' ');

    return _Persona(
      nombre: partes.isNotEmpty ? partes : (t(p['full_name']).isNotEmpty
          ? t(p['full_name'])
          : 'Sin nombre'),
      numero: t(p['numero_empleado']).replaceFirst(RegExp(r'^0+'), ''),
      puesto: t(p['puesto']),
      area: t(p['area']),
      ubicacion: t(p['ubicacion']),
      telefono: t(p['telefono']),
      celular: t(p['celular']),
      // Los dos guardan el mismo valor, pero la cobertura difiere en una docena de perfiles.
      correo: t(p['mail_user']).isNotEmpty ? t(p['mail_user']) : t(p['email']),
      fotoUrl: t(p['foto_url']),
    );
  }

  final String nombre;
  final String numero;
  final String puesto;
  final String area;
  final String ubicacion;
  final String telefono;
  final String celular;
  final String correo;
  final String fotoUrl;

  String get iniciales {
    final partes = nombre.split(RegExp(r'\s+')).where((x) => x.isNotEmpty).toList();
    if (partes.isEmpty) return '?';
    if (partes.length == 1) return partes.first[0].toUpperCase();
    return (partes[0][0] + partes[1][0]).toUpperCase();
  }

  /// Se busca también por teléfono y correo: llega una llamada perdida y se quiere saber de quién.
  /// Los dígitos se comparan sin espacios ni guiones, que es como los teclea la gente.
  bool coincide(String q) {
    final soloDigitos = q.replaceAll(RegExp(r'\D'), '');
    bool tel(String v) =>
        soloDigitos.isNotEmpty && v.replaceAll(RegExp(r'\D'), '').contains(soloDigitos);

    return nombre.toLowerCase().contains(q) ||
        puesto.toLowerCase().contains(q) ||
        area.toLowerCase().contains(q) ||
        ubicacion.toLowerCase().replaceAll('_', ' ').contains(q) ||
        correo.toLowerCase().contains(q) ||
        numero.contains(q) ||
        tel(telefono) ||
        tel(celular);
  }
}
