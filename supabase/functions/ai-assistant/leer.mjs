// Lo unico que comparten los cuatro arneses. Un modulo sin efectos al importarlo, a proposito.
//
// Antes `leer` vivia en verificar_permisos.mjs y los otros tres la importaban de ahi. Pero
// verificar_permisos.mjs corre sus comprobaciones al cargarse y termina en `process.exit(0)`: al
// importarla, ese exit MATABA al arnes que la habia pedido antes de que ejecutara una sola de sus
// propias pruebas. Los cuatro imprimian «TODO BIEN» porque los cuatro estaban corriendo el MISMO
// archivo. Un arnes que no falla nunca no es un arnes.
//
// De ahi que esto sea un archivo aparte: importarlo no puede tener consecuencias.

import { readFileSync } from 'node:fs';

/// Lee un archivo NORMALIZANDO los finales de linea.
///
/// git deja los archivos en CRLF en el disco -core.autocrlf-, y basta un `git checkout` de otra rama
/// para que vuelvan a estarlo. Con el `\r` al final de cada linea, borrar comentarios con
/// `/\/\/.*$/` no coincide: `.` no come el `\r` y `$` exige el final de la cadena. El efecto es
/// silencioso y del peor tipo -los COMENTARIOS se analizan como si fueran codigo- y aparecio como una
/// falsa FALLA en la comprobacion 10, disparada por un comentario que explicaba por que ya no se usa
/// una lista blanca.
export function leer(ruta) {
  return readFileSync(ruta, 'utf8').replace(/\r\n/g, '\n');
}
