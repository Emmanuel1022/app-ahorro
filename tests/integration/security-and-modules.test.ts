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
    const vistas = await asUser(admin, bob, (db) => db.q("select * from cuentas where id = $1", [a.crc]));
    expect(vistas).toEqual([]);
    const bancos = await asUser(admin, bob, (db) => db.q("select * from bancos"));
    expect(bancos).toEqual([]);
  });

  it("un usuario no puede registrar movimientos en cuentas ajenas", async () => {
    await expectError(
      asUser(admin, bob, async (db) => {
        const cat = await db.one<{ id: string }>("select id from categorias where nombre = 'Alimentación'");
        await db.q(
          "insert into movimientos (tipo, direccion, cuenta_id, categoria_id, monto, moneda) values ('gasto', -1, $1, $2, 10, 'CRC')",
          [a.crc, cat.id],
        );
      }),
      /foreign key|row-level security/,
    );
  });

  it("un usuario no puede escribir con el usuario_id de otro", async () => {
    await expectError(
      asUser(admin, bob, (db) => db.q("insert into bancos (usuario_id, nombre) values ($1, 'Intruso')", [alice])),
      /row-level security/,
    );
  });

  it("un usuario no puede transferir desde cuentas ajenas", async () => {
    const deBob = await asUser(admin, bob, setupAccounts);
    await expectError(
      asUser(admin, bob, (db) => db.q("select crear_transferencia($1, $2, 10)", [a.crc, deBob.crc])),
      /no encontrada|foreign key|row-level/,
    );
  });

  it("el historial es de solo lectura", async () => {
    await expectError(asUser(admin, alice, (db) => db.q("delete from historial_cambios")), /permission denied/);
  });
});

describe("metas de ahorro", () => {
  it("aportes y retiros no cambian saldos y el avance se calcula", async () => {
    await asUser(admin, alice, async (db) => {
      const antes = await balance(db, a.crc);
      const g = await db.one<{ id: string }>(
        "insert into metas_ahorro (nombre, monto_objetivo, moneda, cuenta_id) values ('Viaje', 200000, 'CRC', $1) returning id",
        [a.crc],
      );
      await db.q("insert into aportes_meta (meta_id, tipo, monto) values ($1, 'aporte', 60000), ($1, 'retiro', 10000)", [g.id]);
      const p = await db.one("select acumulado, porcentaje_avance from v_progreso_metas where meta_id = $1", [g.id]);
      expect(p).toEqual({ acumulado: "50000.00", porcentaje_avance: "25.00" });
      expect(await balance(db, a.crc)).toBe(antes);
    });
  });

  it("un retiro no puede superar lo acumulado", async () => {
    await expectError(
      asUser(admin, alice, async (db) => {
        const g = await db.one<{ id: string }>("select id from metas_ahorro where nombre = 'Viaje'");
        await db.q("insert into aportes_meta (meta_id, tipo, monto) values ($1, 'retiro', 50000.01)", [g.id]);
      }),
      /supera el monto acumulado/,
    );
  });

  it("la meta usa la moneda de su cuenta", async () => {
    await expectError(
      asUser(admin, alice, (db) =>
        db.q("insert into metas_ahorro (nombre, monto_objetivo, moneda, cuenta_id) values ('X', 10, 'USD', $1)", [a.crc]),
      ),
      /moneda de su cuenta/,
    );
  });
});

describe("presupuestos y categorías", () => {
  it("un presupuesto por categoría principal de gasto y mes", async () => {
    await asUser(admin, alice, (db) =>
      db.q("insert into presupuestos (categoria_id, mes, monto, moneda) values ($1, '2026-11-01', 150000, 'CRC')", [a.food]),
    );
    await expectError(
      asUser(admin, alice, (db) =>
        db.q("insert into presupuestos (categoria_id, mes, monto, moneda) values ($1, '2026-11-01', 1, 'CRC')", [a.food]),
      ),
      /duplicate key/,
    );
    await expectError(
      asUser(admin, alice, (db) =>
        db.q("insert into presupuestos (categoria_id, mes, monto, moneda) values ($1, '2026-11-01', 1, 'CRC')", [a.salary]),
      ),
      /categoría de gasto principal/,
    );
    await expectError(
      asUser(admin, alice, (db) =>
        db.q("insert into presupuestos (categoria_id, mes, monto, moneda) values ($1, '2026-11-15', 1, 'CRC')", [a.food]),
      ),
      /mes_check/,
    );
  });

  it("subcategorías: un nivel y mismo tipo", async () => {
    await asUser(admin, alice, (db) =>
      db.q("insert into categorias (padre_id, tipo, nombre) values ($1, 'gasto', 'Supermercado')", [a.food]),
    );
    await expectError(
      asUser(admin, alice, (db) => db.q("insert into categorias (padre_id, tipo, nombre) values ($1, 'ingreso', 'X')", [a.food])),
      /mismo tipo/,
    );
    await expectError(
      asUser(admin, alice, async (db) => {
        const sub = await db.one<{ id: string }>("select id from categorias where nombre = 'Supermercado'");
        await db.q("insert into categorias (padre_id, tipo, nombre) values ($1, 'gasto', 'Nivel 3')", [sub.id]);
      }),
      /no puede tener subcategorías/,
    );
  });
});

describe("recurrentes", () => {
  it("no se genera dos veces la misma ocurrencia", async () => {
    const regla = await asUser(admin, alice, (db) =>
      db.one<{ id: string }>(
        `insert into reglas_recurrentes (tipo, cuenta_id, categoria_id, monto, descripcion, frecuencia, fecha_inicio, proxima_fecha)
         values ('ingreso', $1, $2, 850000, 'Salario', 'quincenal', '2026-11-15', '2026-11-15') returning id`,
        [a.crc, a.salary],
      ),
    );
    await asUser(admin, alice, (db) => db.q("insert into ocurrencias_recurrentes (regla_id, fecha_programada) values ($1, '2026-11-15')", [regla.id]));
    await expectError(
      asUser(admin, alice, (db) => db.q("insert into ocurrencias_recurrentes (regla_id, fecha_programada) values ($1, '2026-11-15')", [regla.id])),
      /duplicate key/,
    );
  });

  it("la categoría de la regla corresponde a su tipo", async () => {
    await expectError(
      asUser(admin, alice, (db) =>
        db.q(
          `insert into reglas_recurrentes (tipo, cuenta_id, categoria_id, monto, descripcion, frecuencia, fecha_inicio, proxima_fecha)
           values ('gasto', $1, $2, 1, 'X', 'mensual', '2026-11-01', '2026-11-01')`,
          [a.crc, a.salary],
        ),
      ),
      /no corresponde/,
    );
  });
});
