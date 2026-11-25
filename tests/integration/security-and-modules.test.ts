import { afterAll, beforeAll, describe, expect, it } from "vitest";
import type { Client } from "pg";
import { asUser, balance, connect, createUser, expectError, setupAccounts } from "./helpers";

let admin: Client;
let alice: string;
let bob: string;
let a: Awaited<ReturnType<typeof setupAccounts>>;

beforeAll(async () => {
  admin = await connect();
  alice = await createUser(admin);
  bob = await createUser(admin);
  a = await asUser(admin, alice, setupAccounts);
});
afterAll(() => admin.end());

describe("separación por usuario (RLS)", () => {
  it("un usuario no ve datos de otro", async () => {
    const seen = await asUser(admin, bob, (db) => db.q("select * from accounts where id = $1", [a.crc]));
    expect(seen).toEqual([]);
    const banks = await asUser(admin, bob, (db) => db.q("select * from banks"));
    expect(banks).toEqual([]);
  });

  it("un usuario no puede registrar movimientos en cuentas ajenas", async () => {
    await expectError(
      asUser(admin, bob, async (db) => {
        const cat = await db.one<{ id: string }>("select id from categories where name = 'Alimentación'");
        await db.q(
          "insert into transactions (kind, direction, account_id, category_id, amount, currency) values ('expense', -1, $1, $2, 10, 'CRC')",
          [a.crc, cat.id],
        );
      }),
      /foreign key|row-level security/,
    );
  });

  it("un usuario no puede escribir con el user_id de otro", async () => {
    await expectError(
      asUser(admin, bob, (db) => db.q("insert into banks (user_id, name) values ($1, 'Intruso')", [alice])),
      /row-level security/,
    );
  });

  it("un usuario no puede transferir desde cuentas ajenas", async () => {
    const bobIds = await asUser(admin, bob, setupAccounts);
    await expectError(
      asUser(admin, bob, (db) => db.q("select create_transfer($1, $2, 10)", [a.crc, bobIds.crc])),
      /no encontrada|foreign key|row-level/,
    );
  });

  it("el historial es de solo lectura", async () => {
    await expectError(asUser(admin, alice, (db) => db.q("delete from audit_log")), /permission denied/);
  });
});

describe("metas de ahorro", () => {
  it("aportes y retiros no cambian saldos y el avance se calcula", async () => {
    await asUser(admin, alice, async (db) => {
      const before = await balance(db, a.crc);
      const g = await db.one<{ id: string }>(
        "insert into savings_goals (name, target_amount, currency, account_id) values ('Viaje', 200000, 'CRC', $1) returning id",
        [a.crc],
      );
      await db.q("insert into goal_entries (goal_id, kind, amount) values ($1, 'contribution', 60000), ($1, 'withdrawal', 10000)", [g.id]);
      const p = await db.one("select accumulated, progress_pct from v_goal_progress where goal_id = $1", [g.id]);
      expect(p).toEqual({ accumulated: "50000.00", progress_pct: "25.00" });
      expect(await balance(db, a.crc)).toBe(before);
    });
  });

  it("un retiro no puede superar lo acumulado", async () => {
    await expectError(
      asUser(admin, alice, async (db) => {
        const g = await db.one<{ id: string }>("select id from savings_goals where name = 'Viaje'");
        await db.q("insert into goal_entries (goal_id, kind, amount) values ($1, 'withdrawal', 50000.01)", [g.id]);
      }),
      /supera el monto acumulado/,
    );
  });

  it("la meta usa la moneda de su cuenta", async () => {
    await expectError(
      asUser(admin, alice, (db) =>
        db.q("insert into savings_goals (name, target_amount, currency, account_id) values ('X', 10, 'USD', $1)", [a.crc]),
      ),
      /moneda de su cuenta/,
    );
  });
});

describe("presupuestos y categorías", () => {
  it("un presupuesto por categoría principal de gasto y mes", async () => {
    await asUser(admin, alice, (db) =>
      db.q("insert into budgets (category_id, month, amount, currency) values ($1, '2026-11-01', 150000, 'CRC')", [a.food]),
    );
    await expectError(
      asUser(admin, alice, (db) =>
        db.q("insert into budgets (category_id, month, amount, currency) values ($1, '2026-11-01', 1, 'CRC')", [a.food]),
      ),
      /duplicate key/,
    );
    await expectError(
      asUser(admin, alice, (db) =>
        db.q("insert into budgets (category_id, month, amount, currency) values ($1, '2026-11-01', 1, 'CRC')", [a.salary]),
      ),
      /categoría de gasto principal/,
    );
    await expectError(
      asUser(admin, alice, (db) =>
        db.q("insert into budgets (category_id, month, amount, currency) values ($1, '2026-11-15', 1, 'CRC')", [a.food]),
      ),
      /month_check/,
    );
  });

  it("subcategorías: un nivel y mismo tipo", async () => {
    await asUser(admin, alice, (db) =>
      db.q("insert into categories (parent_id, type, name) values ($1, 'expense', 'Supermercado')", [a.food]),
    );
    await expectError(
      asUser(admin, alice, (db) => db.q("insert into categories (parent_id, type, name) values ($1, 'income', 'X')", [a.food])),
      /mismo tipo/,
    );
    await expectError(
      asUser(admin, alice, async (db) => {
        const sub = await db.one<{ id: string }>("select id from categories where name = 'Supermercado'");
        await db.q("insert into categories (parent_id, type, name) values ($1, 'expense', 'Nivel 3')", [sub.id]);
      }),
      /no puede tener subcategorías/,
    );
  });
});

describe("recurrentes", () => {
  it("no se genera dos veces la misma ocurrencia", async () => {
    const rule = await asUser(admin, alice, (db) =>
      db.one<{ id: string }>(
        `insert into recurring_rules (kind, account_id, category_id, amount, description, frequency, start_date, next_due_date)
         values ('income', $1, $2, 850000, 'Salario', 'biweekly', '2026-11-15', '2026-11-15') returning id`,
        [a.crc, a.salary],
      ),
    );
    await asUser(admin, alice, (db) => db.q("insert into recurring_occurrences (rule_id, due_date) values ($1, '2026-11-15')", [rule.id]));
    await expectError(
      asUser(admin, alice, (db) => db.q("insert into recurring_occurrences (rule_id, due_date) values ($1, '2026-11-15')", [rule.id])),
      /duplicate key/,
    );
  });

  it("la categoría de la regla corresponde a su tipo", async () => {
    await expectError(
      asUser(admin, alice, (db) =>
        db.q(
          `insert into recurring_rules (kind, account_id, category_id, amount, description, frequency, start_date, next_due_date)
           values ('expense', $1, $2, 1, 'X', 'monthly', '2026-11-01', '2026-11-01')`,
          [a.crc, a.salary],
        ),
      ),
      /no corresponde/,
    );
  });
});
