// Ejercita el formateador de vacaciones del puente.
//
// Se EXTRAE del index.ts real en lugar de copiarlo, para que la prueba no pueda quedar verificando
// una version vieja. Node 22+ hace falta, por --experimental-strip-types:
//
//   node --experimental-strip-types supabase/functions/whatsapp-openwa/verificar_vacaciones.mjs
//
// El caso que dio origen a esto: por WhatsApp, "las vacaciones de Enrique Ortega Gomez" contesto
// "0 dias disponibles" cuando tiene 102. La aplicacion acertaba porque pinta una tarjeta con los
// datos crudos de la herramienta; el puente mandaba la prosa del modelo y tiraba los datos.
import { readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const aqui = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(aqui, 'index.ts'), 'utf8');

const i = src.indexOf('function textoDeVacaciones(');
if (i < 0) throw new Error('no se encontro textoDeVacaciones');
let prof = 0, fin = -1;
for (let k = src.indexOf('{', i); k < src.length; k++) {
  if (src[k] === '{') prof++;
  else if (src[k] === '}') { prof--; if (prof === 0) { fin = k + 1; break; } }
}
const tmp = join(tmpdir(), 'puente-vacaciones.ts');
writeFileSync(tmp, src.slice(i, fin) + '\nexport { textoDeVacaciones };\n', 'utf8');
const { textoDeVacaciones } = await import('file://' + tmp.replace(/\\/g, '/'));

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

console.log('El caso reportado, con los datos reales del 0170');
const t = textoDeVacaciones(enrique);
console.log('\n--- lo que llegaria al telefono ---\n' + t + '\n-----------------------------------\n');
ok('dice 102, que es la cifra verificada en SQL', t.includes('*102*'), t);
ok('NO dice 0 dias disponibles', !/disponibles: \*0\*/.test(t));
ok('trae el nombre', t.includes('ENRIQUE ORTEGA GOMEZ'));
ok('trae el numero de empleado real', t.includes('0170'));
ok('lista los seis periodos con saldo', (t.match(/^• /gm) || []).length === 6, t);
ok('no lista los agotados, los cuenta', t.includes('7 periodos anteriores ya consumidos'), t);
ok('no aparece ningun periodo en cero', !/• .*: 0 de/.test(t));

console.log('\nCuando NO hay datos de vacaciones, se cae al texto del modelo');
ok('otro tipo de structured', textoDeVacaciones({ type: 'collaborators', data: [] }) === null);
ok('structured nulo', textoDeVacaciones(null) === null);
ok('sin data', textoDeVacaciones({ type: 'vacaciones' }) === null);
ok('total ausente -> null, no cero inventado',
   textoDeVacaciones({ type: 'vacaciones', data: { colaborador: 'X', periodos: [] } }) === null);
ok('periodos que no son lista', textoDeVacaciones(
   { type: 'vacaciones', data: { colaborador: 'X', total_disponible: 5, periodos: 'no' } }) === null);

console.log('\nCasos de borde');
const sinSaldo = textoDeVacaciones({ type: 'vacaciones', data: {
  colaborador: 'ALGUIEN', numero_empleado: '9999', total_disponible: 0,
  periodos: [{ periodo: '2025 - 2026', dias_proporcionales: 12, dias_disponibles: 0 }] } });
ok('un cero REAL si se dice', sinSaldo.includes('Dias disponibles: *0*'), sinSaldo);
ok('un solo periodo agotado va en singular',
   sinSaldo.includes('1 periodo anterior ya consumido'), sinSaldo);
const sinNumero = textoDeVacaciones({ type: 'vacaciones', data: {
  colaborador: 'SIN NUMERO', total_disponible: 3,
  periodos: [{ periodo: '2025 - 2026', dias_proporcionales: 12, dias_disponibles: 3 }] } });
ok('sin numero de empleado no deja un guion suelto',
   !sinNumero.includes('—') && sinNumero.includes('*SIN NUMERO*'), sinNumero);

console.log(fallos === 0 ? '\nTODO BIEN' : `\n${fallos} FALLAS`);
process.exit(fallos === 0 ? 0 : 1);
