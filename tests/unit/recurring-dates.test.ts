import { describe, expect, it } from "vitest";
import { dueDatesBetween, firstDueDate, nextDueDate } from "@/server/services/recurring-dates";

describe("fechas recurrentes", () => {
  it("semanal suma 7 días, cruzando meses", () => {
    expect(nextDueDate("2026-11-28", "semanal", "2026-11-28")).toBe("2026-12-05");
  });

  it("quincenal: 15 y último día del mes", () => {
    expect(dueDatesBetween("2026-01-15", "2026-03-31", "quincenal", "2026-01-15")).toEqual([
      "2026-01-15", "2026-01-31", "2026-02-15", "2026-02-28", "2026-03-15", "2026-03-31",
    ]);
    expect(firstDueDate("2026-01-03", "quincenal")).toBe("2026-01-15");
    expect(firstDueDate("2026-01-20", "quincenal")).toBe("2026-01-31");
  });

  it("mensual el día 31 cae el último día en meses cortos y vuelve al 31", () => {
    expect(dueDatesBetween("2026-01-31", "2026-05-31", "mensual", "2026-01-31")).toEqual([
      "2026-01-31", "2026-02-28", "2026-03-31", "2026-04-30", "2026-05-31",
    ]);
  });

  it("anual el 29 de febrero", () => {
    expect(nextDueDate("2028-02-29", "anual", "2028-02-29")).toBe("2029-02-28");
    expect(nextDueDate("2029-02-28", "anual", "2028-02-29")).toBe("2030-02-28");
    expect(nextDueDate("2031-02-28", "anual", "2028-02-29")).toBe("2032-02-29");
  });

  it("respeta la fecha de fin", () => {
    expect(dueDatesBetween("2026-01-01", "2026-12-31", "mensual", "2026-01-01", "2026-03-15")).toEqual([
      "2026-01-01", "2026-02-01", "2026-03-01",
    ]);
  });
});
