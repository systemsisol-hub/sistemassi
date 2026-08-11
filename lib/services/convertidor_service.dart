import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;

/// Cliente del convertidor de documentos (Stirling PDF, autoalojado).
///
/// ─── Por qué habla directo con el servidor ───────────────────────────────────
///
/// El navegador llama a `pdf.sisol.red` sin pasar por Supabase: en el plan gratuito el cuello de
/// botella es el ancho de banda —5 GB— y un archivo que atravesara una Edge Function contaría dos
/// veces, al subir y al bajar.
///
/// Eso se puede hacer porque el servidor responde el preflight reflejando el origen que se le pide y
/// expone `Content-Disposition`, comprobado contra la instancia. La contrapartida está anotada abajo.
///
/// ⚠️ HOY EL SERVIDOR ESTÁ ABIERTO A INTERNET. No hay autenticación de por medio: `show_convertidor`
/// decide quién ve la página, no quién puede usar el servicio —cualquiera con la URL lo usa—. Es una
/// decisión tomada a conciencia para probar, pendiente de resolver. Cuando se cierre, la llamada
/// directa deja de funcionar y hay que meter un intermediario que ponga las credenciales; por eso
/// [_base] es una constante y no está repartida por la interfaz: se cambia en un solo lugar.
class ConvertidorService {
  static const _base = 'https://pdf.sisol.red/api/v1/convert';

  /// Tope del lado del cliente. El servidor también rechaza —declara 413— y Cloudflare corta los
  /// cuerpos grandes, pero avisar antes de subir 40 MB es mejor que esperar el rechazo.
  static const int maximoBytes = 25 * 1024 * 1024;

  /// Convierte y devuelve los bytes con el nombre que propuso el servidor.
  ///
  /// Lanza [ConvertidorError] con un mensaje ya redactado para la pantalla: quien llama no tiene que
  /// interpretar códigos HTTP.
  static Future<ArchivoConvertido> convertir({
    required Uint8List bytes,
    required String nombreOriginal,
    required FormatoDestino destino,
  }) async {
    if (bytes.length > maximoBytes) {
      final mb = (bytes.length / 1024 / 1024).toStringAsFixed(1);
      throw ConvertidorError(
          'El archivo pesa $mb MB y el máximo son ${maximoBytes ~/ 1024 ~/ 1024} MB.');
    }

    final peticion =
        http.MultipartRequest('POST', Uri.parse('$_base/${destino.ruta}'))
          ..files.add(http.MultipartFile.fromBytes('fileInput', bytes,
              filename: nombreOriginal))
          ..fields.addAll(destino.campos);

    final http.StreamedResponse respuesta;
    try {
      respuesta = await peticion.send().timeout(const Duration(minutes: 3));
    } catch (e) {
      // Sin distinguir tipos: para quien usa la página, «no se pudo llegar al servidor» cubre igual
      // un DNS caído, un túnel abajo o un tiempo de espera agotado.
      throw ConvertidorError(
          'No se pudo contactar al servidor de conversión. Revisa tu conexión '
          'o inténtalo en un momento.');
    }

    final cuerpo = await respuesta.stream.toBytes();

    // ⚠️ EL ORDEN DE ESTAS COMPROBACIONES IMPORTA, y tenerlo al revés costó una sesión de
    // diagnóstico. Antes se miraba «cuerpo vacío» ANTES del código de estado, y como este servidor
    // devuelve 400 con CERO bytes —comprobado: un `outputFormat` inválido da `400` y cuerpo vacío—,
    // cualquier petición mal formada se reportaba como «no encontró contenido». El mensaje culpaba al
    // documento cuando el problema era la petición.
    //
    // Primero el estado, y siempre diciendo el número: un mensaje que no dice qué respondió el
    // servidor no se puede diagnosticar desde el otro lado del teléfono.
    if (respuesta.statusCode != 200) {
      throw ConvertidorError(_mensajeDeError(
          respuesta.statusCode, destino, cuerpo, respuesta.reasonPhrase));
    }

    // 200 con cuerpo vacío es otra cosa: la petición estaba bien y el servidor no encontró nada que
    // extraer. Es lo que hacen las conversiones a tabla —Excel y CSV, que por eso no se ofrecen— y lo
    // que pasa con un escaneo sin capa de texto.
    if (cuerpo.isEmpty) {
      throw ConvertidorError(
          'El servidor aceptó el archivo pero devolvió un resultado vacío al '
          'convertir a ${destino.etiqueta} (200 sin contenido). Suele pasar con '
          'documentos escaneados, que son imágenes sin texto.');
    }

    return ArchivoConvertido(
      bytes: cuerpo,
      nombre: nombreDeRespuesta(
        respuesta.headers['content-disposition'],
        respaldo: nombreConExtension(nombreOriginal, destino.extension),
      ),
    );
  }

  /// Puerta para las pruebas: el mensaje de error se arma con lógica que conviene fijar, y montar un
  /// servidor falso para comprobar un `switch` sería desproporcionado.
  @visibleForTesting
  static String mensajeDeErrorParaPruebas(
          int estado, FormatoDestino destino, Uint8List cuerpo) =>
      _mensajeDeError(estado, destino, cuerpo, null);

  /// Traduce un fallo del servidor a algo que se pueda leer y, sobre todo, diagnosticar.
  ///
  /// Siempre incluye el código: este servidor devuelve el 400 con cuerpo vacío, así que el número es
  /// a veces la única pista que hay. Si además manda texto —a veces responde
  /// `application/problem+json`— se agrega recortado.
  static String _mensajeDeError(
      int estado, FormatoDestino destino, Uint8List cuerpo, String? razon) {
    final detalle = _textoCorto(cuerpo);
    final cola = detalle == null ? '' : ' El servidor dijo: $detalle';

    return switch (estado) {
      400 =>
        'El servidor rechazó la petición al convertir a ${destino.etiqueta} '
            '(400). Suele ser un archivo que no es el que dice ser —un PDF '
            'dañado, o un documento con otra extensión—.$cola',
      413 => 'El servidor rechazó el archivo por tamaño (413).',
      415 => 'El servidor no acepta este tipo de archivo (415).$cola',
      422 =>
        'El servidor no pudo procesar el documento (422). Puede estar protegido '
            'con contraseña o dañado.$cola',
      500 || 502 || 503 || 504 =>
        'El servidor de conversión falló ($estado). Si se repite, el servicio '
            'puede estar caído o sin memoria para este documento.$cola',
      _ => 'El servidor respondió $estado${razon == null || razon.isEmpty ? '' : ' $razon'} '
          'al convertir a ${destino.etiqueta}.$cola',
    };
  }

  /// El cuerpo como texto, si es texto y es corto. Nunca se vuelca un binario en un mensaje.
  static String? _textoCorto(Uint8List cuerpo) {
    if (cuerpo.isEmpty || cuerpo.length > 2000) return null;
    // Un binario trae bytes de control; si los hay, no es un mensaje para leer.
    if (cuerpo.any((b) => b < 9 || (b > 13 && b < 32))) return null;
    final t = String.fromCharCodes(cuerpo).trim();
    if (t.isEmpty) return null;
    return t.length > 240 ? '${t.substring(0, 240)}…' : t;
  }

  /// El nombre que propone el servidor, o el de respaldo.
  ///
  /// Se prefiere el del servidor porque conoce el resultado real: `pdf/img` con varias páginas
  /// devuelve un ZIP —comprobado, empieza con `PK`— y lo nombra `..._convertedToImages.zip`, mientras
  /// que con una sola página devuelve un PNG. Adivinar la extensión desde el cliente daría un archivo
  /// que el sistema operativo no sabe abrir.
  ///
  /// La cabecera llega como `form-data; name="attachment"; filename="x.docx"`, que no es la forma
  /// habitual —se espera `attachment; filename=...`—, así que se busca `filename=` en cualquier parte
  /// en lugar de exigir un formato.
  static String nombreDeRespuesta(String? cabecera, {required String respaldo}) {
    if (cabecera == null) return respaldo;
    final m = RegExp('filename\\*?=(?:"([^"]+)"|([^;]+))', caseSensitive: false)
        .firstMatch(cabecera);
    final crudo = (m?.group(1) ?? m?.group(2))?.trim();
    if (crudo == null || crudo.isEmpty) return respaldo;
    // Nunca se confía en una ruta que viene del servidor: sólo el nombre del archivo.
    final limpio = crudo.split(RegExp(r'[/\\]')).last.trim();
    return limpio.isEmpty ? respaldo : limpio;
  }

  /// Cambia la extensión del nombre original por la del destino.
  static String nombreConExtension(String original, String extension) {
    final punto = original.lastIndexOf('.');
    final base = punto <= 0 ? original : original.substring(0, punto);
    final limpio = base.trim().isEmpty ? 'documento' : base.trim();
    return '$limpio.$extension';
  }

  /// Los destinos posibles para un archivo, según lo que traiga.
  ///
  /// Un PDF puede salir a muchos formatos; cualquier otra cosa sólo entra a PDF, que es lo que hace
  /// LibreOffice del otro lado. No es una limitación inventada: es lo que expone la API.
  static List<FormatoDestino> destinosPara(String nombreArchivo) {
    final ext = nombreArchivo.split('.').last.toLowerCase();
    return ext == 'pdf' ? desdePdf : const [aPdf];
  }

  // ── Catálogo ───────────────────────────────────────────────────────────────
  //
  // Cada entrada se probó contra la instancia. Excel y CSV NO están: devuelven 204 sin contenido
  // incluso con un PDF que lleva una tabla HTML de verdad, así que ofrecerlos sería prometer un
  // archivo vacío.

  static const aPdf = FormatoDestino(
    id: 'pdf',
    etiqueta: 'PDF',
    ruta: 'file/pdf',
    extension: 'pdf',
    descripcion: 'Word, Excel, PowerPoint, imágenes, HTML y texto',
    principal: true,
  );

  static const desdePdf = <FormatoDestino>[
    FormatoDestino(
      id: 'markdown',
      etiqueta: 'Markdown',
      ruta: 'pdf/markdown',
      extension: 'md',
      descripcion: 'Texto con títulos y listas. Las tablas salen aproximadas',
      principal: true,
    ),
    FormatoDestino(
      id: 'txt',
      etiqueta: 'Texto',
      ruta: 'pdf/text',
      campos: {'outputFormat': 'txt'},
      extension: 'txt',
      descripcion: 'Sólo el texto, sin formato',
      principal: true,
    ),
    FormatoDestino(
      id: 'docx',
      etiqueta: 'Word',
      ruta: 'pdf/word',
      campos: {'outputFormat': 'docx'},
      extension: 'docx',
      descripcion: 'Documento editable',
      principal: true,
    ),
    FormatoDestino(
      id: 'html',
      etiqueta: 'HTML',
      ruta: 'pdf/html',
      extension: 'html',
      descripcion: 'Página web',
      principal: true,
    ),
    FormatoDestino(
      id: 'png_zip',
      etiqueta: 'Imágenes PNG',
      ruta: 'pdf/img',
      campos: {
        'colorType': 'color',
        'dpi': '150',
        'imageFormat': 'png',
        'pageNumbers': 'all',
        'singleOrMultiple': 'multiple',
      },
      // Comprobado: con varias páginas devuelve un ZIP, no un PNG.
      extension: 'zip',
      descripcion: 'Una imagen por página, en un ZIP',
      principal: true,
    ),
    FormatoDestino(
      id: 'png',
      etiqueta: 'Imagen única',
      ruta: 'pdf/img',
      campos: {
        'colorType': 'color',
        'dpi': '150',
        'imageFormat': 'png',
        'pageNumbers': 'all',
        'singleOrMultiple': 'single',
      },
      extension: 'png',
      descripcion: 'Todas las páginas en una sola imagen larga',
      principal: true,
    ),
    FormatoDestino(
      id: 'pdfa',
      etiqueta: 'PDF/A',
      ruta: 'pdf/pdfa',
      campos: {'outputFormat': 'pdfa-2b'},
      extension: 'pdf',
      descripcion: 'Formato de archivado a largo plazo',
      principal: true,
    ),
    // De aquí abajo, formatos que funcionan pero se piden poco.
    FormatoDestino(
      id: 'odt',
      etiqueta: 'OpenDocument',
      ruta: 'pdf/word',
      campos: {'outputFormat': 'odt'},
      extension: 'odt',
      descripcion: 'LibreOffice Writer',
    ),
    FormatoDestino(
      id: 'rtf',
      etiqueta: 'RTF',
      ruta: 'pdf/text',
      campos: {'outputFormat': 'rtf'},
      extension: 'rtf',
      descripcion: 'Texto con formato básico',
    ),
    FormatoDestino(
      id: 'pptx',
      etiqueta: 'PowerPoint',
      ruta: 'pdf/presentation',
      campos: {'outputFormat': 'pptx'},
      extension: 'pptx',
      descripcion: 'Una diapositiva por página',
    ),
    FormatoDestino(
      id: 'epub',
      etiqueta: 'EPUB',
      ruta: 'pdf/epub',
      extension: 'epub',
      descripcion: 'Libro electrónico',
    ),
    FormatoDestino(
      id: 'xml',
      etiqueta: 'XML',
      ruta: 'pdf/xml',
      extension: 'xml',
      descripcion: 'Estructura del documento',
    ),
  ];

  /// Extensiones que el selector de archivos acepta.
  ///
  /// Las de entrada a PDF salen de lo que LibreOffice maneja; se dejan las de oficina y las imágenes,
  /// que son las que alguien traería.
  static const extensionesAceptadas = <String>[
    'pdf',
    'doc', 'docx', 'odt', 'rtf', 'txt',
    'xls', 'xlsx', 'ods', 'csv',
    'ppt', 'pptx', 'odp',
    'html', 'htm', 'md',
    'png', 'jpg', 'jpeg', 'webp', 'gif',
  ];
}

/// Un destino de conversión, con todo lo que la petición necesita.
class FormatoDestino {
  const FormatoDestino({
    required this.id,
    required this.etiqueta,
    required this.ruta,
    required this.extension,
    required this.descripcion,
    this.campos = const {},
    this.principal = false,
  });

  final String id;
  final String etiqueta;

  /// Ruta relativa a `/api/v1/convert`.
  final String ruta;

  /// Campos obligatorios del formulario. Salen del propio OpenAPI de la instancia: varias
  /// conversiones fallan con 400 si faltan —`pdf/img` exige cinco—.
  final Map<String, String> campos;

  final String extension;
  final String descripcion;

  /// Si va en el grupo visible o en «más formatos».
  final bool principal;
}

class ArchivoConvertido {
  const ArchivoConvertido({required this.bytes, required this.nombre});
  final Uint8List bytes;
  final String nombre;
}

/// Error con un mensaje ya listo para mostrar.
class ConvertidorError implements Exception {
  const ConvertidorError(this.mensaje);
  final String mensaje;
  @override
  String toString() => mensaje;
}
