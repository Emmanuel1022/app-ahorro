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

/** SQL para insertar un ingreso o gasto en colones. */
const insertarMov = (tipo: "ingreso" | "gasto", cuenta: string, categoria: string | null, monto: string, clave?: string) =>
  `insert into movimientos (tipo, direccion, cuenta_id, categoria_id, monto, moneda, descripcion${clave ? ", clave_idempotencia" : ""})
   values ('${tipo}', ${tipo === "ingreso" ? 1 : -1}, '${cuenta}', ${categoria ? `'${categoria}'` : "null"}, ${monto}, 'CRC', 'prueba'${clave ? `, '${clave}'` : ""}) returning id`;

describe("datos iniciales del usuario", () => {
  it("crea perfil, 19 categorías y 5 métodos de pago", async () => {
    const r = await asUser(admin, user, async (db) => ({
      perfil: await db.one("select moneda_principal, zona_horaria from perfiles"),
      categorias: await db.one<{ n: string }>("select count(*) as n from categorias"),
      metodos: await db.one<{ n: string }>("select count(*) as n from metodos_pago"),
    }));
    expect(r.perfil).toEqual({ moneda_principal: "CRC", zona_horaria: "America/Costa_Rica" });
    expect(Number(r.categorias.n)).toBe(19);
    expect(Number(r.metodos.n)).toBe(5);
  });
});

describe("saldos", () => {
  it("ingreso suma, gasto resta, edición recalcula y anulación revierte", async () => {
    await asUser(admin, user, async (db) => {
      expect(await balance(db, ids.crc)).toBe("100000.00");

      await db.q(insertarMov("ingreso", ids.crc, ids.salary, "50000"));
      expect(await balance(db, ids.crc)).toBe("150000.00");

      const gasto = await db.one<{ id: string }>(insertarMov("gasto", ids.crc, ids.food, "30000.10"));
      expect(await balance(db, ids.crc)).toBe("119999.90");

      // Editar: se quita el valor anterior (30000.10) y entra el nuevo (45000)
      await db.q("update movimientos set monto = 45000 where id = $1", [gasto.id]);
      expect(await balance(db, ids.crc)).toBe("105000.00");

      // Anular revierte el efecto
      await db.q("update movimientos set estado = 'anulado', motivo_anulacion = 'error' where id = $1", [gasto.id]);
      expect(await balance(db, ids.crc)).toBe("150000.00");
      const v = await db.one("select anulado_en is not null as tiene_fecha from movimientos where id = $1", [gasto.id]);
      expect(v.tiene_fecha).toBe(true);

      // Restaurar vuelve a aplicarlo
      await db.q("update movimientos set estado = 'activo' where id = $1", [gasto.id]);
      expect(await balance(db, ids.crc)).toBe("105000.00");

      // Mover el gasto a otra cuenta corrige ambas
      await db.q("update movimientos set cuenta_id = $2 where id = $1", [gasto.id, ids.crc2]);
      expect(await balance(db, ids.crc)).toBe("150000.00");
      expect(await balance(db, ids.crc2)).toBe("-45000.00"); // negativo permitido: la app advierte
    });
  });

  it("los ajustes corrigen el saldo y exigen motivo", async () => {
    await asUser(admin, user, async (db) => {
      const antes = await balance(db, ids.usd);
      await db.q(
        "insert into movimientos (tipo, direccion, cuenta_id, monto, moneda, descripcion) values ('ajuste', -1, $1, 0.55, 'USD', 'Cuadre con estado de cuenta')",
        [ids.usd],
      );
      expect(await balance(db, ids.usd)).toBe((Number(antes) - 0.55).toFixed(2));
    });
    await expectError(
      asUser(admin, user, (db) =>
        db.q("insert into movimientos (tipo, direccion, cuenta_id, monto, moneda) values ('ajuste', 1, $1, 1, 'USD')", [ids.usd]),
      ),
      /movimientos_check|check constraint/,
    );
  });

  it("rechaza montos cero o negativos", async () => {
    for (const monto of ["0", "-10"]) {
      await expectError(asUser(admin, user, (db) => db.q(insertarMov("gasto", ids.crc, ids.food, monto))), /monto_check|check constraint/);
    }
  });

  it("rechaza moneda distinta a la de la cuenta", async () => {
    await expectError(
      asUser(admin, user, (db) =>
        db.q("insert into movimientos (tipo, direccion, cuenta_id, categoria_id, monto, moneda) values ('gasto', -1, $1, $2, 10, 'USD')", [ids.crc, ids.food]),
      ),
      /moneda del movimiento/,
    );
  });

  it("rechaza categoría de ingreso en un gasto", async () => {
    await expectError(asUser(admin, user, (db) => db.q(insertarMov("gasto", ids.crc, ids.salary, "10"))), /no corresponde/);
  });

  it("rechaza signo incoherente con el tipo", async () => {
    await expectError(
      asUser(admin, user, (db) =>
        db.q("insert into movimientos (tipo, direccion, cuenta_id, categoria_id, monto, moneda) values ('gasto', 1, $1, $2, 10, 'CRC')", [ids.crc, ids.food]),
      ),
      /check constraint/,
    );
  });

  it("evita duplicados por doble envío con la misma clave", async () => {
    const clave = "11111111-1111-4111-8111-111111111111";
    await asUser(admin, user, (db) => db.q(insertarMov("gasto", ids.crc, ids.food, "100", clave)));
    await expectError(
      asUser(admin, user, (db) => db.q(insertarMov("gasto", ids.crc, ids.food, "100", clave))),
      /movimientos_idempotencia_uq/,
    );
  });

  it("no permite modificar el saldo inicial ni la moneda si hay movimientos", async () => {
    await expectError(
      asUser(admin, user, (db) => db.q("update cuentas set saldo_inicial = 999 where id = $1", [ids.crc])),
      /movimiento de ajuste/,
    );
    await expectError(
      asUser(admin, user, (db) => db.q("update cuentas set moneda = 'USD' where id = $1", [ids.crc])),
      /movimiento de ajuste/,
    );
  });

  it("calcula el saldo a una fecha", async () => {
    await asUser(admin, user, async (db) => {
      const r = await db.one<{ s: string }>("select saldo_cuenta($1, '2000-01-01') as s", [ids.crc]);
      expect(r.s).toBe("100000.00");
    });
  });
});

describe("eliminación con historial", () => {
  it("los movimientos no se borran, se anulan", async () => {
    await expectError(asUser(admin, user, (db) => db.q("delete from movimientos where cuenta_id = $1", [ids.crc])), /anúlalo/);
  });

  it("no se elimina una cuenta, banco o categoría con movimientos", async () => {
    await expectError(asUser(admin, user, (db) => db.q("delete from cuentas where id = $1", [ids.crc])), /foreign key/);
    await expectError(asUser(admin, user, (db) => db.q("delete from bancos where id = $1", [ids.bankId])), /foreign key/);
    await expectError(asUser(admin, user, (db) => db.q("delete from categorias where id = $1", [ids.food])), /foreign key/);
  });

  it("sí se elimina una cuenta sin movimientos", async () => {
    await asUser(admin, user, async (db) => {
      const c = await db.one<{ id: string }>(
        "insert into cuentas (banco_id, nombre, moneda) values ($1, 'Temporal', 'CRC') returning id",
        [ids.bank2Id],
      );
      await db.q("delete from cuentas where id = $1", [c.id]);
    });
  });

  it("no se registran movimientos en cuentas o categorías inactivas", async () => {
    await asUser(admin, user, (db) => db.q("update categorias set activa = false where id = $1", [ids.food]));
    await expectError(asUser(admin, user, (db) => db.q(insertarMov("gasto", ids.crc, ids.food, "5"))), /categoría está inactiva/);
    await asUser(admin, user, (db) => db.q("update categorias set activa = true where id = $1", [ids.food]));
  });

  it("un banco con cuentas activas no se desactiva", async () => {
    await expectError(asUser(admin, user, (db) => db.q("update bancos set activo = false where id = $1", [ids.bankId])), /Desactiva primero/);
  });

  it("queda historial de cambios y anulaciones", async () => {
    const filas = await asUser(admin, user, (db) =>
      db.q<{ accion: string }>("select distinct accion from historial_cambios where tabla = 'movimientos' order by accion"),
    );
    expect(filas.map((r) => r.accion)).toEqual(expect.arrayContaining(["crear", "editar", "anular", "restaurar"]));
  });
});
