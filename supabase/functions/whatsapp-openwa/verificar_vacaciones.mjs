// Ejercita el formateador de vacaciones del puente y la deteccion de fichas falsificadas.
//
// Se EXTRAE del index.ts real en lugar de copiarlo, para que la prueba no pueda quedar verificando
// una version vieja. Node 22+ hace falta, por --experimental-strip-types:
//
//   node --experimental-strip-types supabase/functions/whatsapp-openwa/verificar_vacaciones.mjs
//
// Dos fallos reales dieron origen a esto, en este orden:
//
//   1. Por WhatsApp, "las vacaciones de Enrique Ortega Gomez" contesto "0 dias disponibles" cuando
//      tiene 102. La aplicacion acertaba porque pinta una tarjeta con los datos crudos de la
//      herramienta; el puente mandaba la prosa del modelo y tiraba los datos.
//   2. Con la ficha ya puesta, el modelo IMITO el formato sin llamar a la herramienta y devolvio una
//      persona que no existe. Habia aprendido la plantilla de sus propias respuestas guardadas.
import { readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const aqui = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(aqui, 'index.ts'), 'utf8');

function extraerFuncion(nombre) {
  const i = src.indexOf(`function ${nombre}(`);
  if (i < 0) throw new Error(`no se encontro ${nombre}`);
  // Se busca la llave que abre el CUERPO, que es la que cierra su linea. Contar desde la primera
  // llave que aparezca es lo que hacia esta prueba antes, y se rompio en cuanto la funcion declaro un
  // tipo de retorno con llaves —`: { texto: string; nota: string } | null`—: extraia el tipo.
  const abre = src.indexOf('{\n', i);
  if (abre < 0) throw new Error(`no se encontro el cuerpo de ${nombre}`);
  let prof = 0;
  for (let k = abre; k < src.length; k++) {
    if (src[k] === '{') prof++;
    else if (src[k] === '}') { prof--; if (prof === 0) return src.slice(i, k + 1); }
  }
  throw new Error(`llaves sin cerrar en ${nombre}`);
}

const lineaFirma = src.match(/^const FIRMA_FICHA = .*$/m);
if (!lineaFirma) throw new Error('no se encontro FIRMA_FICHA');

const tmp = join(tmpdir(), 'puente-vacaciones.ts');
writeFileSync(tmp, `${lineaFirma[0]}\n\n`
  + `${extraerFuncion('sinAcentos')}\n\n`
  + `${extraerFuncion('afirmaDiasSinRespaldo')}\n\n`
  + `${extraerFuncion('textoDeVacaciones')}\n`
  + 'export { textoDeVacaciones, afirmaDiasSinRespaldo, FIRMA_FICHA };\n', 'utf8');
const { textoDeVacaciones, afirmaDiasSinRespaldo, FIRMA_FICHA } =
  await import('file://' + tmp.replace(/\\/g, '/'));

let fallos = 0;
function ok(desc, cond, extra = '') {
  if (cond) console.log(`  ok     ${desc}`);
  else { console.log(`  FALLA  ${desc}${extra ? '\n           ' + extra : ''}`); fallos++; }
}

// Los datos REALES del empleado 0170, tal como los devuelve calcular_vacaciones. Los saldos se
// verificaron por separado en SQL: 102 dias en 13 periodos, con los siete primeros consumidos.
const enrique = {
  type: 'vacaciones',
  data: {
    colaborador: 'ENRIQUE ORTEGA GOMEZ',
    numero_empleado: '0170',
    total_disponible: 102,
    periodos: [
      { periodo: '2014 - 2015', dias_proporcionales: 6,  dias_solicitados: 6,  dias_disponibles: 0 },
      { periodo: '2015 - 2016', dias_proporcionales: 8,  dias_solicitados: 8,  dias_disponibles: 0 },
      { periodo: '2016 - 2017', dias_proporcionales: 10, dias_solicitados: 10, dias_disponibles: 0 },
      { periodo: '2017 - 2018', dias_proporcionales: 12, dias_solicitados: 12, dias_disponibles: 0 },
      { periodo: '2018 - 2019', dias_proporcionales: 14, dias_solicitados: 14, dias_disponibles: 0 },
      { periodo: '2019 - 2020', dias_proporcionales: 14, dias_solicitados: 14, dias_disponibles: 0 },
      { periodo: '2020 - 2021', dias_proporcionales: 14, dias_solicitados: 14, dias_disponibles: 0 },
      { periodo: '2021 - 2022', dias_proporcionales: 14, dias_solicitados: 2,  dias_disponibles: 12 },
      { periodo: '2022 - 2023', dias_proporcionales: 14, dias_solicitados: 0,  dias_disponibles: 14 },
      { periodo: '2023 - 2024', dias_proporcionales: 22, dias_solicitados: 0,  dias_disponibles: 22 },
      { periodo: '2024 - 2025', dias_proporcionales: 24, dias_solicitados: 0,  dias_disponibles: 24 },
      { periodo: '2025 - 2026', dias_proporcionales: 24, dias_solicitados: 0,  dias_disponibles: 24 },
      { periodo: '2026 - 2027', dias_proporcionales: 6,  dias_solicitados: 0,  dias_disponibles: 6  },
    ],
  },
};

console.log('La ficha, con los datos reales del 0170');
const f = textoDeVacaciones(enrique);
console.log('\n--- lo que llega al telefono ---\n' + f.texto + '\n--------------------------------');
console.log('--- lo que se guarda en la memoria ---\n' + f.nota + '\n--------------------------------\n');
ok('dice 102, que es la cifra verificada en SQL', f.texto.includes('*102*'), f.texto);
ok('NO dice 0 dias disponibles', !new RegExp(FIRMA_FICHA + '\\*0\\*').test(f.texto));
ok('trae el nombre', f.texto.includes('ENRIQUE ORTEGA GOMEZ'));
ok('trae el numero de empleado real', f.texto.includes('0170'));
ok('lista los seis periodos con saldo', (f.texto.match(/^• /gm) || []).length === 6, f.texto);
ok('no lista los agotados, los cuenta', f.texto.includes('7 periodos anteriores ya consumidos'));
ok('no aparece ningun periodo en cero', !/• .*: 0 de/.test(f.texto));

console.log('La nota de memoria NO le enseña la plantilla al modelo');
ok('la nota NO lleva la firma de la ficha', !f.nota.includes(FIRMA_FICHA), f.nota);
ok('la nota no lleva bullets ni asteriscos de formato',
   !f.nota.includes('•') && !f.nota.includes('*'), f.nota);
ok('pero SI conserva el dato para una pregunta de seguimiento',
   f.nota.includes('102') && f.nota.includes('ENRIQUE ORTEGA GOMEZ'), f.nota);

console.log('\nSe detecta una cifra de dias que la herramienta no respalda');
// Los TRES textos falsos reales, en el orden en que el modelo los produjo. Cada uno imita la
// plantilla que le deje en la memoria en el intento anterior, y por eso el guardia ya no mira el
// formato: mira de que iba la pregunta y si hay dato detras.
const inventados = [
  ['prosa, 11/08 18:20',
   'Consultando al sistema... El cálculo arroja **0 días disponibles**. No veo periodos registrados.'],
  ['imitando la ficha, 11/08 19:58',
   '*CLAUDIA PATRICIA BRAVO LOMELI* — empleado 2277\nDias disponibles: *8*\n\nPor periodo:\n'
   + '• 2024 - 2025: 8 de 8\n\n(4 periodos anteriores ya consumidos)'],
  ['imitando la nota, 12/08 08:41',
   '[el sistema entregó la ficha de vacaciones de BRAVO LOMELI: 0 días disponibles'],
  ['la cifra inventada de Ana Maria, 11/08 18:32',
   'Ana María López Vigil, 1250:\n- Disponibles: **16 días**\n- Asignados: 20'],
];
for (const [comoEra, texto] of inventados) {
  ok(`se bloquea: ${comoEra}`, afirmaDiasSinRespaldo('vacaciones de claudia bravo', texto), texto);
}
ok('sin structured no se produce ficha', textoDeVacaciones(null) === null);

console.log('\nY NO se bloquea lo legitimo');
ok('hablar de vacaciones sin dar cifras',
   !afirmaDiasSinRespaldo('puedo pedir vacaciones en diciembre?',
     'Eso lo autoriza tu jefe directo. Puedes crear la solicitud y queda pendiente de aprobación.'));
ok('decir que no encontro a la persona',
   !afirmaDiasSinRespaldo('vacaciones de claudia bravo lomeli',
     'No existe ningún colaborador con ese nombre. ¿Lo busco por número de empleado?'));
ok('una pregunta que no es de vacaciones, aunque lleve numeros',
   !afirmaDiasSinRespaldo('numero de empleado de marco antonio',
     'Es el 0186, y lleva 8 años en la empresa.'));
ok('un saludo', !afirmaDiasSinRespaldo('Soli?', '¡Hola! ¿En qué te ayudo?'));

console.log('\nCuando NO hay datos de vacaciones, se cae al texto del modelo');
ok('otro tipo de structured', textoDeVacaciones({ type: 'collaborators', data: [] }) === null);
ok('sin data', textoDeVacaciones({ type: 'vacaciones' }) === null);
ok('total ausente -> null, no cero inventado',
   textoDeVacaciones({ type: 'vacaciones', data: { colaborador: 'X', periodos: [] } }) === null);
ok('periodos que no son lista', textoDeVacaciones(
   { type: 'vacaciones', data: { colaborador: 'X', total_disponible: 5, periodos: 'no' } }) === null);

console.log('\nCasos de borde');
const sinSaldo = textoDeVacaciones({ type: 'vacaciones', data: {
  colaborador: 'ALGUIEN', numero_empleado: '9999', total_disponible: 0,
  periodos: [{ periodo: '2025 - 2026', dias_proporcionales: 12, dias_disponibles: 0 }] } });
ok('un cero REAL si se dice', sinSaldo.texto.includes(FIRMA_FICHA + '*0*'), sinSaldo.texto);
ok('un solo periodo agotado va en singular',
   sinSaldo.texto.includes('1 periodo anterior ya consumido'), sinSaldo.texto);
const sinNumero = textoDeVacaciones({ type: 'vacaciones', data: {
  colaborador: 'SIN NUMERO', total_disponible: 3,
  periodos: [{ periodo: '2025 - 2026', dias_proporcionales: 12, dias_disponibles: 3 }] } });
ok('sin numero de empleado no deja un guion suelto',
   !sinNumero.texto.includes('—') && sinNumero.texto.includes('*SIN NUMERO*'), sinNumero.texto);
ok('la nota tambien aguanta sin numero', !sinNumero.nota.includes('()'), sinNumero.nota);

console.log(fallos === 0 ? '\nTODO BIEN' : `\n${fallos} FALLAS`);
process.exit(fallos === 0 ? 0 : 1);
