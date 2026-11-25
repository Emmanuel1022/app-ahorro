import Decimal from "decimal.js";
import { d, round2, type MoneyInput } from "@/lib/money";

export type BudgetLevel = "ok" | "warning" | "exceeded";

export const BUDGET_WARNING_PCT = 80;
export const BUDGET_LIMIT_PCT = 100;

export interface BudgetStatus {
  budgeted: Decimal;
  spent: Decimal;
  available: Decimal;
  pct: Decimal;
  level: BudgetLevel;
}

export function budgetStatus(budgeted: MoneyInput, spent: MoneyInput): BudgetStatus {
  const b = d(budgeted);
  const s = d(spent);
  // El nivel se decide con el porcentaje exacto: 99,999 % no es "excedido" aunque se muestre 100,00 %.
  const exactPct = b.gt(0) ? s.div(b).times(100) : d(0);
  const pct = exactPct.toDecimalPlaces(2);
  const level: BudgetLevel = exactPct.gte(BUDGET_LIMIT_PCT) ? "exceeded" : exactPct.gte(BUDGET_WARNING_PCT) ? "warning" : "ok";
  return { budgeted: round2(b), spent: round2(s), available: round2(b.minus(s)), pct, level };
}
