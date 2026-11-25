import { randomUUID } from "node:crypto";
import { Client } from "pg";

const url = () => {
  const u = new URL(process.env.TEST_DATABASE_ADMIN_URL ?? "postgres://postgres:postgres@localhost:5432/postgres");
  u.pathname = "/app_ahorro_test";
  return u.toString();
};

export async function connect(): Promise<Client> {
  const c = new Client({ connectionString: url() });
  await c.connect();
  return c;
}

/** Crea un usuario en auth.users (dispara las semillas) y devuelve su id. */
export async function createUser(admin: Client): Promise<string> {
  const id = randomUUID();
  await admin.query("insert into auth.users (id, email) values ($1, $2)", [id, `${id}@test.local`]);
  return id;
}

export type Db = { q: <T = Record<string, unknown>>(sql: string, params?: unknown[]) => Promise<T[]>; one: <T = Record<string, unknown>>(sql: string, params?: unknown[]) => Promise<T> };

/**
 * Ejecuta `fn` como el usuario indicado, con rol `authenticated` y RLS activo,
 * igual que una petición real desde la app. Todo se confirma al final.
 */
export async function asUser<T>(client: Client, userId: string, fn: (db: Db) => Promise<T>): Promise<T> {
  await client.query("begin");
  try {
    await client.query("set local role authenticated");
    await client.query("select set_config('request.jwt.claim.sub', $1, true)", [userId]);
    const db: Db = {
      q: async (sql, params) => (await client.query(sql, params)).rows,
      one: async (sql, params) => (await client.query(sql, params)).rows[0],
    };
    const result = await fn(db);
    await client.query("commit");
    return result;
  } catch (e) {
    await client.query("rollback");
    throw e;
  }
}

export async function balance(db: Db, accountId: string): Promise<string> {
  const r = await db.one<{ saldo_actual: string }>(
    "select saldo_actual from v_saldos_cuentas where cuenta_id = $1",
    [accountId],
  );
  return r.saldo_actual;
}

export async function setupAccounts(db: Db) {
  const bank = await db.one<{ id: string }>("insert into bancos (nombre, color) values ('BAC', '#E11D48') returning id");
  const bank2 = await db.one<{ id: string }>("insert into bancos (nombre) values ('BN') returning id");
  const crc = await db.one<{ id: string }>(
    "insert into cuentas (banco_id, nombre, tipo, moneda, saldo_inicial) values ($1, 'Ahorro colones', 'ahorro', 'CRC', 100000) returning id",
    [bank.id],
  );
  const crc2 = await db.one<{ id: string }>(
    "insert into cuentas (banco_id, nombre, tipo, moneda, saldo_inicial) values ($1, 'Corriente BN', 'corriente', 'CRC', 0) returning id",
    [bank2.id],
  );
  const usd = await db.one<{ id: string }>(
    "insert into cuentas (banco_id, nombre, tipo, moneda, saldo_inicial) values ($1, 'Ahorro dólares', 'ahorro', 'USD', 1000) returning id",
    [bank.id],
  );
  const cat = async (name: string) =>
    (await db.one<{ id: string }>("select id from categorias where nombre = $1 and padre_id is null", [name])).id;
  return {
    bankId: bank.id,
    bank2Id: bank2.id,
    crc: crc.id,
    crc2: crc2.id,
    usd: usd.id,
    salary: await cat("Salario"),
    food: await cat("Alimentación"),
  };
}

export async function expectError(p: Promise<unknown>, match: RegExp) {
  let err: unknown;
  try {
    await p;
  } catch (e) {
    err = e;
  }
  if (!err) throw new Error(`Se esperaba un error que coincidiera con ${match}`);
  const msg = (err as Error).message;
  if (!match.test(msg)) throw new Error(`Error inesperado: "${msg}" (esperado ${match})`);
}
