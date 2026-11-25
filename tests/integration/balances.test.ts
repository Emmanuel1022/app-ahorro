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

const insertTx = (kind: string, account: string, category: string | null, amount: string, extra = "") =>
  `insert into transactions (kind, direction, account_id, category_id, amount, currency, description${extra ? ", " + extra.split("=")[0] : ""})
   values ('${kind}', ${kind === "income" ? 1 : -1}, '${account}', ${category ? `'${category}'` : "null"}, ${amount}, 'CRC', 'prueba'${extra ? ", " + extra.split("=")[1] : ""}) returning id`;

describe("datos iniciales del usuario", () => {
  it("crea perfil, 19 categorías y 5 métodos de pago", async () => {
    const r = await asUser(admin, user, async (db) => ({
      profile: await db.one("select base_currency, timezone from profiles"),
      cats: await db.one<{ n: string }>("select count(*) as n from categories"),
      methods: await db.one<{ n: string }>("select count(*) as n from payment_methods"),
    }));
    expect(r.profile).toEqual({ base_currency: "CRC", timezone: "America/Costa_Rica" });
    expect(Number(r.cats.n)).toBe(19);
    expect(Number(r.methods.n)).toBe(5);
  });
});

describe("saldos", () => {
  it("ingreso suma, gasto resta, edición recalcula y anulación revierte", async () => {
    await asUser(admin, user, async (db) => {
      expect(await balance(db, ids.crc)).toBe("100000.00");

      await db.q(insertTx("income", ids.crc, ids.salary, "50000"));
      expect(await balance(db, ids.crc)).toBe("150000.00");

      const exp = await db.one<{ id: string }>(insertTx("expense", ids.crc, ids.food, "30000.10"));
      expect(await balance(db, ids.crc)).toBe("119999.90");

      // Editar: se quita el valor anterior (30000.10) y entra el nuevo (45000)
      await db.q("update transactions set amount = 45000 where id = $1", [exp.id]);
      expect(await balance(db, ids.crc)).toBe("105000.00");

      // Anular revierte el efecto
      await db.q("update transactions set status = 'voided', void_reason = 'error' where id = $1", [exp.id]);
      expect(await balance(db, ids.crc)).toBe("150000.00");
      const v = await db.one("select voided_at is not null as has_date from transactions where id = $1", [exp.id]);
      expect(v.has_date).toBe(true);

      // Restaurar vuelve a aplicarlo
      await db.q("update transactions set status = 'active' where id = $1", [exp.id]);
      expect(await balance(db, ids.crc)).toBe("105000.00");

      // Mover el gasto a otra cuenta corrige ambas
      await db.q("update transactions set account_id = $2 where id = $1", [exp.id, ids.crc2]);
      expect(await balance(db, ids.crc)).toBe("150000.00");
      expect(await balance(db, ids.crc2)).toBe("-45000.00"); // negativo permitido: la app advierte
    });
  });

  it("los ajustes corrigen el saldo y exigen motivo", async () => {
    await asUser(admin, user, async (db) => {
      const before = await balance(db, ids.usd);
      await db.q(
        "insert into transactions (kind, direction, account_id, amount, currency, description) values ('adjustment', -1, $1, 0.55, 'USD', 'Cuadre con estado de cuenta')",
        [ids.usd],
      );
      expect(await balance(db, ids.usd)).toBe((Number(before) - 0.55).toFixed(2));
    });
    await expectError(
      asUser(admin, user, (db) =>
        db.q("insert into transactions (kind, direction, account_id, amount, currency) values ('adjustment', 1, $1, 1, 'USD')", [ids.usd]),
      ),
      /transactions_check|check constraint/,
    );
  });

  it("rechaza montos cero o negativos", async () => {
    for (const amount of ["0", "-10"]) {
      await expectError(asUser(admin, user, (db) => db.q(insertTx("expense", ids.crc, ids.food, amount))), /amount_check|check constraint/);
    }
  });

  it("rechaza moneda distinta a la de la cuenta", async () => {
    await expectError(
      asUser(admin, user, (db) =>
        db.q("insert into transactions (kind, direction, account_id, category_id, amount, currency) values ('expense', -1, $1, $2, 10, 'USD')", [ids.crc, ids.food]),
      ),
      /moneda del movimiento/,
    );
  });

  it("rechaza categoría de ingreso en un gasto", async () => {
    await expectError(asUser(admin, user, (db) => db.q(insertTx("expense", ids.crc, ids.salary, "10"))), /no corresponde/);
  });

  it("rechaza signo incoherente con el tipo", async () => {
    await expectError(
      asUser(admin, user, (db) =>
        db.q("insert into transactions (kind, direction, account_id, category_id, amount, currency) values ('expense', 1, $1, $2, 10, 'CRC')", [ids.crc, ids.food]),
      ),
      /check constraint/,
    );
  });

  it("evita duplicados por doble envío con la misma clave", async () => {
    const key = "11111111-1111-4111-8111-111111111111";
    await asUser(admin, user, (db) => db.q(insertTx("expense", ids.crc, ids.food, "100", `idempotency_key='${key}'`)));
    await expectError(
      asUser(admin, user, (db) => db.q(insertTx("expense", ids.crc, ids.food, "100", `idempotency_key='${key}'`))),
      /transactions_idempotency_uq/,
    );
  });

  it("no permite modificar el saldo inicial ni la moneda si hay movimientos", async () => {
    await expectError(
      asUser(admin, user, (db) => db.q("update accounts set opening_balance = 999 where id = $1", [ids.crc])),
      /movimiento de ajuste/,
    );
    await expectError(
      asUser(admin, user, (db) => db.q("update accounts set currency = 'USD' where id = $1", [ids.crc])),
      /movimiento de ajuste/,
    );
  });

  it("calcula el saldo a una fecha", async () => {
    await asUser(admin, user, async (db) => {
      const r = await db.one<{ b: string }>("select account_balance($1, '2000-01-01') as b", [ids.crc]);
      expect(r.b).toBe("100000.00");
    });
  });
});

describe("eliminación con historial", () => {
  it("los movimientos no se borran, se anulan", async () => {
    await expectError(asUser(admin, user, (db) => db.q("delete from transactions where account_id = $1", [ids.crc])), /anúlalo/);
  });

  it("no se elimina una cuenta, banco o categoría con movimientos", async () => {
    await expectError(asUser(admin, user, (db) => db.q("delete from accounts where id = $1", [ids.crc])), /foreign key/);
    await expectError(asUser(admin, user, (db) => db.q("delete from banks where id = $1", [ids.bankId])), /foreign key/);
    await expectError(asUser(admin, user, (db) => db.q("delete from categories where id = $1", [ids.food])), /foreign key/);
  });

  it("sí se elimina una cuenta sin movimientos", async () => {
    await asUser(admin, user, async (db) => {
      const a = await db.one<{ id: string }>(
        "insert into accounts (bank_id, name, currency) values ($1, 'Temporal', 'CRC') returning id",
        [ids.bank2Id],
      );
      await db.q("delete from accounts where id = $1", [a.id]);
    });
  });

  it("no se registran movimientos en cuentas o categorías inactivas", async () => {
    await asUser(admin, user, (db) => db.q("update categories set is_active = false where id = $1", [ids.food]));
    await expectError(asUser(admin, user, (db) => db.q(insertTx("expense", ids.crc, ids.food, "5"))), /categoría está inactiva/);
    await asUser(admin, user, (db) => db.q("update categories set is_active = true where id = $1", [ids.food]));
  });

  it("un banco con cuentas activas no se desactiva", async () => {
    await expectError(asUser(admin, user, (db) => db.q("update banks set is_active = false where id = $1", [ids.bankId])), /Desactiva primero/);
  });

  it("queda historial de cambios y anulaciones", async () => {
    const rows = await asUser(admin, user, (db) =>
      db.q<{ action: string }>("select distinct action from audit_log where table_name = 'transactions' order by action"),
    );
    expect(rows.map((r) => r.action)).toEqual(expect.arrayContaining(["insert", "update", "void", "restore"]));
  });
});
