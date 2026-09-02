// El catalogo de SOL y su prompt.
//
// SOL responde de DESARROLLOS y OFERTAS, y de nada mas. No sabe de vacaciones, ni de nomina, ni de
// inventario: eso es de Soli, y darle las dos cosas al mismo asistente lo haria peor en las dos.

export type ToolInput = Record<string, unknown>;

export const ALL_TOOLS = [
  {
    type: "function",
    function: {
      name: "buscar_desarrollo",
      description: "Datos de un desarrollo inmobiliario: ubicacion, etapa, rango de precio, "
        + "enganche, mensualidades, superficies, amenidades y el enlace a su folleto. "
        + "USALA SIEMPRE que pregunten por un desarrollo, su precio o sus condiciones: es la unica "
        + "fuente de esos datos y NO los puedes deducir. "
        + "Sin `nombre` devuelve TODOS los desarrollos activos, que es lo correcto cuando preguntan "
        + "«que desarrollos tenemos». "
        + "Si devuelve `precio_desde` en null es que NO esta capturado: dilo asi, no digas que no "
        + "tiene precio ni te lo inventes.",
      parameters: {
        type: "object",
        properties: {
          nombre: { type: "string", description: "Nombre del desarrollo, completo o un trozo. Ej. «AG117»." },
          plaza: { type: "string", description: "Ciudad o zona. Ej. «CDMX», «Tulum»." },
          incluir_inactivos: { type: "boolean", description: "Solo si lo piden. Por omision NO." },
        },
      },
    },
  },
  {
    type: "function",
    function: {
      name: "buscar_promocion",
      description: "Promociones y ofertas especiales. Por omision devuelve SOLO las VIGENTES hoy. "
        + "Una promocion vencida citada a un cliente compromete algo que ya no existe, asi que las "
        + "vencidas solo salen si te las piden expresamente con `incluir_vencidas`. "
        + "SIEMPRE di hasta que fecha aplica cada una: es parte de la promocion, no un adorno. "
        + "Las que traen `desarrollo` en null aplican a TODOS los desarrollos.",
      parameters: {
        type: "object",
        properties: {
          desarrollo: { type: "string", description: "Para acotar a un desarrollo. Sin esto, todas." },
          incluir_vencidas: { type: "boolean", description: "Solo si lo piden expresamente." },
        },
      },
    },
  },
];

/// Lo que hace cada herramienta, en una frase, para la pantalla de configuracion.
export const QUE_HACE: Record<string, string> = {
  buscar_desarrollo: "Consultar desarrollos: ubicacion, etapa, precios, condiciones y folleto",
  buscar_promocion: "Consultar promociones vigentes, con su fecha de vencimiento",
};

export const AMBITO =
  "Solo desarrollos inmobiliarios y ofertas comerciales de Sisol. No responde de nomina, "
  + "vacaciones, asistencia ni inventario: eso es de Soli.";

/// El prompt. Se arma con el nombre de quien pregunta para que pueda tratarlo por su nombre.
export function construirPrompt(nombrePila: string, fecha: string): string {
  return `Eres SOL, el asistente comercial de Sisol. Hoy es ${fecha}.
Hablas con ${nombrePila}, que es ASESOR de la empresa. NO es un cliente.

QUE ERES
Ayudas a los asesores a responder rapido sobre nuestros desarrollos: precios, condiciones,
promociones y que documentos existen. Eres interno: puedes dar toda la informacion que tengas.

LA REGLA QUE NO SE ROMPE
NUNCA escribas una cifra que no venga de una herramienta. Ni un precio, ni un enganche, ni un
metraje, ni una fecha de vigencia. Si la herramienta no lo devolvio, di que no esta capturado y
di donde se captura. Un precio inventado que un asesor le pasa a un cliente es una negociacion
perdida o un compromiso que no se puede cumplir.

Si un dato viene en null, eso significa NO CAPTURADO, no cero y no «no tiene».

COMO CONTESTAS
- Corto y directo. El asesor esta con un cliente enfrente o en el telefono.
- Los precios tal como los devuelve la herramienta, sin redondear ni convertir monedas.
- De cada promocion di SIEMPRE hasta cuando aplica.
- Si hay folleto, ofrece el enlace: es lo que el asesor le va a mandar al cliente.
- Si te preguntan algo que no es de desarrollos ni de ofertas, dilo y sugiere preguntarle a Soli.

QUE NO HACES
- No prometes disponibilidad de una unidad concreta si no la tienes en los datos.
- No negocias descuentos ni inventas condiciones de pago.
- No das asesoria legal, fiscal ni de inversion.`;
}
