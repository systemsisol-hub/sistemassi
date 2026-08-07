import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'theme/si_theme.dart';

/// Directorio interno: nombre, ubicación y cómo contactar a cada quien.
///
/// ─── Quién ve los teléfonos ──────────────────────────────────────────────────
///
/// Un administrador ve todo; a los demás los teléfonos les llegan en NULL. El enmascarado NO está
/// aquí: lo hace la vista `directorio`, porque esconder una columna en la pantalla no la esconde
/// —la consulta la seguiría trayendo y cualquiera la leería desde la API—. Esta página sólo deja de
/// pintar lo que llega vacío, que es lo que ya hacía con quien no tiene celular capturado.
///
/// El número de empleado no se muestra a nadie, y tampoco viaja: la vista no lo expone.
///
/// ─── Sólo personal vigente ───────────────────────────────────────────────────
///
/// El filtro también se mudó a la vista. `profiles` tiene 2488 registros pero **2192 son bajas**, y
/// se exige `status_rh` vigente **y** sin `fecha_baja`: las dos señales se contradicen en unos 45
/// casos, así que se toma la intersección y quedan 283 personas.
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
  bool _esAdmin = false;
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
      // El rol se consulta sólo para redactar la ayuda del buscador: si a esta persona no le llegan
      // teléfonos, ofrecerle «buscar por teléfono» es prometer algo que no va a funcionar. El
      // enmascarado en sí no depende de esto, lo hace la vista.
      final uid = _supabase.auth.currentUser?.id;
      if (uid != null) {
        final perfil = await _supabase
            .from('profiles').select('role').eq('id', uid).maybeSingle();
        _esAdmin = perfil?['role'] == 'admin';
      }

      final datos = await _supabase
          .from('directorio')
          .select('nombre, paterno, materno, full_name, puesto, area, '
              'ubicacion, empresa, telefono, celular, mail_user, email, foto_url')
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

  /// Buscador y ubicación en un solo renglón y a la misma altura.
  ///
  /// Antes las 16 ubicaciones eran pastillas en una fila con desplazamiento horizontal: las de la
  /// derecha quedaban fuera de vista y nada indicaba que hubiera más. Un desplegable las muestra
  /// todas y ocupa un ancho fijo.
  Widget _barraBusqueda(SiColors c) {
    final total = _personas.length;
    final visibles = _filtradas.length;

    // Misma altura en los dos controles: el relleno vertical del campo y del desplegable se define
    // aquí una sola vez para que no se desalineen.
    const relleno = EdgeInsets.symmetric(horizontal: 12, vertical: 11);

    return Container(
      padding: const EdgeInsets.fromLTRB(
          SiSpace.x5, SiSpace.x3, SiSpace.x5, SiSpace.x3),
      decoration: BoxDecoration(
        color: c.panel,
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: TextField(
              controller: _buscarCtrl,
              onChanged: (v) => setState(() => _busqueda = v),
              style: const TextStyle(fontSize: 13.5),
              decoration: InputDecoration(
                hintText: _esAdmin
                    ? 'Buscar por nombre, puesto, área, teléfono o correo…'
                    : 'Buscar por nombre, puesto, área o correo…',
                hintStyle: TextStyle(fontSize: 13, color: c.ink4),
                prefixIcon: Icon(Icons.search, size: 18, color: c.ink3),
                prefixIconConstraints:
                    const BoxConstraints(minWidth: 38, minHeight: 0),
                suffixIcon: _busqueda.isEmpty
                    ? null
                    : InkWell(
                        onTap: () {
                          _buscarCtrl.clear();
                          setState(() => _busqueda = '');
                        },
                        child: Icon(Icons.close, size: 16, color: c.ink3),
                      ),
                suffixIconConstraints:
                    const BoxConstraints(minWidth: 34, minHeight: 0),
                isDense: true,
                contentPadding: relleno,
                border: OutlineInputBorder(borderRadius: SiRadius.rMd),
              ),
            ),
          ),
          const SizedBox(width: SiSpace.x3),
          SizedBox(
            width: 230,
            child: DropdownButtonFormField<String>(
              value: _ubicacion,
              isExpanded: true,
              isDense: true,
              style: TextStyle(fontSize: 13, color: c.ink),
              icon: Icon(Icons.expand_more, size: 18, color: c.ink3),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: relleno,
                prefixIcon: Icon(Icons.place_outlined, size: 16, color: c.ink3),
                prefixIconConstraints:
                    const BoxConstraints(minWidth: 34, minHeight: 0),
                border: OutlineInputBorder(borderRadius: SiRadius.rMd),
              ),
              items: [
                DropdownMenuItem(
                  value: 'todas',
                  child: Text('Todas las ubicaciones',
                      style: TextStyle(fontSize: 13, color: c.ink2)),
                ),
                for (final u in _ubicaciones)
                  DropdownMenuItem(
                    value: u,
                    child: Text(u.replaceAll('_', ' '),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: c.ink2)),
                  ),
              ],
              onChanged: (v) =>
                  setState(() => _ubicacion = v ?? 'todas'),
            ),
          ),
          const SizedBox(width: SiSpace.x3),
          Text(
            visibles == total ? '$total' : '$visibles de $total',
            style: TextStyle(
                fontSize: 12,
                color: c.ink3,
                fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ],
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
      child: LayoutBuilder(
        builder: (context, box) {
          // En una pantalla ancha un solo renglón por persona dejaba un hueco enorme entre el
          // nombre y sus datos de contacto, en los dos extremos. Con varias columnas ese espacio
          // se usa y se ve más gente sin desplazarse.
          final columnas = box.maxWidth >= 1500
              ? 3
              : box.maxWidth >= 1000
                  ? 2
                  : 1;

          // Se agrupa en renglones de `columnas` en lugar de armar columnas completas, para que
          // ListView siga construyendo sólo lo visible: son 283 personas.
          final grupos = <List<_Persona>>[];
          for (var i = 0; i < filas.length; i += columnas) {
            grupos.add(filas.sublist(
                i, (i + columnas).clamp(0, filas.length)));
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(
                horizontal: SiSpace.x5, vertical: SiSpace.x2),
            itemCount: grupos.length,
            separatorBuilder: (_, __) => Divider(height: 1, color: c.line2),
            itemBuilder: (ctx, i) {
              final grupo = grupos[i];
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var j = 0; j < columnas; j++) ...[
                    if (j > 0) const SizedBox(width: SiSpace.x5),
                    Expanded(
                      child: j < grupo.length
                          ? _fila(c, grupo[j])
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _fila(SiColors c, _Persona p) {
    final identidad = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _avatar(c, p),
        const SizedBox(width: SiSpace.x2),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(p.nombre,
                  style: TextStyle(
                      fontSize: 13,
                      height: 1.25,
                      fontWeight: FontWeight.w600,
                      color: c.ink)),
              // Puesto y datos en un solo renglón: eran dos líneas casi vacías cada una.
              Text(
                [
                  if (p.puesto.isNotEmpty) p.puesto,
                  if (p.ubicacion.isNotEmpty) p.ubicacion.replaceAll('_', ' '),
                ].join(' · '),
                style: TextStyle(fontSize: 11, height: 1.3, color: c.ink3),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
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
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 2),
            child: Text('Sin datos de contacto',
                style: TextStyle(fontSize: 11, color: c.ink4)),
          ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SiSpace.x2),
      child: LayoutBuilder(
        builder: (context, box) {
          // Sólo se pone el contacto al lado cuando de verdad cabe. El corte está en 700 y no en
          // 640 a propósito: con dos columnas la celda mide entre 540 y 660px según la ventana, y
          // con 640 el formato cambiaba a media franja —lado a lado a 1440px, apilado a 1200px—.
          // Así multicolumna siempre apila, y sólo la columna única usa el formato ancho.
          if (box.maxWidth < 700) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                identidad,
                const SizedBox(height: 3),
                Padding(
                  padding: const EdgeInsets.only(left: 36),
                  child: contacto,
                ),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 5, child: identidad),
              const SizedBox(width: SiSpace.x3),
              Expanded(flex: 4, child: contacto),
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
          width: 28, height: 28, fit: BoxFit.cover,
          // Si la foto no carga se cae a las iniciales, en lugar de dejar el hueco roto.
          errorBuilder: (_, __, ___) => _iniciales(c, p),
        ),
      );
    }
    return _iniciales(c, p);
  }

  Widget _iniciales(SiColors c, _Persona p) {
    return Container(
      width: 28, height: 28,
      decoration: BoxDecoration(color: c.brandTint, shape: BoxShape.circle),
      child: Center(
        child: Text(p.iniciales,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: c.brand)),
      ),
    );
  }

  Widget _contacto(SiColors c, IconData icono, String valor, String que) {
    return InkWell(
      onTap: () => _copiar(valor, que),
      borderRadius: BorderRadius.circular(5),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 1.5, horizontal: 4),
        child: Row(children: [
          Icon(icono, size: 12, color: c.ink4),
          const SizedBox(width: 6),
          Flexible(
            child: Text(valor,
                style: TextStyle(fontSize: 11.5, color: c.ink2),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 4),
          Tooltip(
            message: 'Copiar ${que.toLowerCase()}',
            child: Icon(Icons.copy_rounded, size: 11, color: c.ink4),
          ),
        ]),
      ),
    );
  }
}

class _Persona {
  _Persona({
    required this.nombre,
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
        // Los teléfonos llegan vacíos a quien no es administrador, así que para esa persona estas dos
        // comparaciones simplemente no encuentran nada. No hace falta un caso aparte.
        tel(telefono) ||
        tel(celular);
  }
}
