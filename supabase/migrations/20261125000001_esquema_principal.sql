-- =====================================================================
-- App Ahorro · Esquema principal
-- Montos: NUMERIC(18,2). Tipos de cambio: NUMERIC(18,6).
-- El saldo de una cuenta NO se guarda: se calcula en v_saldos_cuentas.
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- Tipos enumerados
-- ---------------------------------------------------------------------
create type public.tipo_cuenta           as enum ('ahorro', 'corriente', 'efectivo', 'inversion', 'otra');
create type public.tipo_categoria        as enum ('ingreso', 'gasto');
create type public.tipo_movimiento       as enum ('ingreso', 'gasto', 'transferencia_salida', 'transferencia_entrada', 'ajuste');
create type public.estado_registro       as enum ('activo', 'anulado');
create type public.prioridad_meta        as enum ('alta', 'media', 'baja');
create type public.estado_meta           as enum ('activa', 'pausada', 'completada', 'cancelada');
create type public.tipo_aporte_meta      as enum ('aporte', 'retiro');
create type public.frecuencia_recurrente as enum ('semanal', 'quincenal', 'mensual', 'anual');
create type public.modo_recurrente       as enum ('automatico', 'confirmar');
create type public.estado_ocurrencia     as enum ('pendiente', 'registrada', 'omitida');

-- ---------------------------------------------------------------------
-- Utilidades
-- ---------------------------------------------------------------------
create or replace function public.fijar_actualizado_en() returns trigger
language plpgsql as $$
begin
  new.actualizado_en := now();
  return new;
end $$;

-- ---------------------------------------------------------------------
-- Catálogo global de monedas
-- ---------------------------------------------------------------------
create table public.monedas (
  codigo     char(3) primary key check (codigo ~ '^[A-Z]{3}$'),
  nombre     text not null,
  simbolo    text not null,
  decimales  smallint not null default 2 check (decimales between 0 and 4)
);

-- ---------------------------------------------------------------------
-- Perfil del usuario (1 a 1 con auth.users)
-- ---------------------------------------------------------------------
create table public.perfiles (
  id               uuid primary key references auth.users (id) on delete cascade,
  nombre_completo  text,
  moneda_principal char(3) not null default 'CRC' references public.monedas (codigo),
  zona_horaria     text not null default 'America/Costa_Rica',
  ocultar_montos   boolean not null default false,
  tema             text not null default 'sistema' check (tema in ('claro', 'oscuro', 'sistema')),
  creado_en        timestamptz not null default now(),
  actualizado_en   timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Tipos de cambio: 1 moneda_origen = tasa moneda_destino, vigente desde fecha_vigencia
-- ---------------------------------------------------------------------
create table public.tipos_cambio (
  id              uuid primary key default gen_random_uuid(),
  usuario_id      uuid not null default auth.uid() references auth.users (id) on delete cascade,
  moneda_origen   char(3) not null references public.monedas (codigo),
  moneda_destino  char(3) not null references public.monedas (codigo),
  tasa            numeric(18, 6) not null check (tasa > 0),
  fecha_vigencia  date not null,
  fuente          text not null default 'manual',
  creado_en       timestamptz not null default now(),
  actualizado_en  timestamptz not null default now(),
  check (moneda_origen <> moneda_destino),
  unique (usuario_id, moneda_origen, moneda_destino, fecha_vigencia)
);

-- ---------------------------------------------------------------------
-- Bancos
-- ---------------------------------------------------------------------
create table public.bancos (
  id             uuid primary key default gen_random_uuid(),
  usuario_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
  nombre         text not null check (char_length(btrim(nombre)) between 1 and 100),
  logo_url       text,
  icono          text,
  color          text check (color is null or color ~ '^#[0-9A-Fa-f]{6}$'),
  descripcion    text,
  activo         boolean not null default true,
  creado_en      timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  unique (id, usuario_id)
);
create unique index bancos_usuario_nombre_uq on public.bancos (usuario_id, lower(btrim(nombre)));

-- ---------------------------------------------------------------------
-- Cuentas bancarias
-- ---------------------------------------------------------------------
create table public.cuentas (
  id                  uuid primary key default gen_random_uuid(),
  usuario_id          uuid not null default auth.uid() references auth.users (id) on delete cascade,
  banco_id            uuid not null,
  nombre              text not null check (char_length(btrim(nombre)) between 1 and 100),
  numero_cuenta       text,
  tipo                public.tipo_cuenta not null default 'ahorro',
  moneda              char(3) not null references public.monedas (codigo),
  saldo_inicial       numeric(18, 2) not null default 0,
  fecha_saldo_inicial date not null default current_date,
  descripcion         text,
  activa              boolean not null default true,
  incluir_en_total    boolean not null default true,
  creado_en           timestamptz not null default now(),
  actualizado_en      timestamptz not null default now(),
  unique (id, usuario_id),
  foreign key (banco_id, usuario_id) references public.bancos (id, usuario_id) on delete restrict
);
create unique index cuentas_usuario_banco_nombre_uq on public.cuentas (usuario_id, banco_id, lower(btrim(nombre)));
create index cuentas_banco_idx on public.cuentas (banco_id);

-- ---------------------------------------------------------------------
-- Categorías y subcategorías (un solo nivel de anidación)
-- ---------------------------------------------------------------------
create table public.categorias (
  id             uuid primary key default gen_random_uuid(),
  usuario_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
  padre_id       uuid,
  tipo           public.tipo_categoria not null,
  nombre         text not null check (char_length(btrim(nombre)) between 1 and 60),
  icono          text,
  color          text check (color is null or color ~ '^#[0-9A-Fa-f]{6}$'),
  descripcion    text,
  activa         boolean not null default true,
  predeterminada boolean not null default false,
  clave_sistema  text,  -- marca categorías que usa el sistema (p. ej. 'comisiones_bancarias')
  creado_en      timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  unique (id, usuario_id),
  check (padre_id is null or padre_id <> id),
  foreign key (padre_id, usuario_id) references public.categorias (id, usuario_id) on delete restrict
);
create unique index categorias_usuario_padre_nombre_uq
  on public.categorias (usuario_id, coalesce(padre_id, '00000000-0000-0000-0000-000000000000'::uuid), tipo, lower(btrim(nombre)));
create unique index categorias_usuario_clave_sistema_uq on public.categorias (usuario_id, clave_sistema) where clave_sistema is not null;

-- ---------------------------------------------------------------------
-- Métodos de pago
-- ---------------------------------------------------------------------
create table public.metodos_pago (
  id             uuid primary key default gen_random_uuid(),
  usuario_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
  nombre         text not null check (char_length(btrim(nombre)) between 1 and 60),
  activo         boolean not null default true,
  creado_en      timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  unique (id, usuario_id)
);
create unique index metodos_pago_usuario_nombre_uq on public.metodos_pago (usuario_id, lower(btrim(nombre)));

-- ---------------------------------------------------------------------
-- Transferencias entre cuentas propias (agrupan 2 o 3 movimientos)
-- ---------------------------------------------------------------------
create table public.transferencias (
  id                 uuid primary key default gen_random_uuid(),
  usuario_id         uuid not null default auth.uid() references auth.users (id) on delete cascade,
  cuenta_origen_id   uuid not null,
  cuenta_destino_id  uuid not null,
  monto_enviado      numeric(18, 2) not null check (monto_enviado > 0),
  monto_recibido     numeric(18, 2) not null check (monto_recibido > 0),
  tipo_cambio        numeric(18, 6) check (tipo_cambio is null or tipo_cambio > 0),
  comision           numeric(18, 2) not null default 0 check (comision >= 0),
  fecha              timestamptz not null default now(),
  descripcion        text,
  estado             public.estado_registro not null default 'activo',
  anulado_en         timestamptz,
  motivo_anulacion   text,
  clave_idempotencia uuid,
  creado_en          timestamptz not null default now(),
  actualizado_en     timestamptz not null default now(),
  unique (id, usuario_id),
  check (cuenta_origen_id <> cuenta_destino_id),
  check ((estado = 'anulado') = (anulado_en is not null)),
  foreign key (cuenta_origen_id, usuario_id)  references public.cuentas (id, usuario_id) on delete restrict,
  foreign key (cuenta_destino_id, usuario_id) references public.cuentas (id, usuario_id) on delete restrict
);
create unique index transferencias_idempotencia_uq on public.transferencias (usuario_id, clave_idempotencia) where clave_idempotencia is not null;
create index transferencias_usuario_fecha_idx on public.transferencias (usuario_id, fecha desc);

-- ---------------------------------------------------------------------
-- Movimientos recurrentes
-- ---------------------------------------------------------------------
create table public.reglas_recurrentes (
  id              uuid primary key default gen_random_uuid(),
  usuario_id      uuid not null default auth.uid() references auth.users (id) on delete cascade,
  tipo            public.tipo_categoria not null,
  cuenta_id       uuid not null,
  categoria_id    uuid not null,
  monto           numeric(18, 2) not null check (monto > 0),
  descripcion     text not null check (char_length(btrim(descripcion)) between 1 and 200),
  metodo_pago_id  uuid,
  frecuencia      public.frecuencia_recurrente not null,
  fecha_inicio    date not null,
  fecha_fin       date,
  proxima_fecha   date not null,
  modo            public.modo_recurrente not null default 'confirmar',
  activa          boolean not null default true,
  creado_en       timestamptz not null default now(),
  actualizado_en  timestamptz not null default now(),
  unique (id, usuario_id),
  check (fecha_fin is null or fecha_fin >= fecha_inicio),
  foreign key (cuenta_id, usuario_id)      references public.cuentas (id, usuario_id) on delete restrict,
  foreign key (categoria_id, usuario_id)   references public.categorias (id, usuario_id) on delete restrict,
  foreign key (metodo_pago_id, usuario_id) references public.metodos_pago (id, usuario_id) on delete restrict
);

create table public.ocurrencias_recurrentes (
  id               uuid primary key default gen_random_uuid(),
  usuario_id       uuid not null default auth.uid() references auth.users (id) on delete cascade,
  regla_id         uuid not null,
  fecha_programada date not null,
  estado           public.estado_ocurrencia not null default 'pendiente',
  creado_en        timestamptz not null default now(),
  actualizado_en   timestamptz not null default now(),
  unique (id, usuario_id),
  unique (regla_id, fecha_programada),  -- imposible generar la misma ocurrencia dos veces
  foreign key (regla_id, usuario_id) references public.reglas_recurrentes (id, usuario_id) on delete cascade
);

-- ---------------------------------------------------------------------
-- Movimientos: el libro mayor
-- ---------------------------------------------------------------------
create table public.movimientos (
  id                 uuid primary key default gen_random_uuid(),
  usuario_id         uuid not null default auth.uid() references auth.users (id) on delete cascade,
  tipo               public.tipo_movimiento not null,
  direccion          smallint not null check (direccion in (-1, 1)),
  cuenta_id          uuid not null,
  categoria_id       uuid,
  monto              numeric(18, 2) not null check (monto > 0),
  moneda             char(3) not null references public.monedas (codigo),
  fecha              timestamptz not null default now(),
  descripcion        text,
  referencia         text,
  metodo_pago_id     uuid,
  ruta_comprobante   text,
  observaciones      text,
  transferencia_id   uuid,
  ocurrencia_id      uuid unique,
  estado             public.estado_registro not null default 'activo',
  anulado_en         timestamptz,
  motivo_anulacion   text,
  clave_idempotencia uuid,
  creado_en          timestamptz not null default now(),
  actualizado_en     timestamptz not null default now(),
  check ((estado = 'anulado') = (anulado_en is not null)),
  check (
       (tipo = 'ingreso'               and direccion =  1 and categoria_id is not null)
    or (tipo = 'gasto'                 and direccion = -1 and categoria_id is not null)
    or (tipo = 'transferencia_salida'  and direccion = -1 and categoria_id is null and transferencia_id is not null)
    or (tipo = 'transferencia_entrada' and direccion =  1 and categoria_id is null and transferencia_id is not null)
    or (tipo = 'ajuste'                and categoria_id is null and transferencia_id is null
        and descripcion is not null and char_length(btrim(descripcion)) > 0)
  ),
  foreign key (cuenta_id, usuario_id)        references public.cuentas (id, usuario_id) on delete restrict,
  foreign key (categoria_id, usuario_id)     references public.categorias (id, usuario_id) on delete restrict,
  foreign key (metodo_pago_id, usuario_id)   references public.metodos_pago (id, usuario_id) on delete restrict,
  foreign key (transferencia_id, usuario_id) references public.transferencias (id, usuario_id) on delete restrict,
  foreign key (ocurrencia_id, usuario_id)    references public.ocurrencias_recurrentes (id, usuario_id) on delete restrict
);
create unique index movimientos_idempotencia_uq on public.movimientos (usuario_id, clave_idempotencia) where clave_idempotencia is not null;
create index movimientos_cuenta_estado_idx  on public.movimientos (cuenta_id, estado);
create index movimientos_usuario_fecha_idx  on public.movimientos (usuario_id, fecha desc);
create index movimientos_categoria_idx      on public.movimientos (categoria_id);
create index movimientos_transferencia_idx  on public.movimientos (transferencia_id);

-- ---------------------------------------------------------------------
-- Metas de ahorro (apartados: no mueven dinero)
-- ---------------------------------------------------------------------
create table public.metas_ahorro (
  id             uuid primary key default gen_random_uuid(),
  usuario_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
  nombre         text not null check (char_length(btrim(nombre)) between 1 and 100),
  monto_objetivo numeric(18, 2) not null check (monto_objetivo > 0),
  moneda         char(3) not null references public.monedas (codigo),
  fecha_objetivo date,
  cuenta_id      uuid,
  prioridad      public.prioridad_meta not null default 'media',
  descripcion    text,
  estado         public.estado_meta not null default 'activa',
  creado_en      timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  unique (id, usuario_id),
  foreign key (cuenta_id, usuario_id) references public.cuentas (id, usuario_id) on delete restrict
);

create table public.aportes_meta (
  id             uuid primary key default gen_random_uuid(),
  usuario_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
  meta_id        uuid not null,
  tipo           public.tipo_aporte_meta not null,
  monto          numeric(18, 2) not null check (monto > 0),
  fecha          date not null default current_date,
  nota           text,
  estado         public.estado_registro not null default 'activo',
  anulado_en     timestamptz,
  creado_en      timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  check ((estado = 'anulado') = (anulado_en is not null)),
  foreign key (meta_id, usuario_id) references public.metas_ahorro (id, usuario_id) on delete cascade
);
create index aportes_meta_meta_idx on public.aportes_meta (meta_id);

-- ---------------------------------------------------------------------
-- Presupuestos mensuales por categoría de gasto
-- ---------------------------------------------------------------------
create table public.presupuestos (
  id             uuid primary key default gen_random_uuid(),
  usuario_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
  categoria_id   uuid not null,
  mes            date not null check (extract(day from mes) = 1),
  monto          numeric(18, 2) not null check (monto > 0),
  moneda         char(3) not null references public.monedas (codigo),
  creado_en      timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  unique (usuario_id, categoria_id, mes),
  foreign key (categoria_id, usuario_id) references public.categorias (id, usuario_id) on delete restrict
);

-- ---------------------------------------------------------------------
-- Historial de modificaciones
-- ---------------------------------------------------------------------
create table public.historial_cambios (
  id            bigint generated always as identity primary key,
  usuario_id    uuid,  -- sin FK: el historial sobrevive aunque cambien los registros
  tabla         text not null,
  registro_id   uuid,
  accion        text not null check (accion in ('crear', 'editar', 'eliminar', 'anular', 'restaurar')),
  datos_antes   jsonb,
  datos_despues jsonb,
  fecha         timestamptz not null default now()
);
create index historial_cambios_registro_idx on public.historial_cambios (tabla, registro_id);
create index historial_cambios_usuario_idx  on public.historial_cambios (usuario_id, fecha desc);

-- ---------------------------------------------------------------------
-- actualizado_en automático
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['perfiles', 'tipos_cambio', 'bancos', 'cuentas', 'categorias', 'metodos_pago',
                           'transferencias', 'reglas_recurrentes', 'ocurrencias_recurrentes', 'movimientos',
                           'metas_ahorro', 'aportes_meta', 'presupuestos']
  loop
    execute format('create trigger %I before update on public.%I for each row execute function public.fijar_actualizado_en()',
                   t || '_fijar_actualizado_en', t);
  end loop;
end $$;
