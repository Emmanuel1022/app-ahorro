import Decimal from "decimal.js";
import { d, round2, type MoneyInput } from "@/lib/money";

/** 1 unidad de `from` = `rate` unidades de `to`, vigente desde `effectiveDate`. */
export interface ExchangeRate {
  from: string;
  to: string;
  rate: MoneyInput;
  effectiveDate: string; // YYYY-MM-DD
}

export interface RateLookup {
  rate: Decimal;
  effectiveDate: string | null;
}

/**
 * Busca el tipo de cambio de referencia más reciente con fecha <= `on`.
 * Acepta la tasa directa o la inversa. Devuelve null si no existe.
 */
export function findRate(rates: ExchangeRate[], from: string, to: string, on: string): RateLookup | null {
  if (from === to) return { rate: d(1), effectiveDate: null };
  let best: RateLookup | null = null;
  for (const r of rates) {
    if (r.effectiveDate > on) continue;
    let rate: Decimal | null = null;
    if (r.from === from && r.to === to) rate = d(r.rate);
    else if (r.from === to && r.to === from) rate = d(1).div(r.rate);
    if (rate && (!best || (best.effectiveDate ?? "") < r.effectiveDate)) {
      best = { rate, effectiveDate: r.effectiveDate };
    }
  }
  return best;
}

export function convert(amount: MoneyInput, rate: MoneyInput): Decimal {
  return round2(d(amount).times(rate));
}

export interface Balance {
  amount: MoneyInput;
  currency: string;
}

export interface Consolidated {
  currency: string;
  total: Decimal;
  /** Tipos de cambio usados, con su fecha, para mostrarlos junto al total. */
  ratesUsed: { currency: string; rate: Decimal; effectiveDate: string | null }[];
  /** Saldos que no se pudieron convertir por falta de tipo de cambio: se muestran aparte. */
  unconverted: { currency: string; total: Decimal }[];
}

/**
 * Consolida saldos en la moneda principal. Nunca suma monedas distintas
 * directamente: agrupa por moneda, convierte cada grupo y deja aparte
 * las monedas sin tipo de cambio.
 */
export function consolidate(balances: Balance[], baseCurrency: string, rates: ExchangeRate[], on: string): Consolidated {
  const byCurrency = new Map<string, Decimal>();
  for (const b of balances) byCurrency.set(b.currency, (byCurrency.get(b.currency) ?? d(0)).plus(b.amount));

  let total = d(0);
  const ratesUsed: Consolidated["ratesUsed"] = [];
  const unconverted: Consolidated["unconverted"] = [];
  for (const [currency, subtotal] of byCurrency) {
    const found = findRate(rates, currency, baseCurrency, on);
    if (!found) {
      unconverted.push({ currency, total: subtotal });
      continue;
    }
    total = total.plus(convert(subtotal, found.rate));
    if (currency !== baseCurrency) ratesUsed.push({ currency, rate: found.rate, effectiveDate: found.effectiveDate });
  }
  return { currency: baseCurrency, total: round2(total), ratesUsed, unconverted };
}
