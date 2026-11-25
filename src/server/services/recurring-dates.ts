/**
 * Cálculo de fechas de movimientos recurrentes. Trabaja con fechas de
 * calendario "YYYY-MM-DD" (sin hora) para evitar errores de zona horaria.
 */
export type Frequency = "semanal" | "quincenal" | "mensual" | "anual";

const pad = (n: number) => String(n).padStart(2, "0");
const fmt = (y: number, m: number, day: number) => `${y}-${pad(m)}-${pad(day)}`;
const parse = (s: string) => {
  const [y, m, day] = s.split("-").map(Number);
  return { y, m, day };
};
export const daysInMonth = (y: number, m: number) => new Date(Date.UTC(y, m, 0)).getUTCDate();

function addDays(s: string, n: number): string {
  const { y, m, day } = parse(s);
  const t = new Date(Date.UTC(y, m - 1, day + n));
  return fmt(t.getUTCFullYear(), t.getUTCMonth() + 1, t.getUTCDate());
}

function addMonthsClamped(y: number, m: number, months: number, anchorDay: number) {
  const idx = y * 12 + (m - 1) + months;
  const ny = Math.floor(idx / 12);
  const nm = (idx % 12) + 1;
  return fmt(ny, nm, Math.min(anchorDay, daysInMonth(ny, nm)));
}

/**
 * Siguiente fecha después de `current`.
 * - Semanal: +7 días.
 * - Quincenal: días 15 y último de cada mes (quincena costarricense).
 * - Mensual: mismo día que `start`; si el mes es más corto, el último día.
 * - Anual: mismo día y mes que `start`; 29 de febrero cae el 28 en años no bisiestos.
 */
export function nextDueDate(current: string, frequency: Frequency, start: string): string {
  const c = parse(current);
  const anchor = parse(start);
  switch (frequency) {
    case "semanal":
      return addDays(current, 7);
    case "quincenal": {
      const last = daysInMonth(c.y, c.m);
      if (c.day < 15) return fmt(c.y, c.m, 15);
      if (c.day < last) return fmt(c.y, c.m, last);
      return addMonthsClamped(c.y, c.m, 1, 15);
    }
    case "mensual":
      return addMonthsClamped(c.y, c.m, 1, anchor.day);
    case "anual":
      return addMonthsClamped(c.y, anchor.m, 12, anchor.day);
  }
}

/** Primera fecha válida de la regla, a partir de `start`. */
export function firstDueDate(start: string, frequency: Frequency): string {
  if (frequency !== "quincenal") return start;
  const s = parse(start);
  if (s.day === 15 || s.day === daysInMonth(s.y, s.m)) return start;
  return nextDueDate(start, "quincenal", start);
}

/** Fechas vencidas desde `from` (incluida) hasta `until` (incluida), sin pasar de `end`. */
export function dueDatesBetween(
  from: string,
  until: string,
  frequency: Frequency,
  start: string,
  end?: string | null,
  max = 400,
): string[] {
  const out: string[] = [];
  let cur = from;
  while (cur <= until && (!end || cur <= end) && out.length < max) {
    out.push(cur);
    cur = nextDueDate(cur, frequency, start);
  }
  return out;
}
