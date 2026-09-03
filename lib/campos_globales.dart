import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme/si_theme.dart';

/// El mapa global de campos: qué usa cada desarrollo y cómo lo llama.
///
/// ─── Para qué sirve ────────────────────────────────────────────────────────
///
/// Lo pidió el usuario el 03/09/2026: «ir viendo un global, decir en AG117 torre sería edificio en
/// Vidamar». Es exactamente eso —una rejilla de campos por desarrollo, con el nombre que cada uno
/// les da— más la lista de columnas que aparecieron sin sitio.
///
/// ─── Y por qué no se crean columnas «por si acaso» ─────────────────────────
///
/// Porque cada columna inventada de más es una que nadie llena y que hay que explicar para siempre.
/// En su lugar, cada carga deja constancia de sus columnas huérfanas con un ejemplo del valor. Con
/// eso, la decisión de crear un campo se toma mirando cuántas listas lo traen y qué guardan, no
/// adivinando. Las de abajo son la lista de espera con evidencia.
///
/// Todo lo de arriba es CALCULADO —`v_campos_por_desarrollo` cuenta las unidades que tienen cada
/// campo lleno—, así que no puede decir que un desarrollo usa un campo si no hay ni una unidad con
/// él.
class CamposGlobales extends StatefulWidget {
  const CamposGlobales({super.key});

  @override
  State<CamposGlobales> createState() => _CamposGlobalesState();
}

class _CamposGlobalesState extends State<CamposGlobales> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _campos = [];
  List<Map<String, dynamic>> _huerfanas = [];
  bool _cargando = true;
  String? _error;

  /// El orden en que se leen, agrupado por lo que significan. El alfabético pondría «banos» antes
  /// de «depto» y rompería la lectura.
  static const orden = <String>[
    'sector', 'torre', 'nivel', 'depto',
    'tipo', 'tipologia', 'vista',
    'm2_superficie', 'm2_interior_techada', 'm2_exterior_techada', 'm2_jardin_terraza',
    'm2_terreno', 'm2_construccion',
    'recamaras', 'banos', 'estacionamientos',
    'precio',
  ];

  static const comoSeLee = <String, String>{
    'sector': 'Sector / cluster / coto',
    'torre': 'Torre / edificio',
    'nivel': 'Nivel / piso',
    'depto': 'Depto / lote / unidad',
    'tipo': 'Tipo',
    'tipologia': 'Tipología / modelo',
    'vista': 'Vista',
    'm2_superficie': 'M² (un solo número)',
    'm2_interior_techada': 'M² interior techada',
    'm2_exterior_techada': 'M² exterior techada',
    'm2_jardin_terraza': 'M² jardín / terraza',
    'm2_terreno': 'M² terreno',
    'm2_construccion': 'M² construcción',
    'recamaras': 'Recámaras',
    'banos': 'Baños',
    'estacionamientos': 'Estacionamientos',
    'precio': 'Precio',
  };

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final campos = await _supabase.from('v_campos_por_desarrollo').select();
      final huerfanas = await _supabase
          .from('columnas_sin_mapear')
          .select('columna,ejemplo,veces,ultima_vez,desarrollos(nombre)')
          .order('veces', ascending: false);
      if (!mounted) return;
      setState(() {
        _campos =
            (campos as List).map((e) => Map<String, dynamic>.from(e)).toList();
        _huerfanas =
            (huerfanas as List).map((e) => Map<String, dynamic>.from(e)).toList();
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
      return const SizedBox(
          height: 200, child: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(SiSpace.x5),
        child: Text('No se pudo cargar: $_error',
            style: TextStyle(color: c.danger, fontSize: 12.5)),
      );
    }

    // Sólo los desarrollos que ya tienen inventario: los demás no dicen nada todavía y llenarían
    // la rejilla de columnas vacías.
    final conInventario = <String>[];
    for (final f in _campos) {
      final n = f['desarrollo'].toString();
      if ((int.tryParse('${f['total']}') ?? 0) > 0 && !conInventario.contains(n)) {
        conInventario.add(n);
      }
    }
    conInventario.sort();

    if (conInventario.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(SiSpace.x6),
        child: Text(
            'Todavía no hay ningún desarrollo con inventario cargado, así que no hay campos que '
            'comparar. En cuanto pegues la primera lista, aquí aparece qué campos usa y con qué '
            'nombre los llama.',
            style: TextStyle(fontSize: 12.5, color: c.ink3, height: 1.5)),
      );
    }

    // campo -> desarrollo -> cómo lo llama (o null si no lo usa)
    final rejilla = <String, Map<String, String?>>{};
    for (final f in _campos) {
      final campo = f['campo'].toString();
      final des = f['desarrollo'].toString();
      if (!conInventario.contains(des)) continue;
      (rejilla[campo] ??= {})[des] =
          f['lo_usa'] == true ? f['se_llama'].toString() : null;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(SiSpace.x5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              'Un solo juego de campos para todos los desarrollos. Cada uno los llama a su manera '
              '—en AG117 «Torre», en Vidamar «EDIFICIO»— y ese nombre se aprende del encabezado '
              'del Excel al pegarlo, sin capturar nada.',
              style: TextStyle(fontSize: 12.5, color: c.ink3, height: 1.5)),
          const SizedBox(height: SiSpace.x4),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 38,
              dataRowMinHeight: 34,
              dataRowMaxHeight: 40,
              columnSpacing: 20,
              headingTextStyle: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700, color: c.ink3),
              dataTextStyle: TextStyle(fontSize: 12, color: c.ink),
              columns: [
                const DataColumn(label: Text('CAMPO')),
                for (final d in conInventario) DataColumn(label: Text(d)),
              ],
              rows: [
                for (final campo in orden)
                  if (rejilla.containsKey(campo))
                    DataRow(cells: [
                      DataCell(Text(comoSeLee[campo] ?? campo,
                          style: const TextStyle(fontWeight: FontWeight.w600))),
                      for (final d in conInventario)
                        DataCell(_celda(c, rejilla[campo]![d])),
                    ]),
              ],
            ),
          ),
          if (_huerfanas.isNotEmpty) ...[
            const SizedBox(height: SiSpace.x8),
            Text('COLUMNAS QUE APARECIERON Y NO TIENEN CAMPO',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: c.ink3,
                    letterSpacing: .6)),
            const SizedBox(height: SiSpace.x2),
            Text(
                'No se crean campos por si acaso: se anota lo que de verdad aparece, con un ejemplo '
                'de su valor. Cuando una columna se repita en varios desarrollos, ya se puede '
                'decidir con datos si merece un campo propio.',
                style: TextStyle(fontSize: 12, color: c.ink3, height: 1.5)),
            const SizedBox(height: SiSpace.x3),
            for (final h in _huerfanas)
              Padding(
                padding: const EdgeInsets.only(bottom: SiSpace.x2),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                          color: c.warnTint, borderRadius: SiRadius.rSm),
                      child: Text(h['columna'].toString(),
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: c.warn)),
                    ),
                    const SizedBox(width: SiSpace.x3),
                    Expanded(
                      child: Text(
                        [
                          (h['desarrollos'] as Map?)?['nombre']?.toString() ?? '?',
                          if ((h['ejemplo'] ?? '').toString().isNotEmpty)
                            'ejemplo: «${h['ejemplo']}»',
                          if ((int.tryParse('${h['veces']}') ?? 1) > 1)
                            'vista ${h['veces']} veces',
                        ].join('  ·  '),
                        style: TextStyle(fontSize: 11.5, color: c.ink3),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _celda(SiColors c, String? seLlama) {
    if (seLlama == null) {
      return Text('—', style: TextStyle(color: c.ink4));
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check, size: 12, color: c.success),
        const SizedBox(width: 4),
        Flexible(
          child: Text(seLlama,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: c.ink2)),
        ),
      ],
    );
  }
}
