import Decimal from "decimal.js";

/**
 * Aritmética monetaria exacta. Nunca usar `number` para sumar dinero:
 * los montos viajan como string (así los entrega PostgreSQL para NUMERIC)
 * y se operan con Decimal.
 */
Decimal.set({ precision: 40, rounding: Decimal.ROUND_HALF_UP });

export type MoneyInput = string | number | Decimal;

export const d = (value: MoneyInput): Decimal => new Decimal(value);

/** Redondea a 2 decimales (centavos / céntimos). */
export const round2 = (value: MoneyInput): Decimal => d(value).toDecimalPlaces(2, Decimal.ROUND_HALF_UP);

export const sum = (values: MoneyInput[]): Decimal => values.reduce<Decimal>((acc, v) => acc.plus(v), d(0));

/** Representación canónica para guardar en la base: "1234.50". */
export const toDbAmount = (value: MoneyInput): string => round2(value).toFixed(2);

const AMOUNT_RE = /^\d{1,16}(\.\d{1,2})?$/;

/**
 * Interpreta lo que el usuario escribe: "1234.5", "1,234.50", "1.234,50" o "₡ 25 000".
 * Devuelve null si no es un monto válido mayor que cero.
 */
export function parseAmount(raw: string): Decimal | null {
  let s = raw.trim().replace(/[₡$€\s]/g, "");
  if (!s) return null;
  const lastComma = s.lastIndexOf(",");
  const lastDot = s.lastIndexOf(".");
  if (lastComma > -1 && lastDot > -1) {
    // El separador que aparece de último es el decimal
    s = lastComma > lastDot ? s.replace(/\./g, "").replace(",", ".") : s.replace(/,/g, "");
  } else if (lastComma > -1) {
    // Solo comas: decimal si hay 1 o 2 dígitos después de la última
    const decimals = s.length - lastComma - 1;
    s = decimals <= 2 && s.split(",").length === 2 ? s.replace(",", ".") : s.replace(/,/g, "");
  } else if (lastDot > -1 && s.split(".").length > 2) {
    s = s.replace(/\./g, "");
  }
  if (!AMOUNT_RE.test(s)) return null;
  const value = d(s);
  return value.gt(0) ? value : null;
}

const formatters = new Map<string, Intl.NumberFormat>();

export function formatMoney(amount: MoneyInput, currency: string, opts: { hidden?: boolean } = {}): string {
  if (opts.hidden) return "••••••";
  let f = formatters.get(currency);
  if (!f) {
    f = new Intl.NumberFormat("es-CR", { style: "currency", currency, minimumFractionDigits: 2, maximumFractionDigits: 2 });
    formatters.set(currency, f);
  }
  // Intl recibe number solo para mostrar; el cálculo ya se hizo con Decimal.
  return f.format(round2(amount).toNumber());
}
