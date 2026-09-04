// Quien puede comprar cada extra. Se calcula, no se deduce.
//
// ─── Por que existe este archivo ────────────────────────────────────────────
//
// Reglas de AG117, dictadas por el usuario el 04/09/2026:
//
//   * Ningun extra sin departamento. Los extras son roof, bodega y estacionamiento.
//   * Bodega: solo departamentos arriba de $8,000,000.
//   * Estacionamiento: solo departamentos arriba de $7,000,000.
//   * Roof garden: solo con la compra de un departamento.
//
// Puestas en el prompt, el modelo tendria que comparar «este depto cuesta 9,310,000» contra «arriba
// de 8,000,000» en cada respuesta. Comparar numeros es donde falla, y aqui fallar significa
// prometerle una bodega a un cliente que no puede comprarla —y eso se descubre en la firma—.
//
// Asi que el umbral es un dato en `reglas_extras` y la calificacion se calcula aqui. El modelo solo
// redacta la lista que recibe.
//
// Sin efectos al importarlo, a proposito, para que el arnes pueda ejercitarlo.

/// Una regla tal como esta en la base.
export interface ReglaExtra {
  extra: string;
  requiere_departamento: boolean;
  precio_minimo_departamento: number | null;
  minimo_inclusivo: boolean;
  notas?: string | null;
}

/// Si una unidad es un DEPARTAMENTO.
///
/// Se mira `tipo`, que en AG117 vale «Depto» o «ROOF». Se compara sin acentos ni mayusculas y por
/// prefijo, porque el dia que alguien escriba «Departamento» o «DEPTO.» sigue siendo lo mismo.
export function esDepartamento(tipo: unknown): boolean {
  const t = String(tipo ?? "").toLowerCase().trim();
  return t.startsWith("depto") || t.startsWith("departamento") || t.startsWith("depa");
}

/// Los extras que da derecho a comprar UNA unidad.
///
/// Si la unidad no es un departamento, la lista sale vacia: ningun extra se compra suelto, asi que
/// un roof no da derecho a una bodega ni a otro roof.
export function extrasQueCalifica(
  unidad: { tipo?: unknown; precio?: unknown },
  reglas: ReglaExtra[],
): string[] {
  if (!esDepartamento(unidad.tipo)) return [];

  const precio = Number(unidad.precio);
  const sirve: string[] = [];

  for (const r of reglas) {
    // Un extra que NO exige departamento se puede comprar suelto, asi que no depende de esta
    // unidad y no se lista como «derecho» de ella.
    if (!r.requiere_departamento) continue;

    const minimo = r.precio_minimo_departamento;
    if (minimo === null || minimo === undefined) {
      // Sin minimo: basta con que sea un departamento. Es el caso del roof.
      sirve.push(r.extra);
      continue;
    }
    if (!Number.isFinite(precio)) continue; // Sin precio no se puede decir que si.

    // `minimo_inclusivo` decide el borde. «Arriba de 8,000,000» es false: un departamento de
    // exactamente 8,000,000 NO califica.
    const califica = r.minimo_inclusivo ? precio >= minimo : precio > minimo;
    if (califica) sirve.push(r.extra);
  }
  return sirve;
}

/// Si una unidad califica para un extra concreto, para poder FILTRAR por el.
export function calificaPara(
  unidad: { tipo?: unknown; precio?: unknown },
  extra: string,
  reglas: ReglaExtra[],
): boolean {
  const buscado = extra.toUpperCase().trim();
  return extrasQueCalifica(unidad, reglas)
    .some((e) => e.toUpperCase() === buscado);
}

/// La regla en palabras, para que el modelo la lea sin tener que interpretar numeros.
///
/// Se redacta AQUI y no en el prompt por lo mismo que todo lo demas: el numero sale del dato, y la
/// frase no puede contradecirlo porque se construye con el.
export function reglaEnPalabras(r: ReglaExtra): string {
  const nombre = r.extra.toLowerCase();
  const partes: string[] = [];

  if (r.requiere_departamento) {
    partes.push(`El ${nombre} NO se puede comprar solo: hace falta comprar un departamento`);
  } else {
    partes.push(`El ${nombre} se puede comprar sin departamento`);
  }

  const minimo = r.precio_minimo_departamento;
  if (r.requiere_departamento && minimo !== null && minimo !== undefined) {
    const conComas = Number(minimo).toLocaleString("en-US");
    partes.push(r.minimo_inclusivo
      ? `y ese departamento tiene que costar $${conComas} o mas`
      : `y ese departamento tiene que costar MAS de $${conComas}`);
  } else if (r.requiere_departamento) {
    partes.push("sin importar el precio del departamento");
  }

  return partes.join(" ") + ".";
}
