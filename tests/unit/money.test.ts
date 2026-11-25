import { describe, expect, it } from "vitest";
import { d, formatMoney, parseAmount, round2, sum, toDbAmount } from "@/lib/money";

describe("money", () => {
  it("suma sin errores de punto flotante", () => {
    expect(sum(["0.1", "0.2"]).toString()).toBe("0.3");
    expect(sum(Array(10).fill("0.10")).toFixed(2)).toBe("1.00");
  });

  it("redondea a 2 decimales hacia arriba en el medio", () => {
    expect(round2("2.345").toFixed(2)).toBe("2.35");
    expect(round2("2.344").toFixed(2)).toBe("2.34");
    expect(toDbAmount("1000")).toBe("1000.00");
  });

  it.each([
    ["1234.5", "1234.5"],
    ["1,234.50", "1234.5"],
    ["1.234,50", "1234.5"],
    ["₡ 25 000", "25000"],
    ["25,5", "25.5"],
    ["1.000.000", "1000000"],
    ["$12", "12"],
  ])("interpreta %s", (raw, expected) => {
    expect(parseAmount(raw)?.toString()).toBe(expected);
  });

  it.each(["0", "-5", "abc", "", "1.234"])("rechaza %s como monto inválido o ambiguo", (raw) => {
    // "1.234" se toma como 1.234 (3 decimales) y no es válido
    expect(parseAmount(raw)).toBeNull();
  });

  it("formatea en colones y dólares, y oculta en modo privacidad", () => {
    expect(formatMoney("1234.5", "CRC")).toMatch(/1.?234,50/);
    expect(formatMoney("10", "USD")).toMatch(/10,00/);
    expect(formatMoney("10", "USD", { hidden: true })).toBe("••••••");
    expect(d("1").toString()).toBe("1");
  });
});
