// Lo que las funciones usan y no vive en el repositorio, declarado para poder comprobar los tipos.
//
// ─── Por que hace falta ──────────────────────────────────────────────────────
//
// `tsc` no sabe resolver `jsr:@supabase/supabase-js@2` ni conoce el objeto `Deno`, asi que sin esto
// la comprobacion de tipos se ahoga en dos errores de importacion y nunca llega al codigo nuestro.
//
// Se declaran a proposito FLOJOS -`any`- porque su unico trabajo es dejar pasar lo de fuera para que
// se revise lo de dentro. Lo que se quiere atrapar son los fallos propios, como llamar `hoyISO()` a
// una constante.
//
// Este archivo NO se despliega: vive en `supabase/functions/`, no dentro de ninguna funcion.

declare module "jsr:@supabase/supabase-js@2" {
  export function createClient(url: string, key: string, opciones?: unknown): any;
}

// El que manda los correos de `correspondencia` por SMTP. La version va fija en el import y aqui
// igual: si se sube una, hay que subir las dos, o la comprobacion deja de reconocerlo.
declare module "npm:nodemailer@6.9.16" {
  const nodemailer: any;
  export default nodemailer;
}

// Para pasarle a nodemailer las imagenes incrustadas: espera un Buffer de Node, y el entorno de las
// funciones lo da por su compatibilidad con Node.
declare module "node:buffer" {
  export const Buffer: { from(datos: Uint8Array): unknown };
}

declare const Deno: {
  env: { get(nombre: string): string | undefined };
  serve(manejador: (req: Request) => Response | Promise<Response>): void;
};
