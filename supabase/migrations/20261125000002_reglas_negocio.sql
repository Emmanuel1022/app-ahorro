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
