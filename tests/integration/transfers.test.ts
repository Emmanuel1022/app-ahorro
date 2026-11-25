import { afterAll, beforeAll, describe, expect, it } from "vitest";
import type { Client } from "pg";
import { asUser, balance, connect, createUser, expectError, setupAccounts } from "./helpers";

let admin: Client;
let user: string;
let ids: Awaited<ReturnType<typeof setupAccounts>>;

beforeAll(async () => {
  admin = await connect();
  user = await createUser(admin);
  ids = await asUser(admin, user, setupAccounts);
});
afterAll(() => admin.end());

describe("transferencias", () => {
  it("misma moneda con comisión: descuenta origen, suma destino y la comisión es gasto", async () => {
    await asUser(admin, user, async (db) => {
      const t = await db.one<{ id: string }>(
        "select create_transfer($1, $2, 20000, now(), 'Ahorro mensual', null, null, 500) as id",
        [ids.crc, ids.crc2],
      );
      expect(await balance(db, ids.crc)).toBe("79500.00");
      expect(await balance(db, ids.crc2)).toBe("20000.00");

      const parts = await db.q<{ kind: string; amount: string; category: string | null }>(
        `select t.kind, t.amount, c.system_key as category from transactions t left join categories c on c.id = t.category_id
         where transfer_id = $1 order by kind`,
        [t.id],
      );
      expect(parts).toEqual([
        { kind: "expense", amount: "500.00", category: "bank_fees" },
        { kind: "transfer_out", amount: "20000.00", category: null },
        { kind: "transfer_in", amount: "20000.00", category: null },
      ]);

      // En los reportes solo cuenta la comisión como gasto; la transferencia no es ingreso ni gasto
      const s = await db.q<{ income: string; expense: string }>("select income, expense from v_monthly_summary where currency = 'CRC'");
      expect(s).toEqual([{ income: "0", expense: "500.00" }]);
    });
  });

  it("monedas distintas con tipo de cambio: conserva ambos montos", async () => {
    await asUser(admin, user, async (db) => {
      // USD → CRC a 520
      const t = await db.one<{ id: string }>("select create_transfer($1, $2, 100, now(), null, null, 520) as id", [ids.usd, ids.crc2]);
      const tr = await db.one("select amount_sent, amount_received, exchange_rate from transfers where id = $1", [t.id]);
      expect(tr).toEqual({ amount_sent: "100.00", amount_received: "52000.00", exchange_rate: "520.000000" });
      expect(await balance(db, ids.usd)).toBe("900.00");
      expect(await balance(db, ids.crc2)).toBe("72000.00");

      // CRC → USD indicando el monto recibido: calcula la tasa
      const t2 = await db.one<{ id: string }>("select create_transfer($1, $2, 26000, now(), null, 50) as id", [ids.crc2, ids.usd]);
      const tr2 = await db.one("select amount_received, exchange_rate from transfers where id = $1", [t2.id]);
      expect(tr2).toEqual({ amount_received: "50.00", exchange_rate: "0.001923" });
      expect(await balance(db, ids.usd)).toBe("950.00");
    });
  });

  it("exige tipo de cambio entre monedas distintas", async () => {
    await expectError(
      asUser(admin, user, (db) => db.q("select create_transfer($1, $2, 10)", [ids.usd, ids.crc])),
      /monedas distintas/,
    );
  });

  it("rechaza origen igual a destino y montos inválidos", async () => {
    await expectError(asUser(admin, user, (db) => db.q("select create_transfer($1, $1, 10)", [ids.crc])), /distintas/);
    await expectError(asUser(admin, user, (db) => db.q("select create_transfer($1, $2, 0)", [ids.crc, ids.crc2])), /mayor que cero/);
  });

  it("es atómica: si falla una parte no queda nada guardado", async () => {
    const count = () =>
      asUser(admin, user, async (db) => ({
        transfers: (await db.one<{ n: string }>("select count(*) n from transfers")).n,
        txs: (await db.one<{ n: string }>("select count(*) n from transactions")).n,
      }));
    const before = await count();
    // Simula una falla justo al registrar la entrada en la cuenta destino
    await admin.query(`create function test_fail() returns trigger language plpgsql as $$
      begin if new.kind = 'transfer_in' then raise exception 'falla simulada'; end if; return new; end $$`);
    await admin.query("create trigger test_fail before insert on transactions for each row execute function test_fail()");
    try {
      await expectError(
        asUser(admin, user, (db) => db.q("select create_transfer($1, $2, 1000)", [ids.crc, ids.crc2])),
        /falla simulada/,
      );
    } finally {
      await admin.query("drop trigger test_fail on transactions; drop function test_fail()");
    }
    expect(await count()).toEqual(before);
  });

  it("las piezas no se editan sueltas; editar la transferencia actualiza todo", async () => {
    const t = await asUser(admin, user, (db) =>
      db.one<{ id: string }>("select create_transfer($1, $2, 10000, now(), 'x', null, null, 0) as id", [ids.crc, ids.crc2]),
    );
    await expectError(
      asUser(admin, user, (db) => db.q("update transactions set amount = 1 where transfer_id = $1", [t.id])),
      /desde la transferencia/,
    );

    await asUser(admin, user, async (db) => {
      const crcBefore = Number(await balance(db, ids.crc));
      const crc2Before = Number(await balance(db, ids.crc2));
      await db.q("select update_transfer($1, 12000, now(), 'corregida', null, null, 300)", [t.id]);
      expect(Number(await balance(db, ids.crc))).toBe(crcBefore - 2000 - 300);
      expect(Number(await balance(db, ids.crc2))).toBe(crc2Before + 2000);

      // Quitar la comisión la anula
      await db.q("select update_transfer($1, 12000, now(), 'corregida', null, null, 0)", [t.id]);
      expect(Number(await balance(db, ids.crc))).toBe(crcBefore - 2000);

      // Anular revierte todas las piezas
      await db.q("select void_transfer($1, 'duplicada')", [t.id]);
      expect(Number(await balance(db, ids.crc))).toBe(crcBefore + 10000);
      expect(Number(await balance(db, ids.crc2))).toBe(crc2Before - 10000);
    });
  });

  it("una clave de idempotencia repetida devuelve la misma transferencia", async () => {
    const key = "22222222-2222-4222-8222-222222222222";
    const [a, b] = await asUser(admin, user, async (db) => [
      await db.one<{ id: string }>("select create_transfer($1, $2, 1, now(), null, null, null, 0, $3) as id", [ids.crc, ids.crc2, key]),
      await db.one<{ id: string }>("select create_transfer($1, $2, 1, now(), null, null, null, 0, $3) as id", [ids.crc, ids.crc2, key]),
    ]);
    expect(a.id).toBe(b.id);
  });
});

describe("tipo de cambio de referencia (SQL)", () => {
  it("usa el más reciente vigente y la tasa inversa", async () => {
    await asUser(admin, user, async (db) => {
      await db.q(`insert into exchange_rates (base_currency, quote_currency, rate, effective_date) values
        ('USD', 'CRC', 510, '2026-11-01'), ('USD', 'CRC', 520, '2026-11-20')`);
      const direct = await db.one("select rate, effective_date::text from fx_rate('USD', 'CRC', '2026-11-25')");
      expect(direct).toEqual({ rate: "520.000000", effective_date: "2026-11-20" });
      const old = await db.one("select rate from fx_rate('USD', 'CRC', '2026-11-10')");
      expect(old.rate).toBe("510.000000");
      const inverse = await db.one<{ r: string }>("select round(rate * 520, 6) as r from fx_rate('CRC', 'USD', '2026-11-25')");
      expect(inverse.r).toBe("1.000000");
      const none = await db.q("select * from fx_rate('EUR', 'CRC', '2026-11-25')");
      expect(none).toEqual([]);
    });
  });
});
