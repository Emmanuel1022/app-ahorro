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
        "select crear_transferencia($1, $2, 20000, now(), 'Ahorro mensual', null, null, 500) as id",
        [ids.crc, ids.crc2],
      );
      expect(await balance(db, ids.crc)).toBe("79500.00");
      expect(await balance(db, ids.crc2)).toBe("20000.00");

      const piezas = await db.q<{ tipo: string; monto: string; categoria: string | null }>(
        `select m.tipo, m.monto, c.clave_sistema as categoria from movimientos m left join categorias c on c.id = m.categoria_id
         where transferencia_id = $1 order by m.tipo`,
        [t.id],
      );
      expect(piezas).toEqual([
        { tipo: "gasto", monto: "500.00", categoria: "comisiones_bancarias" },
        { tipo: "transferencia_salida", monto: "20000.00", categoria: null },
        { tipo: "transferencia_entrada", monto: "20000.00", categoria: null },
      ]);

      // En los reportes solo cuenta la comisión como gasto; la transferencia no es ingreso ni gasto
      const s = await db.q<{ ingresos: string; gastos: string }>("select ingresos, gastos from v_resumen_mensual where moneda = 'CRC'");
      expect(s).toEqual([{ ingresos: "0", gastos: "500.00" }]);
    });
  });

  it("monedas distintas con tipo de cambio: conserva ambos montos", async () => {
    await asUser(admin, user, async (db) => {
      // USD → CRC a 520
      const t = await db.one<{ id: string }>("select crear_transferencia($1, $2, 100, now(), null, null, 520) as id", [ids.usd, ids.crc2]);
      const tr = await db.one("select monto_enviado, monto_recibido, tipo_cambio from transferencias where id = $1", [t.id]);
      expect(tr).toEqual({ monto_enviado: "100.00", monto_recibido: "52000.00", tipo_cambio: "520.000000" });
      expect(await balance(db, ids.usd)).toBe("900.00");
      expect(await balance(db, ids.crc2)).toBe("72000.00");

      // CRC → USD indicando el monto recibido: calcula la tasa
      const t2 = await db.one<{ id: string }>("select crear_transferencia($1, $2, 26000, now(), null, 50) as id", [ids.crc2, ids.usd]);
      const tr2 = await db.one("select monto_recibido, tipo_cambio from transferencias where id = $1", [t2.id]);
      expect(tr2).toEqual({ monto_recibido: "50.00", tipo_cambio: "0.001923" });
      expect(await balance(db, ids.usd)).toBe("950.00");
    });
  });

  it("exige tipo de cambio entre monedas distintas", async () => {
    await expectError(
      asUser(admin, user, (db) => db.q("select crear_transferencia($1, $2, 10)", [ids.usd, ids.crc])),
      /monedas distintas/,
    );
  });

  it("rechaza origen igual a destino y montos inválidos", async () => {
    await expectError(asUser(admin, user, (db) => db.q("select crear_transferencia($1, $1, 10)", [ids.crc])), /distintas/);
    await expectError(asUser(admin, user, (db) => db.q("select crear_transferencia($1, $2, 0)", [ids.crc, ids.crc2])), /mayor que cero/);
  });

  it("es atómica: si falla una parte no queda nada guardado", async () => {
    const contar = () =>
      asUser(admin, user, async (db) => ({
        transferencias: (await db.one<{ n: string }>("select count(*) n from transferencias")).n,
        movimientos: (await db.one<{ n: string }>("select count(*) n from movimientos")).n,
      }));
    const antes = await contar();
    // Simula una falla justo al registrar la entrada en la cuenta destino
    await admin.query(`create function prueba_falla() returns trigger language plpgsql as $$
      begin if new.tipo = 'transferencia_entrada' then raise exception 'falla simulada'; end if; return new; end $$`);
    await admin.query("create trigger prueba_falla before insert on movimientos for each row execute function prueba_falla()");
    try {
      await expectError(
        asUser(admin, user, (db) => db.q("select crear_transferencia($1, $2, 1000)", [ids.crc, ids.crc2])),
        /falla simulada/,
      );
    } finally {
      await admin.query("drop trigger prueba_falla on movimientos; drop function prueba_falla()");
    }
    expect(await contar()).toEqual(antes);
  });

  it("las piezas no se editan sueltas; editar la transferencia actualiza todo", async () => {
    const t = await asUser(admin, user, (db) =>
      db.one<{ id: string }>("select crear_transferencia($1, $2, 10000, now(), 'x', null, null, 0) as id", [ids.crc, ids.crc2]),
    );
    await expectError(
      asUser(admin, user, (db) => db.q("update movimientos set monto = 1 where transferencia_id = $1", [t.id])),
      /desde la transferencia/,
    );

    await asUser(admin, user, async (db) => {
      const crcAntes = Number(await balance(db, ids.crc));
      const crc2Antes = Number(await balance(db, ids.crc2));
      await db.q("select actualizar_transferencia($1, 12000, now(), 'corregida', null, null, 300)", [t.id]);
      expect(Number(await balance(db, ids.crc))).toBe(crcAntes - 2000 - 300);
      expect(Number(await balance(db, ids.crc2))).toBe(crc2Antes + 2000);

      // Quitar la comisión la anula
      await db.q("select actualizar_transferencia($1, 12000, now(), 'corregida', null, null, 0)", [t.id]);
      expect(Number(await balance(db, ids.crc))).toBe(crcAntes - 2000);

      // Anular revierte todas las piezas
      await db.q("select anular_transferencia($1, 'duplicada')", [t.id]);
      expect(Number(await balance(db, ids.crc))).toBe(crcAntes + 10000);
      expect(Number(await balance(db, ids.crc2))).toBe(crc2Antes - 10000);
    });
  });

  it("una clave de idempotencia repetida devuelve la misma transferencia", async () => {
    const clave = "22222222-2222-4222-8222-222222222222";
    const [a, b] = await asUser(admin, user, async (db) => [
      await db.one<{ id: string }>("select crear_transferencia($1, $2, 1, now(), null, null, null, 0, $3) as id", [ids.crc, ids.crc2, clave]),
      await db.one<{ id: string }>("select crear_transferencia($1, $2, 1, now(), null, null, null, 0, $3) as id", [ids.crc, ids.crc2, clave]),
    ]);
    expect(a.id).toBe(b.id);
  });
});

describe("tipo de cambio de referencia (SQL)", () => {
  it("usa el más reciente vigente y la tasa inversa", async () => {
    await asUser(admin, user, async (db) => {
      await db.q(`insert into tipos_cambio (moneda_origen, moneda_destino, tasa, fecha_vigencia) values
        ('USD', 'CRC', 510, '2026-11-01'), ('USD', 'CRC', 520, '2026-11-20')`);
      const directa = await db.one("select tasa, fecha_vigencia::text from tipo_cambio_referencia('USD', 'CRC', '2026-11-25')");
      expect(directa).toEqual({ tasa: "520.000000", fecha_vigencia: "2026-11-20" });
      const anterior = await db.one("select tasa from tipo_cambio_referencia('USD', 'CRC', '2026-11-10')");
      expect(anterior.tasa).toBe("510.000000");
      const inversa = await db.one<{ r: string }>("select round(tasa * 520, 6) as r from tipo_cambio_referencia('CRC', 'USD', '2026-11-25')");
      expect(inversa.r).toBe("1.000000");
      const ninguna = await db.q("select * from tipo_cambio_referencia('EUR', 'CRC', '2026-11-25')");
      expect(ninguna).toEqual([]);
    });
  });
});
