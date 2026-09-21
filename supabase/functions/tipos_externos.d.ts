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

declare const Deno: {
  env: { get(nombre: string): string | undefined };
  serve(manejador: (req: Request) => Response | Promise<Response>): void;
};
