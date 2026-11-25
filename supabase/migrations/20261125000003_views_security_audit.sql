-- =====================================================================
-- App Ahorro · Vistas calculadas, seguridad por usuario (RLS) y auditoría
-- =====================================================================

-- ---------------------------------------------------------------------
-- Vistas (security_invoker: respetan RLS del usuario que consulta)
-- ---------------------------------------------------------------------
create view public.v_account_balances with (security_invoker = true) as
select a.id            as account_id,
       a.user_id,
       a.bank_id,
       b.name          as bank_name,
       b.color         as bank_color,
       a.name,
       a.type,
       a.currency,
       a.opening_balance,
       a.is_active,
       a.include_in_total,
       a.opening_balance + coalesce(sum(t.direction * t.amount) filter (where t.status = 'active'), 0) as current_balance,
       max(t.occurred_at) filter (where t.status = 'active') as last_movement_at
from public.accounts a
join public.banks b on b.id = a.bank_id
left join public.transactions t on t.account_id = a.id
group by a.id, b.id;

-- Ingresos y gastos por mes y moneda original (sin transferencias ni ajustes)
create view public.v_monthly_summary with (security_invoker = true) as
select t.user_id,
       date_trunc('month', t.occurred_at at time zone coalesce(p.timezone, 'America/Costa_Rica'))::date as month,
       t.currency,
       coalesce(sum(t.amount) filter (where t.kind = 'income'), 0)  as income,
       coalesce(sum(t.amount) filter (where t.kind = 'expense'), 0) as expense,
       coalesce(sum(t.amount) filter (where t.kind = 'income'), 0)
         - coalesce(sum(t.amount) filter (where t.kind = 'expense'), 0) as balance
from public.transactions t
left join public.profiles p on p.id = t.user_id
where t.status = 'active' and t.kind in ('income', 'expense')
group by t.user_id, 2, t.currency;

create view public.v_goal_progress with (security_invoker = true) as
select g.id as goal_id,
       g.user_id,
       g.name,
       g.target_amount,
       g.currency,
       g.target_date,
       g.account_id,
       g.priority,
       g.status,
       coalesce(sum(case when e.kind = 'contribution' then e.amount else -e.amount end)
                filter (where e.status = 'active'), 0) as accumulated,
       round(100 * coalesce(sum(case when e.kind = 'contribution' then e.amount else -e.amount end)
                filter (where e.status = 'active'), 0) / g.target_amount, 2) as progress_pct
from public.savings_goals g
left join public.goal_entries e on e.goal_id = g.id
group by g.id;

-- ---------------------------------------------------------------------
-- Row Level Security: cada usuario solo ve y modifica lo suyo
-- ---------------------------------------------------------------------
alter table public.currencies enable row level security;
create policy currencies_read on public.currencies for select to authenticated using (true);

alter table public.profiles enable row level security;
create policy profiles_own on public.profiles for all to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

do $$
declare t text;
begin
  foreach t in array array['exchange_rates', 'banks', 'accounts', 'categories', 'payment_methods', 'transfers',
                           'recurring_rules', 'recurring_occurrences', 'transactions', 'savings_goals',
                           'goal_entries', 'budgets']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy %I on public.%I for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid())',
                   t || '_own', t);
  end loop;
end $$;

alter table public.audit_log enable row level security;
create policy audit_log_read_own on public.audit_log for select to authenticated using (user_id = auth.uid());
revoke insert, update, delete on public.audit_log from authenticated, anon;

-- ---------------------------------------------------------------------
-- Auditoría: un trigger genérico guarda el antes y el después
-- ---------------------------------------------------------------------
create or replace function public.audit_changes() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_action text;
  v_old jsonb := case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) end;
  v_new jsonb := case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) end;
  v_row jsonb := coalesce(v_new, v_old);
begin
  v_action := lower(tg_op);
  if tg_op = 'UPDATE' then
    if v_old = v_new then return null; end if;
    if v_old ? 'status' and v_old ->> 'status' = 'active' and v_new ->> 'status' = 'voided' then
      v_action := 'void';
    elsif v_old ? 'status' and v_old ->> 'status' = 'voided' and v_new ->> 'status' = 'active' then
      v_action := 'restore';
    end if;
  end if;

  insert into public.audit_log (user_id, table_name, record_id, action, old_data, new_data)
  values (coalesce((v_row ->> 'user_id')::uuid, (v_row ->> 'id')::uuid), tg_table_name, (v_row ->> 'id')::uuid,
          v_action, v_old, v_new);
  return null;
end $$;

do $$
declare t text;
begin
  foreach t in array array['profiles', 'exchange_rates', 'banks', 'accounts', 'categories', 'payment_methods',
                           'transfers', 'recurring_rules', 'transactions', 'savings_goals', 'goal_entries', 'budgets']
  loop
    execute format('create trigger %I after insert or update or delete on public.%I for each row execute function public.audit_changes()',
                   t || '_audit', t);
  end loop;
end $$;
