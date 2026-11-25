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
