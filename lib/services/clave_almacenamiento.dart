/// Nombres de archivo aptos para una clave de Supabase Storage.
///
/// ─── Por qué existe ─────────────────────────────────────────────────────────
///
/// Subir «CÓDIGO DE ÉTICA SISOL.pdf» a la base de conocimiento fallaba con:
///
///     StorageException(message: Invalid key: <id>/1786565663330_CÓDIGO DE ÉTICA SISOL.pdf,
///                      statusCode: 400, error: InvalidKey)
///
/// Storage valida la clave del objeto y rechaza los caracteres fuera de ASCII. Las tildes de «CÓDIGO»
/// y «ÉTICA» son las que la invalidan; un archivo que sí había subido antes se llamaba
/// `PoliticaTI.pdf`, sin acentos.
///
/// ─── Una diferencia con el asistente que conviene no confundir ──────────────
///
/// En la búsqueda de personas la Ñ se conserva a propósito, porque «Peñafiel» está guardado así en la
/// base y convertirlo rompería las búsquedas. Aquí es lo contrario: la clave tiene que ser ASCII, así
/// que la Ñ también se convierte. Son dos reglas distintas para dos problemas distintos.
///
/// El nombre bonito NO se pierde: `knowledge_articles.file_name` guarda el original y es lo que se
/// muestra en pantalla. Esto sólo afecta la ruta interna del archivo.
library;

/// Cuántos caracteres se conservan del nombre, sin contar la extensión.
///
/// No es un límite de Storage —admite claves largas— sino de sentido común: una URL con doscientos
/// caracteres de título es incómoda de leer, copiar y depurar.
const int _maxBase = 80;

const Map<String, String> _equivalencias = {
  'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u', 'ñ': 'n',
  'Á': 'A', 'É': 'E', 'Í': 'I', 'Ó': 'O', 'Ú': 'U', 'Ü': 'U', 'Ñ': 'N',
  'à': 'a', 'è': 'e', 'ì': 'i', 'ò': 'o', 'ù': 'u',
  'â': 'a', 'ê': 'e', 'î': 'i', 'ô': 'o', 'û': 'u',
  'ä': 'a', 'ë': 'e', 'ï': 'i', 'ö': 'o',
  'ç': 'c', 'Ç': 'C', 'ý': 'y', 'ÿ': 'y',
};

/// Convierte un nombre de archivo en algo que Storage acepta como clave.
///
/// Conserva la extensión, quita acentos, y sustituye por `_` todo lo que no sea letra ASCII, dígito,
/// punto, guion o guion bajo. Nunca devuelve una cadena vacía.
String claveDeArchivo(String nombre) {
  final limpio = nombre.trim();
  if (limpio.isEmpty) return 'archivo';

  // La extensión se separa ANTES de sanear, para que el punto que la delimita no se pierda entre los
  // demás. «informe.final.v2.pdf» conserva `.pdf` y el resto pasa a ser parte del nombre.
  final punto = limpio.lastIndexOf('.');
  // `punto >= 0` y no `> 0`: un nombre que EMPIEZA con punto —«.pdf»— también tiene extensión. Con
  // `> 0` el punto no se detectaba, el nombre entero pasaba por el saneador, éste le quitaba el punto
  // inicial y la clave quedaba en «pdf», sin extensión. Lo encontró la prueba.
  final tieneExt = punto >= 0 && punto < limpio.length - 1;
  final base = tieneExt ? limpio.substring(0, punto) : limpio;
  final ext = tieneExt ? limpio.substring(punto + 1) : '';

  String sanear(String s) {
    final sinAcentos = s.split('').map((c) => _equivalencias[c] ?? c).join();
    return sinAcentos
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^[_.]+|[_.]+$'), '');
  }

  var baseLimpia = sanear(base);
  if (baseLimpia.length > _maxBase) baseLimpia = baseLimpia.substring(0, _maxBase);
  // Si el nombre era sólo acentos o símbolos, no queda nada útil y hace falta algo que nombrar.
  if (baseLimpia.isEmpty) baseLimpia = 'archivo';

  final extLimpia = sanear(ext).toLowerCase();
  return extLimpia.isEmpty ? baseLimpia : '$baseLimpia.$extLimpia';
}
