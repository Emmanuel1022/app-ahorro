# App Ahorro

Aplicación web de gestión y control de finanzas personales: bancos, cuentas, movimientos,
transferencias, metas de ahorro, presupuestos, movimientos recurrentes, reportes y multimoneda (CRC / USD).

**Stack:** Next.js 15 (App Router) · TypeScript · Tailwind CSS · Supabase (PostgreSQL, Auth, Storage, RLS) · Vitest.

## Principios

- El saldo de una cuenta **no se guarda**: se calcula como saldo inicial + movimientos activos (`v_saldos_cuentas`).
- Montos en `NUMERIC(18,2)` y aritmética con `decimal.js`; nunca `float`.
- Cada movimiento conserva su monto y moneda originales; los consolidados se convierten con un tipo de cambio fechado.
- Las reglas críticas viven en la base de datos: constraints, triggers, funciones transaccionales y Row Level Security.
- Nada con historial se borra: los movimientos se anulan y bancos, cuentas y categorías se desactivan.

## Nombres en la base de datos

Tablas, columnas, valores y funciones están en español: `bancos`, `cuentas`, `categorias`, `movimientos`,
`transferencias`, `metas_ahorro`, `aportes_meta`, `presupuestos`, `reglas_recurrentes`, `tipos_cambio`,
`historial_cambios`; funciones `crear_transferencia`, `actualizar_transferencia`, `anular_transferencia`,
`saldo_cuenta` y `tipo_cambio_referencia`. El código TypeScript usa nombres en inglés.

## Estructura

```
supabase/migrations/   Esquema, reglas de negocio, vistas, RLS, auditoría y semillas (SQL)
src/lib/               Utilidades compartidas (money.ts: aritmética y formato de montos)
src/server/services/   Lógica de dominio: tipos de cambio, presupuestos, fechas recurrentes
tests/unit/            Pruebas de cálculo puras
tests/integration/     Pruebas contra PostgreSQL real (saldos, transferencias, RLS, etc.)
```

## Desarrollo local

```bash
npm install
cp .env.example .env.local   # completa con tu proyecto Supabase
npm run dev
```

## Pruebas

Las pruebas de integración crean una base `app_ahorro_test` en un PostgreSQL local y aplican todas las migraciones.

```bash
npm test             # todas (requiere PostgreSQL; ver TEST_DATABASE_ADMIN_URL en .env.example)
npm run test:unit    # solo las que no necesitan base de datos
npm run build && npm run test:e2e   # punta a punta con Playwright (usa un Auth simulado)
```

Para las pruebas de punta a punta, compila con `NEXT_PUBLIC_SUPABASE_URL=http://localhost:54329` y
`NEXT_PUBLIC_SUPABASE_ANON_KEY=clave-de-prueba`: Playwright levanta `tests/e2e/mock-auth-server.mjs`,
que imita Supabase Auth.

## Base de datos en Supabase

Con la [CLI de Supabase](https://supabase.com/docs/guides/cli): `supabase link` y luego `supabase db push`
aplica las migraciones de `supabase/migrations/`. También se pueden ejecutar en orden desde el SQL Editor del panel.

En **Authentication → URL Configuration** define la *Site URL* (por ejemplo `http://localhost:3000` en desarrollo)
y agrega `<tu-dominio>/auth/callback` a las *Redirect URLs*: es el destino de los correos de confirmación y de
recuperación de contraseña.
