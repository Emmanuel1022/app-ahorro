-- App Ahorro: esquema completo con nombres en español. Pegar y ejecutar una sola vez en Supabase → SQL Editor.

-- ===== 20261125000001_esquema_principal.sql =====
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

-- ===== 20261125000002_reglas_negocio.sql =====
-- =====================================================================
-- App Ahorro · Reglas de negocio aplicadas en la base de datos
-- =====================================================================

-- ---------------------------------------------------------------------
-- Categorías: un nivel de subcategoría y mismo tipo que el padre
-- ---------------------------------------------------------------------
create or replace function public.validar_categoria() returns trigger
language plpgsql as $$
declare
  v_padre public.categorias;
begin
  if new.padre_id is not null then
    select * into v_padre from public.categorias where id = new.padre_id;
    if v_padre.padre_id is not null then
      raise exception 'Una subcategoría no puede tener subcategorías' using errcode = 'check_violation';
    end if;
    if v_padre.tipo <> new.tipo then
      raise exception 'La subcategoría debe ser del mismo tipo que su categoría' using errcode = 'check_violation';
    end if;
    if exists (select 1 from public.categorias c where c.padre_id = new.id) then
      raise exception 'Una categoría con subcategorías no puede convertirse en subcategoría' using errcode = 'check_violation';
    end if;
  end if;

  if tg_op = 'UPDATE' and new.tipo <> old.tipo then
    if exists (select 1 from public.movimientos m where m.categoria_id = new.id)
       or exists (select 1 from public.categorias c where c.padre_id = new.id) then
      raise exception 'No se puede cambiar el tipo de una categoría con movimientos o subcategorías' using errcode = 'check_violation';
    end if;
  end if;

  if tg_op = 'UPDATE' and old.clave_sistema is not null and new.clave_sistema is distinct from old.clave_sistema then
    raise exception 'No se puede cambiar la clave de sistema de una categoría' using errcode = 'check_violation';
  end if;
  return new;
end $$;

create trigger categorias_validar before insert or update on public.categorias
for each row execute function public.validar_categoria();

-- ---------------------------------------------------------------------
-- Cuentas: moneda y saldo inicial fijos cuando ya hay movimientos
-- ---------------------------------------------------------------------
create or replace function public.validar_edicion_cuenta() returns trigger
language plpgsql as $$
begin
  if (new.moneda <> old.moneda or new.saldo_inicial <> old.saldo_inicial or new.fecha_saldo_inicial <> old.fecha_saldo_inicial)
     and exists (select 1 from public.movimientos m where m.cuenta_id = new.id) then
    raise exception 'La cuenta ya tiene movimientos: corrige el saldo con un movimiento de ajuste'
      using errcode = 'check_violation';
  end if;
  return new;
end $$;

create trigger cuentas_validar_edicion before update on public.cuentas
for each row execute function public.validar_edicion_cuenta();

-- Un banco no se desactiva mientras tenga cuentas activas
create or replace function public.validar_edicion_banco() returns trigger
language plpgsql as $$
begin
  if old.activo and not new.activo
     and exists (select 1 from public.cuentas c where c.banco_id = new.id and c.activa) then
    raise exception 'Desactiva primero las cuentas activas de este banco' using errcode = 'check_violation';
  end if;
  return new;
end $$;

create trigger bancos_validar_edicion before update on public.bancos
for each row execute function public.validar_edicion_banco();

-- ---------------------------------------------------------------------
-- Movimientos
-- ---------------------------------------------------------------------
create or replace function public.validar_movimiento() returns trigger
language plpgsql as $$
declare
  v_cuenta    public.cuentas;
  v_categoria public.categorias;
  v_desde_transferencia boolean := coalesce(current_setting('app.operacion_transferencia', true), '') = 'on';
begin
  -- Las piezas de una transferencia solo se tocan desde las funciones de transferencia
  if new.transferencia_id is not null or (tg_op = 'UPDATE' and old.transferencia_id is not null) then
    if not v_desde_transferencia then
      raise exception 'Los movimientos de una transferencia se modifican desde la transferencia'
        using errcode = 'check_violation';
    end if;
  end if;

  select * into v_cuenta from public.cuentas where id = new.cuenta_id;
  if new.moneda <> v_cuenta.moneda then
    raise exception 'La moneda del movimiento (%) debe ser la de la cuenta (%)', new.moneda, v_cuenta.moneda
      using errcode = 'check_violation';
  end if;

  -- Cuenta y categoría activas al crear o al cambiarlas
  if tg_op = 'INSERT' or new.cuenta_id <> old.cuenta_id then
    if not v_cuenta.activa then
      raise exception 'La cuenta está inactiva' using errcode = 'check_violation';
    end if;
  end if;

  if new.categoria_id is not null then
    select * into v_categoria from public.categorias where id = new.categoria_id;
    if (new.tipo = 'ingreso' and v_categoria.tipo <> 'ingreso')
       or (new.tipo = 'gasto' and v_categoria.tipo <> 'gasto') then
      raise exception 'La categoría no corresponde al tipo de movimiento' using errcode = 'check_violation';
    end if;
    if (tg_op = 'INSERT' or new.categoria_id is distinct from old.categoria_id) and not v_categoria.activa then
      raise exception 'La categoría está inactiva' using errcode = 'check_violation';
    end if;
  end if;

  -- Una anulación se registra con fecha
  if new.estado = 'anulado' and new.anulado_en is null then
    new.anulado_en := now();
  elsif new.estado = 'activo' then
    new.anulado_en := null;
    new.motivo_anulacion := null;
  end if;
  return new;
end $$;

create trigger movimientos_validar before insert or update on public.movimientos
for each row execute function public.validar_movimiento();

-- Los movimientos no se borran físicamente: se anulan
create or replace function public.impedir_eliminacion() returns trigger
language plpgsql as $$
begin
  raise exception 'Este registro no se elimina: anúlalo para conservar el historial' using errcode = 'check_violation';
end $$;

create trigger movimientos_no_eliminar before delete on public.movimientos
for each row execute function public.impedir_eliminacion();
create trigger transferencias_no_eliminar before delete on public.transferencias
for each row execute function public.impedir_eliminacion();

-- ---------------------------------------------------------------------
-- Saldos
-- ---------------------------------------------------------------------
create or replace function public.saldo_cuenta(p_cuenta_id uuid, p_hasta timestamptz default null)
returns numeric
language sql stable security invoker as $$
  select c.saldo_inicial + coalesce(sum(m.direccion * m.monto) filter (
           where m.estado = 'activo' and (p_hasta is null or m.fecha <= p_hasta)), 0)
  from public.cuentas c
  left join public.movimientos m on m.cuenta_id = c.id
  where c.id = p_cuenta_id
  group by c.id, c.saldo_inicial
$$;

-- ---------------------------------------------------------------------
-- Tipo de cambio de referencia: el más reciente vigente a la fecha.
-- Devuelve cuántas unidades de p_destino vale 1 unidad de p_origen, o nada si no hay.
-- ---------------------------------------------------------------------
create or replace function public.tipo_cambio_referencia(p_origen char(3), p_destino char(3), p_fecha date default current_date)
returns table (tasa numeric, fecha_vigencia date)
language sql stable security invoker as $$
  select r.tasa, r.fecha_vigencia from (
    select 1::numeric as tasa, p_fecha as fecha_vigencia, 0 as prioridad
    where p_origen = p_destino
    union all
    select x.tasa, x.fecha_vigencia, 1
    from public.tipos_cambio x
    where x.usuario_id = auth.uid() and x.moneda_origen = p_origen and x.moneda_destino = p_destino and x.fecha_vigencia <= p_fecha
    union all
    select 1 / x.tasa, x.fecha_vigencia, 1
    from public.tipos_cambio x
    where x.usuario_id = auth.uid() and x.moneda_origen = p_destino and x.moneda_destino = p_origen and x.fecha_vigencia <= p_fecha
  ) r
  order by r.prioridad, r.fecha_vigencia desc
  limit 1
$$;

-- ---------------------------------------------------------------------
-- Transferencias: todo en una sola transacción
-- ---------------------------------------------------------------------
create or replace function public.categoria_comisiones_id() returns uuid
language plpgsql security invoker as $$
declare v_id uuid;
begin
  select id into v_id from public.categorias where usuario_id = auth.uid() and clave_sistema = 'comisiones_bancarias';
  if v_id is null then
    insert into public.categorias (usuario_id, tipo, nombre, icono, color, predeterminada, clave_sistema)
    values (auth.uid(), 'gasto', 'Comisiones bancarias', 'landmark', '#64748B', true, 'comisiones_bancarias')
    returning id into v_id;
  end if;
  return v_id;
end $$;

create or replace function public.resolver_montos_transferencia(
  p_origen public.cuentas, p_destino public.cuentas,
  p_monto_enviado numeric, p_monto_recibido numeric, p_tipo_cambio numeric,
  out monto_recibido numeric, out tipo_cambio numeric)
language plpgsql immutable as $$
begin
  if p_origen.moneda = p_destino.moneda then
    if p_monto_recibido is not null and p_monto_recibido <> p_monto_enviado then
      raise exception 'En cuentas de la misma moneda el monto recibido debe ser igual al enviado'
        using errcode = 'check_violation';
    end if;
    monto_recibido := p_monto_enviado;
    tipo_cambio := null;
  else
    if p_monto_recibido is null and p_tipo_cambio is null then
      raise exception 'Las cuentas tienen monedas distintas: indica el tipo de cambio o el monto recibido'
        using errcode = 'check_violation';
    end if;
    -- tipo_cambio = unidades de la moneda destino por 1 unidad de la moneda origen
    monto_recibido := coalesce(p_monto_recibido, round(p_monto_enviado * p_tipo_cambio, 2));
    tipo_cambio := coalesce(p_tipo_cambio, round(p_monto_recibido / p_monto_enviado, 6));
  end if;
end $$;

create or replace function public.crear_transferencia(
  p_cuenta_origen_id   uuid,
  p_cuenta_destino_id  uuid,
  p_monto_enviado      numeric,
  p_fecha              timestamptz default now(),
  p_descripcion        text default null,
  p_monto_recibido     numeric default null,
  p_tipo_cambio        numeric default null,
  p_comision           numeric default 0,
  p_clave_idempotencia uuid default null
) returns uuid
language plpgsql security invoker as $$
declare
  v_origen  public.cuentas;
  v_destino public.cuentas;
  v_id      uuid;
  v_montos  record;
  v_comision numeric := coalesce(p_comision, 0);
  v_fecha   timestamptz := coalesce(p_fecha, now());
begin
  if p_clave_idempotencia is not null then
    select id into v_id from public.transferencias where usuario_id = auth.uid() and clave_idempotencia = p_clave_idempotencia;
    if v_id is not null then return v_id; end if;
  end if;

  if p_cuenta_origen_id = p_cuenta_destino_id then
    raise exception 'La cuenta de origen y la de destino deben ser distintas' using errcode = 'check_violation';
  end if;
  if p_monto_enviado is null or p_monto_enviado <= 0 then
    raise exception 'El monto debe ser mayor que cero' using errcode = 'check_violation';
  end if;
  if v_comision < 0 then
    raise exception 'La comisión no puede ser negativa' using errcode = 'check_violation';
  end if;

  -- Bloquea ambas cuentas en orden fijo para evitar interbloqueos
  perform 1 from public.cuentas where id in (p_cuenta_origen_id, p_cuenta_destino_id) order by id for update;
  select * into v_origen  from public.cuentas where id = p_cuenta_origen_id;
  select * into v_destino from public.cuentas where id = p_cuenta_destino_id;
  if v_origen.id is null or v_destino.id is null then
    raise exception 'Cuenta no encontrada' using errcode = 'foreign_key_violation';
  end if;

  select * into v_montos from public.resolver_montos_transferencia(v_origen, v_destino, p_monto_enviado, p_monto_recibido, p_tipo_cambio);

  perform set_config('app.operacion_transferencia', 'on', true);

  insert into public.transferencias (usuario_id, cuenta_origen_id, cuenta_destino_id, monto_enviado, monto_recibido,
                                     tipo_cambio, comision, fecha, descripcion, clave_idempotencia)
  values (auth.uid(), v_origen.id, v_destino.id, p_monto_enviado, v_montos.monto_recibido,
          v_montos.tipo_cambio, v_comision, v_fecha, p_descripcion, p_clave_idempotencia)
  returning id into v_id;

  insert into public.movimientos (usuario_id, tipo, direccion, cuenta_id, monto, moneda, fecha, descripcion, transferencia_id)
  values (auth.uid(), 'transferencia_salida',  -1, v_origen.id,  p_monto_enviado,         v_origen.moneda,  v_fecha, p_descripcion, v_id),
         (auth.uid(), 'transferencia_entrada',  1, v_destino.id, v_montos.monto_recibido, v_destino.moneda, v_fecha, p_descripcion, v_id);

  if v_comision > 0 then
    insert into public.movimientos (usuario_id, tipo, direccion, cuenta_id, categoria_id, monto, moneda, fecha, descripcion, transferencia_id)
    values (auth.uid(), 'gasto', -1, v_origen.id, public.categoria_comisiones_id(), v_comision, v_origen.moneda,
            v_fecha, 'Comisión de transferencia', v_id);
  end if;

  perform set_config('app.operacion_transferencia', 'off', true);
  return v_id;
end $$;

create or replace function public.actualizar_transferencia(
  p_transferencia_id uuid,
  p_monto_enviado    numeric,
  p_fecha            timestamptz,
  p_descripcion      text default null,
  p_monto_recibido   numeric default null,
  p_tipo_cambio      numeric default null,
  p_comision         numeric default 0
) returns uuid
language plpgsql security invoker as $$
declare
  v_tr      public.transferencias;
  v_origen  public.cuentas;
  v_destino public.cuentas;
  v_montos  record;
  v_comision numeric := coalesce(p_comision, 0);
begin
  select * into v_tr from public.transferencias where id = p_transferencia_id for update;
  if v_tr.id is null then
    raise exception 'Transferencia no encontrada' using errcode = 'no_data_found';
  end if;
  if v_tr.estado = 'anulado' then
    raise exception 'La transferencia está anulada' using errcode = 'check_violation';
  end if;
  if p_monto_enviado is null or p_monto_enviado <= 0 then
    raise exception 'El monto debe ser mayor que cero' using errcode = 'check_violation';
  end if;
  if v_comision < 0 then
    raise exception 'La comisión no puede ser negativa' using errcode = 'check_violation';
  end if;

  select * into v_origen  from public.cuentas where id = v_tr.cuenta_origen_id;
  select * into v_destino from public.cuentas where id = v_tr.cuenta_destino_id;
  select * into v_montos from public.resolver_montos_transferencia(v_origen, v_destino, p_monto_enviado, p_monto_recibido, p_tipo_cambio);

  perform set_config('app.operacion_transferencia', 'on', true);

  update public.transferencias
     set monto_enviado = p_monto_enviado, monto_recibido = v_montos.monto_recibido, tipo_cambio = v_montos.tipo_cambio,
         comision = v_comision, fecha = p_fecha, descripcion = p_descripcion
   where id = v_tr.id;

  update public.movimientos set monto = p_monto_enviado, fecha = p_fecha, descripcion = p_descripcion
   where transferencia_id = v_tr.id and tipo = 'transferencia_salida';
  update public.movimientos set monto = v_montos.monto_recibido, fecha = p_fecha, descripcion = p_descripcion
   where transferencia_id = v_tr.id and tipo = 'transferencia_entrada';

  if v_comision > 0 then
    update public.movimientos set monto = v_comision, fecha = p_fecha, estado = 'activo'
     where transferencia_id = v_tr.id and tipo = 'gasto';
    if not found then
      insert into public.movimientos (usuario_id, tipo, direccion, cuenta_id, categoria_id, monto, moneda, fecha, descripcion, transferencia_id)
      values (v_tr.usuario_id, 'gasto', -1, v_origen.id, public.categoria_comisiones_id(), v_comision, v_origen.moneda,
              p_fecha, 'Comisión de transferencia', v_tr.id);
    end if;
  else
    update public.movimientos set estado = 'anulado', motivo_anulacion = 'Comisión eliminada'
     where transferencia_id = v_tr.id and tipo = 'gasto' and estado = 'activo';
  end if;

  perform set_config('app.operacion_transferencia', 'off', true);
  return v_tr.id;
end $$;

create or replace function public.anular_transferencia(p_transferencia_id uuid, p_motivo text default null)
returns void
language plpgsql security invoker as $$
begin
  perform set_config('app.operacion_transferencia', 'on', true);
  update public.transferencias set estado = 'anulado', anulado_en = now(), motivo_anulacion = p_motivo
   where id = p_transferencia_id and estado = 'activo';
  if not found then
    raise exception 'Transferencia no encontrada o ya anulada' using errcode = 'no_data_found';
  end if;
  update public.movimientos set estado = 'anulado', motivo_anulacion = p_motivo
   where transferencia_id = p_transferencia_id and estado = 'activo';
  perform set_config('app.operacion_transferencia', 'off', true);
end $$;

-- ---------------------------------------------------------------------
-- Metas: los retiros no pueden dejar el acumulado en negativo;
-- la moneda de la meta es la de su cuenta asociada.
-- ---------------------------------------------------------------------
create or replace function public.validar_meta() returns trigger
language plpgsql as $$
declare v_moneda char(3);
begin
  if new.cuenta_id is not null then
    select moneda into v_moneda from public.cuentas where id = new.cuenta_id;
    if v_moneda <> new.moneda then
      raise exception 'La meta debe estar en la moneda de su cuenta asociada (%)', v_moneda using errcode = 'check_violation';
    end if;
  end if;
  return new;
end $$;

create trigger metas_ahorro_validar before insert or update on public.metas_ahorro
for each row execute function public.validar_meta();

create or replace function public.validar_aporte_meta() returns trigger
language plpgsql as $$
declare v_total numeric;
begin
  if new.estado = 'anulado' and new.anulado_en is null then new.anulado_en := now(); end if;
  if new.estado = 'activo' then new.anulado_en := null; end if;

  select coalesce(sum(case when a.tipo = 'aporte' then a.monto else -a.monto end), 0)
    into v_total
    from public.aportes_meta a
   where a.meta_id = new.meta_id and a.estado = 'activo' and a.id <> new.id;

  if new.estado = 'activo' then
    v_total := v_total + case when new.tipo = 'aporte' then new.monto else -new.monto end;
  end if;
  if v_total < 0 then
    raise exception 'El retiro supera el monto acumulado de la meta' using errcode = 'check_violation';
  end if;
  return new;
end $$;

create trigger aportes_meta_validar before insert or update on public.aportes_meta
for each row execute function public.validar_aporte_meta();

-- ---------------------------------------------------------------------
-- Presupuestos: solo categorías de gasto de primer nivel
-- ---------------------------------------------------------------------
create or replace function public.validar_presupuesto() returns trigger
language plpgsql as $$
declare v_cat public.categorias;
begin
  select * into v_cat from public.categorias where id = new.categoria_id;
  if v_cat.tipo <> 'gasto' or v_cat.padre_id is not null then
    raise exception 'Los presupuestos se definen por categoría de gasto principal' using errcode = 'check_violation';
  end if;
  return new;
end $$;

create trigger presupuestos_validar before insert or update on public.presupuestos
for each row execute function public.validar_presupuesto();

-- ---------------------------------------------------------------------
-- Reglas recurrentes: categoría acorde al tipo
-- ---------------------------------------------------------------------
create or replace function public.validar_regla_recurrente() returns trigger
language plpgsql as $$
declare v_tipo public.tipo_categoria;
begin
  select tipo into v_tipo from public.categorias where id = new.categoria_id;
  if v_tipo <> new.tipo then
    raise exception 'La categoría no corresponde al tipo de la regla' using errcode = 'check_violation';
  end if;
  return new;
end $$;

create trigger reglas_recurrentes_validar before insert or update on public.reglas_recurrentes
for each row execute function public.validar_regla_recurrente();

-- ===== 20261125000003_vistas_seguridad_historial.sql =====
-- =====================================================================
-- App Ahorro · Vistas calculadas, seguridad por usuario (RLS) e historial
-- =====================================================================

-- ---------------------------------------------------------------------
-- Vistas (security_invoker: respetan RLS del usuario que consulta)
-- ---------------------------------------------------------------------
create view public.v_saldos_cuentas with (security_invoker = true) as
select c.id            as cuenta_id,
       c.usuario_id,
       c.banco_id,
       b.nombre        as banco_nombre,
       b.color         as banco_color,
       c.nombre,
       c.tipo,
       c.moneda,
       c.saldo_inicial,
       c.activa,
       c.incluir_en_total,
       c.saldo_inicial + coalesce(sum(m.direccion * m.monto) filter (where m.estado = 'activo'), 0) as saldo_actual,
       max(m.fecha) filter (where m.estado = 'activo') as ultimo_movimiento_en
from public.cuentas c
join public.bancos b on b.id = c.banco_id
left join public.movimientos m on m.cuenta_id = c.id
group by c.id, b.id;

-- Ingresos y gastos por mes y moneda original (sin transferencias ni ajustes)
create view public.v_resumen_mensual with (security_invoker = true) as
select m.usuario_id,
       date_trunc('month', m.fecha at time zone coalesce(p.zona_horaria, 'America/Costa_Rica'))::date as mes,
       m.moneda,
       coalesce(sum(m.monto) filter (where m.tipo = 'ingreso'), 0) as ingresos,
       coalesce(sum(m.monto) filter (where m.tipo = 'gasto'), 0)   as gastos,
       coalesce(sum(m.monto) filter (where m.tipo = 'ingreso'), 0)
         - coalesce(sum(m.monto) filter (where m.tipo = 'gasto'), 0) as balance
from public.movimientos m
left join public.perfiles p on p.id = m.usuario_id
where m.estado = 'activo' and m.tipo in ('ingreso', 'gasto')
group by m.usuario_id, 2, m.moneda;

create view public.v_progreso_metas with (security_invoker = true) as
select g.id as meta_id,
       g.usuario_id,
       g.nombre,
       g.monto_objetivo,
       g.moneda,
       g.fecha_objetivo,
       g.cuenta_id,
       g.prioridad,
       g.estado,
       coalesce(sum(case when a.tipo = 'aporte' then a.monto else -a.monto end)
                filter (where a.estado = 'activo'), 0) as acumulado,
       round(100 * coalesce(sum(case when a.tipo = 'aporte' then a.monto else -a.monto end)
                filter (where a.estado = 'activo'), 0) / g.monto_objetivo, 2) as porcentaje_avance
from public.metas_ahorro g
left join public.aportes_meta a on a.meta_id = g.id
group by g.id;

-- ---------------------------------------------------------------------
-- Row Level Security: cada usuario solo ve y modifica lo suyo
-- ---------------------------------------------------------------------
alter table public.monedas enable row level security;
create policy monedas_lectura on public.monedas for select to authenticated using (true);

alter table public.perfiles enable row level security;
create policy perfiles_propios on public.perfiles for all to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

do $$
declare t text;
begin
  foreach t in array array['tipos_cambio', 'bancos', 'cuentas', 'categorias', 'metodos_pago', 'transferencias',
                           'reglas_recurrentes', 'ocurrencias_recurrentes', 'movimientos', 'metas_ahorro',
                           'aportes_meta', 'presupuestos']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy %I on public.%I for all to authenticated using (usuario_id = auth.uid()) with check (usuario_id = auth.uid())',
                   t || '_propios', t);
  end loop;
end $$;

alter table public.historial_cambios enable row level security;
create policy historial_cambios_lectura_propia on public.historial_cambios for select to authenticated using (usuario_id = auth.uid());
revoke insert, update, delete on public.historial_cambios from authenticated, anon;

-- ---------------------------------------------------------------------
-- Historial: un trigger genérico guarda el antes y el después
-- ---------------------------------------------------------------------
create or replace function public.registrar_cambio() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_accion text;
  v_antes   jsonb := case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) end;
  v_despues jsonb := case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) end;
  v_fila    jsonb := coalesce(v_despues, v_antes);
begin
  v_accion := case tg_op when 'INSERT' then 'crear' when 'UPDATE' then 'editar' else 'eliminar' end;
  if tg_op = 'UPDATE' then
    if v_antes = v_despues then return null; end if;
    if v_antes ? 'estado' and v_antes ->> 'estado' = 'activo' and v_despues ->> 'estado' = 'anulado' then
      v_accion := 'anular';
    elsif v_antes ? 'estado' and v_antes ->> 'estado' = 'anulado' and v_despues ->> 'estado' = 'activo' then
      v_accion := 'restaurar';
    end if;
  end if;

  insert into public.historial_cambios (usuario_id, tabla, registro_id, accion, datos_antes, datos_despues)
  values (coalesce((v_fila ->> 'usuario_id')::uuid, (v_fila ->> 'id')::uuid), tg_table_name, (v_fila ->> 'id')::uuid,
          v_accion, v_antes, v_despues);
  return null;
end $$;

do $$
declare t text;
begin
  foreach t in array array['perfiles', 'tipos_cambio', 'bancos', 'cuentas', 'categorias', 'metodos_pago',
                           'transferencias', 'reglas_recurrentes', 'movimientos', 'metas_ahorro', 'aportes_meta', 'presupuestos']
  loop
    execute format('create trigger %I after insert or update or delete on public.%I for each row execute function public.registrar_cambio()',
                   t || '_historial', t);
  end loop;
end $$;

-- ===== 20261125000004_datos_predeterminados.sql =====
-- =====================================================================
-- App Ahorro · Datos predeterminados
-- =====================================================================

insert into public.monedas (codigo, nombre, simbolo, decimales) values
  ('CRC', 'Colón costarricense', '₡', 2),
  ('USD', 'Dólar estadounidense', '$', 2),
  ('EUR', 'Euro', '€', 2)
on conflict (codigo) do nothing;

-- Crea perfil, categorías y métodos de pago predeterminados de un usuario.
create or replace function public.sembrar_datos_usuario(p_usuario_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into public.perfiles (id, nombre_completo)
  values (p_usuario_id, null)
  on conflict (id) do nothing;

  insert into public.categorias (usuario_id, tipo, nombre, icono, color, predeterminada, clave_sistema) values
    (p_usuario_id, 'gasto',   'Alimentación',         'utensils',        '#F97316', true, null),
    (p_usuario_id, 'gasto',   'Transporte',           'bus',             '#0EA5E9', true, null),
    (p_usuario_id, 'gasto',   'Combustible',          'fuel',            '#EAB308', true, null),
    (p_usuario_id, 'gasto',   'Vivienda',             'house',           '#8B5CF6', true, null),
    (p_usuario_id, 'gasto',   'Servicios públicos',   'plug-zap',        '#06B6D4', true, null),
    (p_usuario_id, 'gasto',   'Salud',                'heart-pulse',     '#EF4444', true, null),
    (p_usuario_id, 'gasto',   'Educación',            'graduation-cap',  '#3B82F6', true, null),
    (p_usuario_id, 'gasto',   'Entretenimiento',      'clapperboard',    '#EC4899', true, null),
    (p_usuario_id, 'gasto',   'Suscripciones',        'repeat',          '#A855F7', true, null),
    (p_usuario_id, 'gasto',   'Compras',              'shopping-bag',    '#F43F5E', true, null),
    (p_usuario_id, 'gasto',   'Deudas',               'credit-card',     '#DC2626', true, null),
    (p_usuario_id, 'gasto',   'Comisiones bancarias', 'landmark',        '#64748B', true, 'comisiones_bancarias'),
    (p_usuario_id, 'gasto',   'Otros gastos',         'circle-ellipsis', '#78716C', true, null),
    (p_usuario_id, 'ingreso', 'Salario',              'briefcase',       '#16A34A', true, null),
    (p_usuario_id, 'ingreso', 'Bonificaciones',       'gift',            '#22C55E', true, null),
    (p_usuario_id, 'ingreso', 'Intereses',            'percent',         '#10B981', true, null),
    (p_usuario_id, 'ingreso', 'Ventas',               'store',           '#14B8A6', true, null),
    (p_usuario_id, 'ingreso', 'Ingresos adicionales', 'plus-circle',     '#84CC16', true, null),
    (p_usuario_id, 'ingreso', 'Otros ingresos',       'circle-ellipsis', '#65A30D', true, null)
  on conflict do nothing;

  insert into public.metodos_pago (usuario_id, nombre) values
    (p_usuario_id, 'Efectivo'),
    (p_usuario_id, 'Tarjeta de débito'),
    (p_usuario_id, 'Tarjeta de crédito'),
    (p_usuario_id, 'SINPE Móvil'),
    (p_usuario_id, 'Transferencia bancaria')
  on conflict do nothing;
end $$;

revoke execute on function public.sembrar_datos_usuario(uuid) from public, anon, authenticated;

-- Al registrarse un usuario en Supabase Auth se crean sus datos iniciales
create or replace function public.al_crear_usuario() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public.sembrar_datos_usuario(new.id);
  update public.perfiles set nombre_completo = new.raw_user_meta_data ->> 'full_name' where id = new.id;
  return new;
end $$;

create trigger al_crear_usuario after insert on auth.users
for each row execute function public.al_crear_usuario();
