// Ejercita lo que decide si un correo se puede mandar.
//
//   node --experimental-strip-types supabase/functions/correspondencia/verificar_correspondencia.mjs
//
// `validar.ts` no importa nada, asi que se carga tal cual: la prueba no puede quedar verificando una
// copia vieja.
//
// La tabla de CORREOS esta repetida, igual, en `test/correspondencia_test.dart`. La aplicacion valida
// para avisar pronto y el servidor valida para mandar; si las dos expresiones se separan, alguien ve
// «direccion valida» en pantalla y un rechazo al enviar. Las dos tablas iguales son lo que lo detecta.
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

// ─── El mensaje entero ─────────────────────────────────────────────────────
console.log('\nvalidar el mensaje');
const bueno = { asunto: 'Junta', cuerpo: 'Hola', destinatarios: ['ana@sisol.com.mx'] };

ok('uno bien formado pasa', M.validarMensaje(bueno).ok === true);
ok('sin asunto no', M.validarMensaje({ ...bueno, asunto: '  ' }).ok === false);
ok('sin cuerpo no', M.validarMensaje({ ...bueno, cuerpo: '' }).ok === false);
ok('sin destinatarios no', M.validarMensaje({ ...bueno, destinatarios: [] }).ok === false);
ok('asunto demasiado largo no',
  M.validarMensaje({ ...bueno, asunto: 'x'.repeat(M.MAX_ASUNTO + 1) }).ok === false);
ok('cuerpo demasiado largo no',
  M.validarMensaje({ ...bueno, cuerpo: 'x'.repeat(M.MAX_CUERPO + 1) }).ok === false);

// La forma clasica de colar cabeceras: un salto de linea en el asunto con un «Bcc:» detras.
ok('un asunto con salto de linea NO pasa',
  M.validarMensaje({ ...bueno, asunto: 'Hola\r\nBcc: todos@fuera.com' }).ok === false,
  'por aqui se cuela una cabecera Bcc');

// Una mala tumba el envio ENTERO: si se mandara a las buenas, la mala no recibe y nadie se entera.
{
  const r = M.validarMensaje({ ...bueno, destinatarios: ['ana@sisol.com.mx', 'mal'] });
  ok('una direccion mala detiene todo el envio', r.ok === false);
  ok('y dice cual', r.ok === false && JSON.stringify(r.rechazados) === JSON.stringify(['mal']));
}
{
  const muchos = Array.from({ length: M.MAX_DESTINATARIOS + 1 }, (_, i) => `p${i}@x.com`);
  ok(`mas de ${M.MAX_DESTINATARIOS} destinatarios no`,
    M.validarMensaje({ ...bueno, destinatarios: muchos }).ok === false);
  const justo = muchos.slice(0, M.MAX_DESTINATARIOS);
  ok(`exactamente ${M.MAX_DESTINATARIOS} si`,
    M.validarMensaje({ ...bueno, destinatarios: justo }).ok === true);
}
{
  const r = M.validarMensaje({ asunto: '  Junta  ', cuerpo: '  Hola  ', destinatarios: ['ANA@x.com'] });
  ok('recorta y normaliza',
    r.ok && r.mensaje.asunto === 'Junta' && r.mensaje.cuerpo === 'Hola'
      && r.mensaje.destinatarios[0] === 'ana@x.com');
}

// ─── El comunicado tal como sale ───────────────────────────────────────────
//
// Lo que pidio el usuario el 23/09/2026, comprobado sobre el correo que de verdad se entrega a la
// libreria: que salga como «Comunicación SI SOL», que no diga quien lo escribio por NINGUN lado, que
// los destinatarios no se vean entre si, y sin pie.
console.log('\nel comunicado tal como sale');
{
  const mensaje = {
    asunto: 'Aviso de vacaciones',
    cuerpo: 'Estimados colaboradores:\n<b>Se recuerda</b> que el lunes es festivo.',
    destinatarios: ['ana@sisol.com.mx', 'beto@bonanzaprisma.com', 'carla@externo.com'],
  };
  const cuenta = 'comunicacion@sisol.com.mx';
  const c = M.armarCorreo(mensaje, cuenta);

  ok('sale como «Comunicación SI SOL»', c.from.name === 'Comunicación SI SOL',
    `sale como «${c.from.name}»`);
  ok('desde la cuenta compartida', c.from.address === cuenta);

  // Cambiar solo el nombre visible no bastaba: el Reply-To llevaba el correo de quien lo mando y lo
  // descubria en cuanto alguien pulsaba «Responder».
  ok('NO lleva Reply-To', !('replyTo' in c) && !('reply_to' in c) && !('replyto' in c),
    'con Reply-To se sabe quien lo mando al contestar');

  // Los destinatarios no se ven entre si.
  ok('los destinatarios van en copia oculta',
    JSON.stringify(c.bcc) === JSON.stringify(mensaje.destinatarios));
  ok('y NINGUNO va a la vista', !mensaje.destinatarios.some((d) => String(c.to).includes(d)),
    `en «to» va ${c.to}`);
  ok('a la vista solo va la propia cuenta', c.to === cuenta);
  ok('no hay campo cc que los descubra', !('cc' in c));

  // Sin pie: ni en texto ni en HTML.
  ok('el texto va tal cual, sin pie', c.text === mensaje.cuerpo);
  ok('el HTML no lleva pie', !/Enviado por|Para contestar|SISOL\./.test(c.html),
    'el pie decia quien lo habia mandado');
  ok('ni una linea separadora de pie', !c.html.includes('<hr'));

  // Y el cuerpo sigue escapado: sigue siendo la cuenta de la empresa.
  ok('el marcado del usuario se escapa', !c.html.includes('<b>') && c.html.includes('&lt;b&gt;'));
  ok('los saltos de linea se conservan', c.html.includes('<br>'));
  ok('el asunto va tal cual', c.subject === 'Aviso de vacaciones');
}
{
  // La prueba fuerte: el nombre de quien lo escribio no esta en NINGUNA parte del correo. La
  // funcion ni siquiera lo recibe, pero si un dia alguien se lo pasa, esto lo delata.
  const quien = 'Marco Antonio Montoya Lopez';
  const c = M.armarCorreo({ asunto: 'Junta', cuerpo: 'Hola', destinatarios: ['a@x.com'] },
    'comunicacion@sisol.com.mx');
  const todo = JSON.stringify(c);
  ok('el nombre de quien lo escribio no aparece en ningun campo',
    !todo.includes('Marco') && !todo.includes(quien));
  ok('ni la palabra «Enviado»', !todo.includes('Enviado'));
}
{
  // Lo de arriba pasa por construccion: `armarCorreo` nunca recibe el nombre. Lo que SI se puede
  // romper mañana es que alguien, al enviar, añada un `replyTo` o arme el correo a mano en index.ts.
  // Eso se comprueba sobre el FUENTE de la funcion.
  const { readFileSync } = await import('node:fs');
  const idx = readFileSync(join(aqui, 'index.ts'), 'utf8').replace(/\r\n/g, '\n');
  // Solo codigo, sin comentarios: el comentario de cabecera NOMBRA el Reply-To para explicar por que
  // no esta, y un guardia que se dispara con su propia explicacion no sirve.
  const codigo = idx.split('\n').filter((l) => !/^\s*(\/\/|\*|\/\*)/.test(l)).join('\n');
  ok('la funcion envia SOLO lo que arma `armarCorreo`',
    /sendMail\(armarCorreo\(v\.mensaje, remitente\.direccion\)\)/.test(codigo),
    'si el correo se arma a mano en index.ts, estas pruebas dejan de cubrirlo');
  ok('y no añade un replyTo por su cuenta', !/replyTo|reply_to/i.test(codigo),
    'con Reply-To se sabe quien lo mando al contestar');
  ok('ni un pie', !/Enviado por/.test(codigo));
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
  // Causa 1: SMTP_USER es un nombre de usuario y no hay SMTP_FROM.
  const r = M.revisarRemitente('', 'correspondencia');
  ok('usuario sin arroba y sin SMTP_FROM: NO', r.ok === false);
  ok('y el motivo pide poner SMTP_FROM', r.ok === false && r.motivo.includes('Agrega SMTP_FROM'));
  ok('sin repetir el usuario, que es parte de las credenciales',
    r.ok === false && !r.motivo.includes('«correspondencia»'));
}
{
  // Causa 2: se pego con nombre.
  const r = M.revisarRemitente('Sistema <correspondencia@sisol.com.mx>', 'x');
  ok('con nombre y angulos: NO', r.ok === false);
  ok('y el motivo pide solo la direccion', r.ok === false && r.motivo.includes('SOLO la direccion'));
  ok('entre comillas tampoco', M.revisarRemitente('"correspondencia@sisol.com.mx"', 'x').ok === false);
}
{
  // Causa 3: un espacio de ancho cero, que `trim()` no quita y `\s` no reconoce.
  const invisible = 'correspondencia​@sisol.com.mx';
  ok('esCorreo por si solo lo dejaria pasar (por eso hace falta la otra regla)',
    M.esCorreo(invisible) === true,
    'si esto cambia, la regla de ASCII sigue haciendo falta igual');
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
