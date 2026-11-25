import { describe, expect, it } from "vitest";
import { consolidate, convert, findRate, type ExchangeRate } from "@/server/services/fx";

const rates: ExchangeRate[] = [
  { from: "USD", to: "CRC", rate: "510.00", effectiveDate: "2026-11-01" },
  { from: "USD", to: "CRC", rate: "520.00", effectiveDate: "2026-11-20" },
  { from: "EUR", to: "USD", rate: "1.08", effectiveDate: "2026-11-20" },
];

describe("tipos de cambio", () => {
  it("usa el tipo más reciente vigente a la fecha", () => {
    expect(findRate(rates, "USD", "CRC", "2026-11-25")?.rate.toString()).toBe("520");
    expect(findRate(rates, "USD", "CRC", "2026-11-10")?.rate.toString()).toBe("510");
    expect(findRate(rates, "USD", "CRC", "2026-10-31")).toBeNull();
  });

  it("acepta la tasa inversa", () => {
    const r = findRate(rates, "CRC", "USD", "2026-11-25");
    expect(convert("260000", r!.rate).toFixed(2)).toBe("500.00");
  });

  it("misma moneda = tasa 1", () => {
    expect(findRate(rates, "CRC", "CRC", "2026-11-25")?.rate.toString()).toBe("1");
  });

  it("consolida sin sumar monedas distintas directamente", () => {
    const res = consolidate(
      [
        { amount: "100000.00", currency: "CRC" },
        { amount: "500.00", currency: "USD" },
        { amount: "50.10", currency: "USD" },
        { amount: "10.00", currency: "EUR" }, // EUR→CRC no existe: queda aparte
      ],
      "CRC",
      rates,
      "2026-11-25",
    );
    expect(res.total.toFixed(2)).toBe("386052.00"); // 100000 + 550.10 × 520
    expect(res.ratesUsed).toEqual([{ currency: "USD", rate: expect.anything(), effectiveDate: "2026-11-20" }]);
    expect(res.unconverted.map((u) => [u.currency, u.total.toFixed(2)])).toEqual([["EUR", "10.00"]]);
  });
});
