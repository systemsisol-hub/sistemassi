// Arma la invitación de calendario (iCalendar, RFC 5545) que entienden Outlook, Gmail y el iPhone.
//
// Sin dependencias a propósito: es texto, y así se puede probar con Node sin desplegar
// (ver verificar_ics.mjs).

export type Persona = { nombre?: string | null; email: string };

export type DatosInvitacion = {
  metodo: "REQUEST" | "CANCEL";
  uid: string;
  secuencia: number;
  inicio: Date;
  fin: Date;
  titulo: string;
  descripcion?: string | null;
  lugar?: string | null;
  organizador: Persona;
  asistentes: Persona[];
  /// Para una serie que se repite: `FREQ=…;UNTIL=…`.
  rrule?: string | null;
  /// Para cambiar o cancelar UNA fecha de una serie: su inicio original.
  recurrenceId?: Date | null;
  ahora?: Date;
};

const RE_CORREO = /^[^@\s<>",;]+@[^@\s<>",;]+\.[^@\s<>",;]+$/;

export function esCorreo(t: string): boolean {
  return RE_CORREO.test(t.trim());
}

/// 2026-10-07T17:00:00Z → 20261007T170000Z
export function fechaUtc(d: Date): string {
  return d.toISOString().replace(/[-:]/g, "").replace(/\.\d{3}/, "");
}

/// Texto escapado como pide el formato: barra, punto y coma, coma y saltos de línea.
export function escapar(t: string): string {
  return t
    .replace(/\\/g, "\\\\")
    .replace(/;/g, "\\;")
    .replace(/,/g, "\\,")
    .replace(/\r?\n/g, "\\n");
}

/// Parte las líneas de más de 75 bytes (el formato lo exige; Outlook rechaza las largas).
export function doblar(linea: string): string {
  const bytes = new TextEncoder();
  if (bytes.encode(linea).length <= 75) return linea;
  const partes: string[] = [];
  let actual = "";
  for (const ch of linea) {
    const limite = partes.length === 0 ? 75 : 74; // las siguientes llevan un espacio al inicio
    if (bytes.encode(actual + ch).length > limite) {
      partes.push(actual);
      actual = ch;
    } else {
      actual += ch;
    }
  }
  partes.push(actual);
  return partes.join("\r\n ");
}

/// La repetición tal como la guarda la app («Semanalmente»…) a regla de calendario.
export function rruleDe(repeticion: string | null | undefined, hasta: Date): string | null {
  const frec: Record<string, string> = {
    Diariamente: "DAILY",
    Semanalmente: "WEEKLY",
    Mensualmente: "MONTHLY",
    Anualmente: "YEARLY",
  };
  const f = repeticion ? frec[repeticion] : undefined;
  return f ? `FREQ=${f};UNTIL=${fechaUtc(hasta)}` : null;
}

function cn(p: Persona): string {
  const nombre = (p.nombre ?? "").replace(/["\\]/g, "").trim();
  return nombre ? `;CN="${nombre}"` : "";
}

export function construirIcs(d: DatosInvitacion): string {
  const ahora = d.ahora ?? new Date();
  const cancelar = d.metodo === "CANCEL";
  const lineas = [
    "BEGIN:VCALENDAR",
    "PRODID:-//SI SOL//SistemasSI Calendario//ES",
    "VERSION:2.0",
    "CALSCALE:GREGORIAN",
    `METHOD:${d.metodo}`,
    "BEGIN:VEVENT",
    `UID:${d.uid}`,
    `SEQUENCE:${d.secuencia}`,
    `DTSTAMP:${fechaUtc(ahora)}`,
    `DTSTART:${fechaUtc(d.inicio)}`,
    `DTEND:${fechaUtc(d.fin)}`,
    ...(d.recurrenceId ? [`RECURRENCE-ID:${fechaUtc(d.recurrenceId)}`] : []),
    ...(d.rrule && !d.recurrenceId ? [`RRULE:${d.rrule}`] : []),
    `SUMMARY:${escapar(d.titulo)}`,
    ...(d.descripcion ? [`DESCRIPTION:${escapar(d.descripcion)}`] : []),
    ...(d.lugar ? [`LOCATION:${escapar(d.lugar)}`] : []),
    `ORGANIZER${cn(d.organizador)}:mailto:${d.organizador.email}`,
    ...d.asistentes.map((a) =>
      `ATTENDEE${cn(a)};ROLE=REQ-PARTICIPANT;PARTSTAT=NEEDS-ACTION;RSVP=TRUE:mailto:${a.email}`
    ),
    `STATUS:${cancelar ? "CANCELLED" : "CONFIRMED"}`,
    "TRANSP:OPAQUE",
    ...(cancelar ? [] : [
      "BEGIN:VALARM",
      "ACTION:DISPLAY",
      "DESCRIPTION:Recordatorio",
      "TRIGGER:-PT15M",
      "END:VALARM",
    ]),
    "END:VEVENT",
    "END:VCALENDAR",
  ];
  return lineas.map(doblar).join("\r\n") + "\r\n";
}
