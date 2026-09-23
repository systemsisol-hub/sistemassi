// Ejercita lo que decide si un comunicado se puede mandar, a quien, y como sale.
//
//   node --experimental-strip-types supabase/functions/correspondencia/verificar_correspondencia.mjs
//
// `validar.ts` solo importa `contenido.ts`, y ninguno de los dos tiene efectos, asi que se cargan tal
// cual: la prueba no puede quedar verificando una copia vieja. El conversor del editor a HTML tiene
// su propio arnes, `verificar_contenido.mjs`.
//
// La tabla de CORREOS esta repetida, igual, en `test/correspondencia_test.dart`. La aplicacion valida
// para avisar pronto y el servidor valida para mandar; si las dos expresiones se separan, alguien ve
// «direccion valida» en pantalla y un rechazo al enviar. Las dos tablas iguales son lo que lo detecta.
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const aqui = dirname(fileURLToPath(import.meta.url));
const M = await import(`file://${join(aqui, 'validar.ts').replace(/\\/g, '/')}`);

let fallos = 0;
function ok(titulo, cond, detalle) {
  if (cond) return;
  fallos++;
  console.log(`  FALLA  ${titulo}`);
  if (detalle) console.log(`         ${detalle}`);
}

/// Un documento del editor con una sola linea de texto, como lo produce flutter_quill.
const doc = (t) => [{ insert: `${t}\n` }];

// ─── La tabla compartida con la prueba de Dart ─────────────────────────────
console.log('que es una direccion de correo');
const SI_SON = [
  'ana@sisol.com.mx',
  'a.b+c@x.co',
  'nombre.apellido@bonanzaprisma.com',
  'ANA@SISOL.COM.MX',
];
const NO_SON = [
  '',
  'ana',
  'ana@',
  '@sisol.com',
  'ana@@sisol.com',
  'ana sisol@x.com',
  'ana@sisol',
  'ana@sisol.c',
  '"ana"@x.com',
  'ana<@x.com',
  'a,b@x.com',
];
for (const c of SI_SON) ok(`«${c}» es correo`, M.esCorreo(c));
for (const c of NO_SON) ok(`«${c}» NO es correo`, !M.esCorreo(c));

// ─── Como se pegan de otro lado ────────────────────────────────────────────
console.log('\nlistas pegadas');
{
  const r = M.normalizarDestinatarios(['Ana@Sisol.com.mx, beto@x.com; ana@sisol.com.mx\ncarla@y.org']);
  ok('separa por coma, punto y coma y salto de linea',
    JSON.stringify(r.validos) === JSON.stringify(['ana@sisol.com.mx', 'beto@x.com', 'carla@y.org']),
    `obtuve ${JSON.stringify(r.validos)}`);
  ok('pasa a minusculas y no repite', r.validos.filter((d) => d === 'ana@sisol.com.mx').length === 1);
  ok('sin rechazos', r.rechazados.length === 0);
}
{
  const r = M.normalizarDestinatarios(['ana@x.com, no-es-correo', 'beto@y.com']);
  ok('aparta la que no es', JSON.stringify(r.rechazados) === JSON.stringify(['no-es-correo']),
    `obtuve ${JSON.stringify(r.rechazados)}`);
  ok('y conserva las buenas', r.validos.length === 2);
}
ok('algo que no es lista no revienta', M.normalizarDestinatarios('ana@x.com').validos.length === 0);

// ─── El asunto y el cuerpo ─────────────────────────────────────────────────
console.log('\nel asunto y el cuerpo');
const bueno = { asunto: 'Junta', contenido: doc('Hola') };

ok('uno bien formado pasa', M.validarContenido(bueno).ok === true);
ok('sin asunto no', M.validarContenido({ ...bueno, asunto: '  ' }).ok === false);
ok('asunto demasiado largo no',
  M.validarContenido({ ...bueno, asunto: 'x'.repeat(M.MAX_ASUNTO + 1) }).ok === false);
ok('sin cuerpo no', M.validarContenido({ ...bueno, contenido: [{ insert: '\n' }] }).ok === false);
ok('un cuerpo de solo espacios no', M.validarContenido({ ...bueno, contenido: doc('   ') }).ok === false);
ok('cuerpo demasiado largo no',
  M.validarContenido({ ...bueno, contenido: doc('x'.repeat(M.MAX_CUERPO + 1)) }).ok === false);

// La forma clasica de colar cabeceras: un salto de linea en el asunto con un «Bcc:» detras.
ok('un asunto con salto de linea NO pasa',
  M.validarContenido({ ...bueno, asunto: 'Hola\r\nBcc: todos@fuera.com' }).ok === false,
  'por aqui se cuela una cabecera Bcc');

// El cuerpo NO se acepta como HTML: solo como documento del editor. Si se aceptara, cualquiera con el
// permiso podria llamar a la funcion directamente con el HTML que quisiera.
ok('un cuerpo mandado como HTML crudo NO se acepta',
  M.validarContenido({ asunto: 'x', contenido: '<form action="https://x"><input></form>' }).ok === false);
ok('ni como campo html aparte',
  M.validarContenido({ asunto: 'x', html: '<b>hola</b>' }).ok === false);
{
  const r = M.validarContenido({ asunto: '  Junta  ', contenido: doc('Hola') });
  ok('recorta el asunto y convierte el cuerpo',
    r.ok && r.contenido.asunto === 'Junta' && r.contenido.texto === 'Hola'
      && r.contenido.html.includes('<p '));
}

// ─── Los destinatarios ─────────────────────────────────────────────────────
console.log('\nlos destinatarios');
ok('uno bien', M.validarDestinatarios(['ana@sisol.com.mx']).ok === true);
ok('ninguno no', M.validarDestinatarios([]).ok === false);
{
  // Una mala tumba el envio ENTERO: si se mandara a las buenas, la mala no recibe y nadie se entera.
  const r = M.validarDestinatarios(['ana@sisol.com.mx', 'mal']);
  ok('una direccion mala detiene todo el envio', r.ok === false);
  ok('y dice cual', r.ok === false && JSON.stringify(r.rechazados) === JSON.stringify(['mal']));
}
{
  // El tope subio a 500 por comunicado: con 74 empleados, el de 50 ya no dejaba mandar a «todos».
  ok('el tope por comunicado alcanza para toda la plantilla (74)', M.MAX_DESTINATARIOS >= 74);
  const muchos = Array.from({ length: M.MAX_DESTINATARIOS + 1 }, (_, i) => `p${i}@x.com`);
  ok(`mas de ${M.MAX_DESTINATARIOS} no`, M.validarDestinatarios(muchos).ok === false);
  ok(`exactamente ${M.MAX_DESTINATARIOS} si`,
    M.validarDestinatarios(muchos.slice(0, M.MAX_DESTINATARIOS)).ok === true);
}
{
  // Un correo que viene a mano Y dentro de una lista se manda una sola vez.
  const r = M.validarDestinatarios(['ana@x.com', 'ANA@x.com', 'beto@x.com']);
  ok('sin repetidos entre lo tecleado y las listas', r.ok && r.destinatarios.length === 2);
}

// ─── Las tandas ────────────────────────────────────────────────────────────
console.log('\nlas tandas');
{
  const setenta = Array.from({ length: 74 }, (_, i) => `p${i}@x.com`);
  const t = M.lotes(setenta);
  ok('74 destinatarios salen en 2 tandas', t.length === 2, `salieron ${t.length}`);
  ok(`la primera de ${M.TAMANO_LOTE}`, t[0].length === M.TAMANO_LOTE);
  ok('la segunda con el resto', t[1].length === 74 - M.TAMANO_LOTE);
  ok('sin perder ni repetir a nadie', t.flat().length === 74 && new Set(t.flat()).size === 74);
  ok('en el mismo orden', t.flat().every((d, i) => d === setenta[i]));
}
ok('exactamente una tanda llena', M.lotes(Array(M.TAMANO_LOTE).fill('a')).length === 1);
ok('una lista vacia no da tandas', M.lotes([]).length === 0);
ok('un tamaño absurdo no cuelga', M.lotes(['a', 'b'], 0).length === 2);

// ─── Las listas de distribucion ────────────────────────────────────────────
console.log('\nlas listas de distribucion');
{
  const perfiles = new Map([
    ['p1', { mail_user: 'Ana@Sisol.com.mx', email: 'ana.cuenta@x.com', status_sys: 'ACTIVO' }],
    ['p2', { mail_user: '', email: 'beto@x.com', status_sys: 'ACTIVO' }],
    ['p3', { mail_user: 'carla@sisol.com.mx', email: null, status_sys: 'BAJA' }],
    ['p4', { mail_user: 'no-es-correo', email: '', status_sys: 'ACTIVO' }],
  ]);
  const r = M.resolverMiembros([
    { profile_id: 'p1', correo: null },
    { profile_id: 'p2', correo: null },
    { profile_id: 'p3', correo: null },
    { profile_id: 'p4', correo: null },
    { profile_id: 'p9', correo: null },
    { profile_id: null, correo: 'Externo@Cliente.com' },
    { profile_id: null, correo: 'ana@sisol.com.mx' },
  ], perfiles);

  ok('del compañero, el buzon de trabajo antes que el de la cuenta', r.correos.includes('ana@sisol.com.mx'));
  ok('sin buzon de trabajo, el de la cuenta', r.correos.includes('beto@x.com'));
  ok('el correo tecleado va tal cual, en minusculas', r.correos.includes('externo@cliente.com'));
  // Guardar por persona es lo que hace que la lista no se quede vieja.
  ok('quien se dio de BAJA ya no recibe', !r.correos.includes('carla@sisol.com.mx'));
  ok('ni quien no tiene correo valido', !r.correos.some((c) => c.includes('no-es-correo')));
  ok('se cuentan los que ya no alcanza (baja, sin correo, borrado)', r.omitidos === 3, `omitidos ${r.omitidos}`);
  ok('y no se repite quien esta dos veces', r.correos.filter((c) => c === 'ana@sisol.com.mx').length === 1);
}
ok('un uuid es uuid', M.esUuid('5506f8af-326a-4bec-a6c4-97cbd244a299'));
ok('lo demas no', !M.esUuid("1' or '1'='1") && !M.esUuid(''));

// ─── El comunicado tal como sale ───────────────────────────────────────────
//
// Lo que pidio el usuario el 23/09/2026, comprobado sobre el correo que de verdad se entrega a la
// libreria: que salga como «Comunicación SI SOL», que no diga quien lo escribio por NINGUN lado, que
// los destinatarios no se vean entre si, y sin pie.
console.log('\nel comunicado tal como sale');
{
  const contenido = { asunto: 'Aviso', html: '<div><p>Hola</p></div>', texto: 'Hola' };
  const lote = ['ana@sisol.com.mx', 'beto@bonanzaprisma.com', 'carla@externo.com'];
  const cuenta = 'comunicacion@sisol.com.mx';
  const c = M.armarCorreo(contenido, cuenta, lote);

  ok('sale como «Comunicación SI SOL»', c.from.name === 'Comunicación SI SOL', `sale como «${c.from.name}»`);
  ok('desde la cuenta compartida', c.from.address === cuenta);
  // Cambiar solo el nombre visible no bastaba: el Reply-To llevaba el correo de quien lo mando y lo
  // descubria en cuanto alguien pulsaba «Responder».
  ok('NO lleva Reply-To', !('replyTo' in c) && !('reply_to' in c), 'con Reply-To se sabe quien lo mando');
  ok('la tanda va en copia oculta', JSON.stringify(c.bcc) === JSON.stringify(lote));
  ok('y NINGUNO va a la vista', !lote.some((d) => String(c.to).includes(d)), `en «to» va ${c.to}`);
  ok('a la vista solo va la propia cuenta', c.to === cuenta);
  ok('no hay campo cc que los descubra', !('cc' in c));
  ok('el HTML y el texto van tal cual los dejo el conversor', c.html === contenido.html && c.text === 'Hola');
  ok('el asunto va tal cual', c.subject === 'Aviso');
}
{
  // Lo de arriba pasa por construccion: `armarCorreo` nunca recibe el nombre. Lo que SI se puede
  // romper mañana es que alguien, al enviar, añada un `replyTo` o arme el correo a mano en index.ts.
  // Eso se comprueba sobre el FUENTE de la funcion.
  const idx = readFileSync(join(aqui, 'index.ts'), 'utf8').replace(/\r\n/g, '\n');
  // Solo codigo, sin comentarios: el comentario de cabecera NOMBRA el Reply-To para explicar por que
  // no esta, y un guardia que se dispara con su propia explicacion no sirve.
  const codigo = idx.split('\n').filter((l) => !/^\s*(\/\/|\*|\/\*)/.test(l)).join('\n');
  ok('la funcion envia SOLO lo que arma `armarCorreo`',
    /sendMail\(armarCorreo\(c\.contenido, remitente\.direccion, lote\)\)/.test(codigo),
    'si el correo se arma a mano en index.ts, estas pruebas dejan de cubrirlo');
  ok('y no añade un replyTo por su cuenta', !/replyTo|reply_to/i.test(codigo),
    'con Reply-To se sabe quien lo mando al contestar');
  ok('ni un pie', !/Enviado por/.test(codigo));
  // El HTML lo escribe el conversor: la funcion no puede aceptar HTML de la peticion.
  ok('la funcion no lee ningun HTML de la peticion', !/entrada\.(html|cuerpo_html|cuerpoHtml)/.test(codigo));
}

// ─── El remitente ──────────────────────────────────────────────────────────
//
// El primer envio real fallo con «501 5.1.7 Bad sender address syntax», que no dice QUE esta mal.
// Tres causas tipicas, y cada una tiene que dar un motivo distinto que diga que arreglar.
console.log('\nel remitente');
{
  const r = M.revisarRemitente('correspondencia@sisol.com.mx', 'correspondencia');
  ok('con SMTP_FROM bien puesto, se usa', r.ok && r.direccion === 'correspondencia@sisol.com.mx');
}
{
  const r = M.revisarRemitente('', 'correspondencia@sisol.com.mx');
  ok('sin SMTP_FROM, vale SMTP_USER si es un correo', r.ok && r.direccion === 'correspondencia@sisol.com.mx');
}
{
  const r = M.revisarRemitente('', 'correspondencia');
  ok('usuario sin arroba y sin SMTP_FROM: NO', r.ok === false);
  ok('y el motivo pide poner SMTP_FROM', r.ok === false && r.motivo.includes('Agrega SMTP_FROM'));
  ok('sin repetir el usuario, que es parte de las credenciales',
    r.ok === false && !r.motivo.includes('«correspondencia»'));
}
{
  const r = M.revisarRemitente('Sistema <correspondencia@sisol.com.mx>', 'x');
  ok('con nombre y angulos: NO', r.ok === false);
  ok('y el motivo pide solo la direccion', r.ok === false && r.motivo.includes('SOLO la direccion'));
  ok('entre comillas tampoco', M.revisarRemitente('"correspondencia@sisol.com.mx"', 'x').ok === false);
}
{
  // Un espacio de ancho cero, que `trim()` no quita y `\s` no reconoce.
  const invisible = 'correspondencia​@sisol.com.mx';
  ok('esCorreo por si solo lo dejaria pasar (por eso hace falta la otra regla)', M.esCorreo(invisible) === true);
  const r = M.revisarRemitente(invisible, 'x');
  ok('un caracter invisible: NO', r.ok === false);
  ok('y el motivo dice que se escriba a mano', r.ok === false && r.motivo.includes('a mano'));
}
ok('espacios alrededor se toleran', M.revisarRemitente('  correo@sisol.com.mx  ', '').ok === true);
ok('sin nada de nada, lo dice', M.revisarRemitente('', '').ok === false);

// ─── Los puertos que Supabase deja usar ────────────────────────────────────
console.log('\npuertos');
ok('465 si', M.puertoPermitido(465).ok === true);
ok('587 NO: Supabase lo bloquea', M.puertoPermitido(587).ok === false);
ok('25 NO: Supabase lo bloquea', M.puertoPermitido(25).ok === false);
ok('el motivo dice que use el 465', M.puertoPermitido(587).motivo?.includes('465'));
ok('0 no es puerto', M.puertoPermitido(0).ok === false);
ok('70000 no es puerto', M.puertoPermitido(70000).ok === false);
ok('NaN no es puerto', M.puertoPermitido(Number('abc')).ok === false);
ok('otro puerto cualquiera se deja intentar', M.puertoPermitido(2525).ok === true);

console.log('');
if (fallos > 0) {
  console.log(`${fallos} FALLAS`);
  process.exit(1);
}
console.log('TODO BIEN');
