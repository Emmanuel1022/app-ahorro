import { describe, expect, it } from "vitest";
import { budgetStatus } from "@/server/services/budget";

describe("presupuestos", () => {
  it.each([
    ["100000", "50000", "ok", "50.00", "50000.00"],
    ["100000", "80000", "warning", "80.00", "20000.00"],
    ["100000", "99999.99", "warning", "100.00", "0.01"],
    ["100000", "100000", "exceeded", "100.00", "0.00"],
    ["100000", "125000", "exceeded", "125.00", "-25000.00"],
  ])("presupuesto %s, gastado %s → %s", (b, s, level, pct, available) => {
    const r = budgetStatus(b, s);
    expect(r.level).toBe(level);
    expect(r.pct.toFixed(2)).toBe(pct);
    expect(r.available.toFixed(2)).toBe(available);
  });
});
