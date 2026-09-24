/// Lo que la sección Ventas calcula sin base de datos ni pantalla.
///
/// Sisol es el agente de ventas PÚBLICO de sisol.com.mx (el Worker de chat.sisol.red, en
/// `workers/ventas/`). Guarda en `ventas_leads` y `ventas_conversaciones`; aquí se leen esas filas y
/// se convierten en lo que muestra la app: los datos que dejó un visitante aunque no llegara a ser
/// lead, los repetidos, el CSV y el inventario pegado desde Excel.
///
/// No importa nada de Flutter a propósito: así las pruebas corren sin levantar un widget.
library;

// ─── Dinero y fechas ─────────────────────────────────────────────────────────

/// 5950000 → «$5,950,000». `null` o no numérico → «—».
String dinero(dynamic v) {
  if (v == null) return '—';
  final n = num.tryParse(v.toString());
  if (n == null) return '—';
  final entero = n.round().abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < entero.length; i++) {
    if (i > 0 && (entero.length - i) % 3 == 0) buf.write(',');
    buf.write(entero[i]);
  }
  return '${n < 0 ? '-' : ''}\$$buf';
}

/// Fecha y hora de la Ciudad de México (UTC-6, sin horario de verano desde 2022), que es la que
/// usan los asesores. La base guarda en UTC.
DateTime horaMexico(DateTime utc) => utc.toUtc().subtract(const Duration(hours: 6));

String fechaCorta(dynamic v) {
  final d = DateTime.tryParse('${v ?? ''}');
  if (d == null) return '—';
  final m = horaMexico(d);
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${dos(m.day)}/${dos(m.month)}/${m.year} ${dos(m.hour)}:${dos(m.minute)}';
}

// ─── Desarrollos ─────────────────────────────────────────────────────────────

/// «Punta Pacífico» → reconoce «punta pacifico», «Punta-Pacífico», «PUNTA PACIFICO». La misma
/// regla que usa el Worker (`regexDeNombres` en workers/ventas/src/supabase.ts), para que la app y
/// el chat reconozcan igual un desarrollo.
RegExp regexDeNombres(Iterable<String> nombres) {
  const vocal = {'a': '[aá]', 'e': '[eé]', 'i': '[ií]', 'o': '[oó]', 'u': '[uúü]'};
  final partes = nombres
      .map((n) => sinAcentos(n.trim().toLowerCase()))
      .where((n) => n.isNotEmpty)
      .toSet()
      .map((n) => RegExp.escape(n)
          .replaceAll(RegExp(r'[\s-]+'), r'\s*-?\s*')
          .replaceAllMapped(RegExp('[aeiou]'), (m) => vocal[m[0]]!))
      .toList();
  return RegExp(partes.isEmpty ? r'(?!)' : partes.join('|'), caseSensitive: false);
}

String sinAcentos(String s) {
  const de = 'áàäâéèëêíìïîóòöôúùüûñÁÀÄÂÉÈËÊÍÌÏÎÓÒÖÔÚÙÜÛÑ';
  const a = 'aaaaeeeeiiiioooouuuunAAAAEEEEIIIIOOOOUUUUN';
  final buf = StringBuffer();
  for (final ch in s.split('')) {
    final i = de.indexOf(ch);
    buf.write(i >= 0 ? a[i] : ch);
  }
  return buf.toString();
}

/// «Punta Pacífico» → «punta-pacifico». El slug nombra la página en sisol.com.mx y los brochures
/// (`{slug}-es.pdf`).
String slugDe(String nombre) => sinAcentos(nombre.trim().toLowerCase())
    .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-+|-+$'), '');

// ─── Conversaciones ──────────────────────────────────────────────────────────

class Mensaje {
  final String role;
  final String content;
  const Mensaje(this.role, this.content);

  bool get esCliente => role == 'user';

  static List<Mensaje> deTranscript(dynamic t) {
    if (t is! List) return const [];
    return [
      for (final m in t)
        if (m is Map && m['content'] is String)
          Mensaje('${m['role']}', m['content'] as String),
    ];
  }
}

class DatosCliente {
  final String nombre;
  final String email;
  final String telefono;
  final String presupuesto;
  const DatosCliente({
    this.nombre = '',
    this.email = '',
    this.telefono = '',
    this.presupuesto = '',
  });

  bool get vacio => nombre.isEmpty && email.isEmpty && telefono.isEmpty && presupuesto.isEmpty;
}

final _reEmail = RegExp(r'\S+@\S+\.\S+');
final _rePresupuesto = RegExp(
    r'\$?\s?\d[\d.,]*\s*(millones?|mill(?:ones?)?|mdp|mil|k|usd|d[óo]lares|pesos|mxn)\b',
    caseSensitive: false);

// Palabras con las que NO empieza un nombre: saludos, preguntas, zonas y los chips del menú del
// widget («Cuéntame de VidaMar»). Las mismas que usa el Worker.
const _noNombre = {
  'hola', 'si', 'sí', 'no', 'claro', 'gracias', 'buenos', 'buenas', 'dias', 'días', 'tardes',
  'noches', 'ok', 'okay', 'va', 'vale', 'quiero', 'busco', 'me', 'mi', 'interesa', 'cuentame',
  'cuéntame', 'cuanto', 'cuánto', 'que', 'qué', 'cual', 'cuál', 'como', 'cómo', 'donde', 'dónde',
  'porfa', 'favor', 'depa', 'departamento', 'info', 'informacion', 'información', 'zona', 'precio',
  'precios', 'adios', 'adiós', 'cdmx', 'tulum', 'acapulco', 'ensenada', 'playa', 'puerto',
  'morelos', 'selva', 'norte', 'saber', 'mas', 'más', 'tienen', 'hay', 'ver',
  'broker', 'brokers', 'asesor', 'asesora', 'agente', 'inmobiliario', 'inmobiliaria', 'empresa',
  'proveedor', 'en', 'con', 'para', 'por',
  'perfecto', 'listo', 'excelente', 'bien', 'genial', 'entendido', 'sale', 'dale', 'correcto', 'exacto',
};

bool pareceNombre(String texto) {
  final t = texto.trim();
  if (t.isEmpty || t.contains('?') || t.contains('@') || RegExp(r'\d').hasMatch(t)) return false;
  final p = t.split(RegExp(r'\s+'));
  if (p.length > 4) return false;
  if (!p.every((w) => RegExp(r"^[A-Za-zÁÉÍÓÚÑáéíóúñ'.-]{2,}$").hasMatch(w))) return false;
  // Ninguna palabra, no solo la primera: «lockoff quiero saber mas» no es un nombre aunque
  // empiece con una palabra que no está en la lista.
  return !p.any((w) => _noNombre.contains(w.toLowerCase()));
}

/// El nombre que dio el cliente, de más a menos confiable: «me llamo X», el texto antes del correo
/// en el mismo mensaje, o la respuesta a un mensaje del agente que le pidió el nombre.
String detectarNombre(List<Mensaje> hilo) {
  final auto = RegExp(
      r"\b(?:me\s+llamo|mi\s+nombre\s+es|mi\s+nombre|soy|nombre(?:\s+completo)?(?:\s+es)?)[:\s]+"
      r"([A-Za-zÁÉÍÓÚÑáéíóúñ'.\-]{2,}(?:\s+[A-Za-zÁÉÍÓÚÑáéíóúñ'.\-]{2,}){0,3})",
      caseSensitive: false);
  for (final m in hilo.where((m) => m.esCliente)) {
    final mm = auto.firstMatch(m.content);
    if (mm != null && pareceNombre(mm[1]!)) return mm[1]!.trim();
  }
  for (final m in hilo.where((m) => m.esCliente)) {
    final em = _reEmail.firstMatch(m.content);
    if (em == null) continue;
    final antes = m.content
        .substring(0, em.start)
        .replaceAll(RegExp(r'[,;:]'), ' ')
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    final p = antes.skip(antes.length > 4 ? antes.length - 4 : 0).join(' ');
    if (pareceNombre(p)) return p;
  }
  for (var i = 1; i < hilo.length; i++) {
    if (!hilo[i].esCliente) continue;
    final prev = hilo.sublist(0, i).lastWhere((m) => !m.esCliente, orElse: () => const Mensaje('', ''));
    if (!prev.content.toLowerCase().contains('nombre')) continue;
    if (pareceNombre(hilo[i].content)) return hilo[i].content.trim();
    final seg = hilo[i].content.split(RegExp(r'[,.!?\n]')).first.trim();
    if (pareceNombre(seg)) return seg;
  }
  return '';
}

/// Lo que dejó el visitante aunque no llegara a ser lead (p. ej. dio teléfono pero no correo).
DatosCliente datosDeConversacion(List<Mensaje> hilo) {
  final texto = hilo.where((m) => m.esCliente).map((m) => m.content).join(' ');
  final email = _reEmail.firstMatch(texto)?[0] ?? '';
  final sinEmails = texto.replaceAll(_reEmail, ' ');
  final tel = RegExp(r'\d{10,13}')
          .firstMatch(sinEmails.replaceAll(RegExp(r'[\s().-]'), ''))?[0] ??
      '';
  return DatosCliente(
    nombre: detectarNombre(hilo),
    email: email,
    telefono: tel.isEmpty ? '' : tel.substring(tel.length - 10),
    presupuesto: _rePresupuesto.firstMatch(texto)?[0]?.trim() ?? '',
  );
}

/// El último desarrollo que nombró el CLIENTE: refleja su interés actual mejor que el primero que
/// aparezca cuando la plática pasa por varios.
String ultimoDesarrollo(List<Mensaje> hilo, Map<String, RegExp> desarrollos) {
  for (final m in hilo.reversed.where((m) => m.esCliente)) {
    var mejor = '';
    var pos = -1;
    for (final e in desarrollos.entries) {
      for (final hit in e.value.allMatches(m.content)) {
        if (hit.start > pos) {
          pos = hit.start;
          mejor = e.key;
        }
      }
    }
    if (mejor.isNotEmpty) return mejor;
  }
  return '';
}

String conversacionTxt(List<Mensaje> hilo, {String encabezado = ''}) {
  final buf = StringBuffer();
  if (encabezado.isNotEmpty) buf.writeln('$encabezado\n');
  for (final m in hilo) {
    buf.writeln('${m.esCliente ? 'CLIENTE' : 'SISOL'}: ${m.content}\n');
  }
  return buf.toString();
}

// ─── Leads ───────────────────────────────────────────────────────────────────

/// Cuántas veces aparece cada correo y cada teléfono. El chat NO une repetidos a propósito: la
/// misma persona puede cotizar dos desarrollos. Se marcan para que el asesor no llame dos veces.
({Map<String, int> emails, Map<String, int> telefonos}) repetidos(
    List<Map<String, dynamic>> leads) {
  final e = <String, int>{};
  final t = <String, int>{};
  for (final l in leads) {
    final em = '${l['email'] ?? ''}'.trim().toLowerCase();
    final te = '${l['telefono'] ?? ''}'.replaceAll(RegExp(r'\D'), '');
    if (em.isNotEmpty) e[em] = (e[em] ?? 0) + 1;
    if (te.isNotEmpty) t[te] = (t[te] ?? 0) + 1;
  }
  return (emails: e, telefonos: t);
}

String _celdaCsv(Object? v) {
  final s = '${v ?? ''}';
  return RegExp(r'[",\n\r]').hasMatch(s) ? '"${s.replaceAll('"', '""')}"' : s;
}

/// Con BOM para que Excel lo abra en UTF-8 y no rompa los acentos.
String leadsCsv(List<Map<String, dynamic>> leads, {required String Function(String folio) urlCotizacion}) {
  const cols = ['fecha_mx', 'tipo', 'nombre', 'email', 'telefono', 'presupuesto', 'desarrollo', 'resumen', 'notificado', 'cotizacion'];
  final buf = StringBuffer('﻿${cols.join(',')}\r\n');
  for (final l in leads) {
    buf.write([
      fechaCorta(l['created_at']),
      tipoTexto[l['tipo']] ?? 'Cliente',
      l['nombre'],
      l['email'],
      l['telefono'],
      l['presupuesto'],
      l['desarrollo'],
      l['resumen'],
      l['notificado'] == true ? 'si' : 'no',
      urlCotizacion('${l['folio']}'),
    ].map(_celdaCsv).join(','));
    buf.write('\r\n');
  }
  return buf.toString();
}

// ─── Inventario pegado desde Excel ───────────────────────────────────────────

const estatusVentas = ['DISPONIBLE', 'APARTADO', 'RESERVADO', 'VENDIDO', 'EN_PROCESO'];

/// Quién dejó sus datos en el chat. Solo CLIENTE recibe cotización; los demás reciben la tarjeta de
/// contacto de Configuración (decisión del usuario del 24/09/2026).
const tipoTexto = {
  'CLIENTE': 'Cliente',
  'ASESOR_EXTERNO': 'Asesor externo',
  'PROVEEDOR': 'Proveedor',
  'BUSCA_EMPLEO': 'Busca empleo',
};

const estatusTexto = {
  'DISPONIBLE': 'Disponible',
  'APARTADO': 'Apartado',
  'RESERVADO': 'Reservado',
  'VENDIDO': 'Vendido',
  'EN_PROCESO': 'En proceso',
};

/// Columnas de `ventas_unidades` y los encabezados con que llegan en las listas. Son los alias del
/// panel anterior (admin.html de AgenteIA), para que el mismo Excel siga sirviendo.
const _alias = <String, List<String>>{
  'tipo': ['tipo', 'type', 'tipologia', 'prototipo', 'modelo'],
  'nivel': ['nivel', 'floor', 'piso'],
  'numero': ['numero', 'num', 'no', '#', 'unit', 'unidad', 'depto', 'departamento'],
  'area_int': ['area_int', 'area int', 'area interior', 'interior', 'int', 'm2 int'],
  'area_ext': ['area_ext', 'area ext', 'area exterior', 'exterior', 'ext', 'terraza'],
  'area_total': ['area_total', 'area total', 'total', 'm2', 'm²', 'superficie', 'sup m2'],
  'precio_mxn': ['precio_mxn', 'precio mxn', 'precio', 'mxn', 'pesos'],
  'precio_usd': ['precio_usd', 'precio usd', 'precio_dls', 'precio dls', 'usd', 'dls', 'dolares'],
  'fecha_escritura': ['fecha_escritura', 'fecha escritura', 'fecha', 'escritura', 'entrega'],
  'estatus': ['estatus', 'status', 'estado', 'disponibilidad'],
};

const columnasUnidad = [
  'tipo', 'nivel', 'numero', 'area_int', 'area_ext', 'area_total',
  'precio_mxn', 'precio_usd', 'fecha_escritura', 'estatus',
];

String? _columnaDe(String encabezado) {
  final h = sinAcentos(encabezado.trim().toLowerCase())
      .replaceAll('.', '')
      .replaceAll(RegExp(r'\s+'), ' ');
  for (final e in _alias.entries) {
    if (e.value.contains(h)) return e.key;
  }
  return null;
}

/// «$5,950,000.00», «5950000», «282,857 USD» → número. Vacío o texto → null.
double? numeroDe(String? s) {
  if (s == null) return null;
  final limpio = s.replaceAll(RegExp(r'[^0-9.\-]'), '');
  if (limpio.isEmpty || limpio == '.' || limpio == '-') return null;
  return double.tryParse(limpio);
}

/// «Disponible», «VENDIDA», «en proceso» → la clave de la base. Lo que no se reconoce → null.
String? estatusDe(String? crudo) {
  final s = sinAcentos((crudo ?? '').trim().toLowerCase());
  if (s.isEmpty) return 'DISPONIBLE';
  if (s.startsWith('disp') || s == 'libre') return 'DISPONIBLE';
  if (s.startsWith('apart')) return 'APARTADO';
  if (s.startsWith('reserv')) return 'RESERVADO';
  if (s.startsWith('vend')) return 'VENDIDO';
  if (s.contains('proceso')) return 'EN_PROCESO';
  return null;
}

class PegadoVentas {
  final List<Map<String, dynamic>> filas;
  final List<String> errores;
  final List<String> ignoradas;
  const PegadoVentas(this.filas, this.errores, this.ignoradas);
}

/// Lee lo que se pega desde Excel (tabuladores) o un CSV (comas). La primera línea tiene que ser el
/// encabezado: sin él no hay forma de saber cuál número es el precio y cuál la superficie.
PegadoVentas leerPegadoVentas(String texto) {
  final lineas = texto
      .replaceAll('\r\n', '\n')
      .split('\n')
      .where((l) => l.trim().isNotEmpty)
      .toList();
  if (lineas.isEmpty) return const PegadoVentas([], ['No hay nada pegado.'], []);

  final sep = lineas.first.contains('\t') ? '\t' : ',';
  List<String> celdas(String l) => sep == '\t' ? l.split('\t') : _partirCsv(l);

  final encabezado = celdas(lineas.first);
  final mapa = encabezado.map(_columnaDe).toList();
  if (!mapa.any((c) => c != null)) {
    return const PegadoVentas([], [
      'La primera línea no parece un encabezado. Copia la tabla CON la fila de títulos '
          '(Tipo, Nivel, Número, Área total, Precio MXN…).'
    ], []);
  }
  final ignoradas = [
    for (var i = 0; i < encabezado.length; i++)
      if (mapa[i] == null && encabezado[i].trim().isNotEmpty) encabezado[i].trim(),
  ];

  final filas = <Map<String, dynamic>>[];
  final errores = <String>[];
  for (var n = 1; n < lineas.length; n++) {
    final c = celdas(lineas[n]);
    final crudo = <String, String>{};
    for (var j = 0; j < c.length && j < mapa.length; j++) {
      final col = mapa[j];
      if (col != null && c[j].trim().isNotEmpty) crudo.putIfAbsent(col, () => c[j].trim());
    }
    if (crudo.isEmpty) continue;
    if ((crudo['tipo'] ?? crudo['numero'] ?? crudo['precio_mxn'] ?? crudo['precio_usd']) == null) {
      errores.add('Línea ${n + 1}: sin tipo, número ni precio; se omite.');
      continue;
    }
    final estatus = estatusDe(crudo['estatus']);
    if (estatus == null) {
      errores.add('Línea ${n + 1}: estatus «${crudo['estatus']}» no reconocido; se omite.');
      continue;
    }
    filas.add({
      'tipo': crudo['tipo'],
      'nivel': crudo['nivel'],
      'numero': crudo['numero'],
      'area_int': numeroDe(crudo['area_int']),
      'area_ext': numeroDe(crudo['area_ext']),
      'area_total': numeroDe(crudo['area_total']),
      'precio_mxn': numeroDe(crudo['precio_mxn']),
      'precio_usd': numeroDe(crudo['precio_usd']),
      'fecha_escritura': crudo['fecha_escritura'],
      'estatus': estatus,
    });
  }
  return PegadoVentas(filas, errores, ignoradas);
}

List<String> _partirCsv(String linea) {
  final out = <String>[];
  final buf = StringBuffer();
  var comillas = false;
  for (var i = 0; i < linea.length; i++) {
    final ch = linea[i];
    if (ch == '"') {
      if (comillas && i + 1 < linea.length && linea[i + 1] == '"') {
        buf.write('"');
        i++;
      } else {
        comillas = !comillas;
      }
    } else if (ch == ',' && !comillas) {
      out.add(buf.toString());
      buf.clear();
    } else {
      buf.write(ch);
    }
  }
  out.add(buf.toString());
  return out;
}
