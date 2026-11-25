-- =====================================================================
-- App Ahorro · Reglas de negocio aplicadas en la base de datos
-- =====================================================================

-- ---------------------------------------------------------------------
-- Categorías: un nivel de subcategoría y mismo tipo que el padre
-- ---------------------------------------------------------------------
create or replace function public.validate_category() returns trigger
language plpgsql as $$
declare
  v_parent public.categories;
begin
  if new.parent_id is not null then
    select * into v_parent from public.categories where id = new.parent_id;
    if v_parent.parent_id is not null then
      raise exception 'Una subcategoría no puede tener subcategorías' using errcode = 'check_violation';
    end if;
    if v_parent.type <> new.type then
      raise exception 'La subcategoría debe ser del mismo tipo que su categoría' using errcode = 'check_violation';
    end if;
    if exists (select 1 from public.categories c where c.parent_id = new.id) then
      raise exception 'Una categoría con subcategorías no puede convertirse en subcategoría' using errcode = 'check_violation';
    end if;
  end if;

  if tg_op = 'UPDATE' and new.type <> old.type then
    if exists (select 1 from public.transactions t where t.category_id = new.id)
       or exists (select 1 from public.categories c where c.parent_id = new.id) then
      raise exception 'No se puede cambiar el tipo de una categoría con movimientos o subcategorías' using errcode = 'check_violation';
    end if;
  end if;

  if tg_op = 'UPDATE' and old.system_key is not null and new.system_key is distinct from old.system_key then
    raise exception 'No se puede cambiar la clave de sistema de una categoría' using errcode = 'check_violation';
  end if;
  return new;
end $$;

create trigger categories_validate before insert or update on public.categories
for each row execute function public.validate_category();

-- ---------------------------------------------------------------------
-- Cuentas: moneda y saldo inicial fijos cuando ya hay movimientos
-- ---------------------------------------------------------------------
create or replace function public.validate_account_update() returns trigger
language plpgsql as $$
begin
  if (new.currency <> old.currency or new.opening_balance <> old.opening_balance or new.opening_date <> old.opening_date)
     and exists (select 1 from public.transactions t where t.account_id = new.id) then
    raise exception 'La cuenta ya tiene movimientos: corrige el saldo con un movimiento de ajuste'
      using errcode = 'check_violation';
  end if;
  return new;
end $$;

create trigger accounts_validate_update before update on public.accounts
for each row execute function public.validate_account_update();

-- Un banco no se desactiva mientras tenga cuentas activas
create or replace function public.validate_bank_update() returns trigger
language plpgsql as $$
begin
  if old.is_active and not new.is_active
     and exists (select 1 from public.accounts a where a.bank_id = new.id and a.is_active) then
    raise exception 'Desactiva primero las cuentas activas de este banco' using errcode = 'check_violation';
  end if;
  return new;
end $$;

create trigger banks_validate_update before update on public.banks
for each row execute function public.validate_bank_update();

-- ---------------------------------------------------------------------
-- Movimientos
-- ---------------------------------------------------------------------
create or replace function public.validate_transaction() returns trigger
language plpgsql as $$
declare
  v_account  public.accounts;
  v_category public.categories;
  v_transfer_op boolean := coalesce(current_setting('app.transfer_op', true), '') = 'on';
begin
  -- Las piezas de una transferencia solo se tocan desde las funciones de transferencia
  if new.transfer_id is not null or (tg_op = 'UPDATE' and old.transfer_id is not null) then
    if not v_transfer_op then
      raise exception 'Los movimientos de una transferencia se modifican desde la transferencia'
        using errcode = 'check_violation';
    end if;
  end if;

  select * into v_account from public.accounts where id = new.account_id;
  if new.currency <> v_account.currency then
    raise exception 'La moneda del movimiento (%) debe ser la de la cuenta (%)', new.currency, v_account.currency
      using errcode = 'check_violation';
  end if;

  -- Cuenta y categoría activas al crear o al cambiarlas
  if tg_op = 'INSERT' or new.account_id <> old.account_id then
    if not v_account.is_active then
      raise exception 'La cuenta está inactiva' using errcode = 'check_violation';
    end if;
  end if;

  if new.category_id is not null then
    select * into v_category from public.categories where id = new.category_id;
    if (new.kind = 'income' and v_category.type <> 'income')
       or (new.kind = 'expense' and v_category.type <> 'expense') then
      raise exception 'La categoría no corresponde al tipo de movimiento' using errcode = 'check_violation';
    end if;
    if (tg_op = 'INSERT' or new.category_id is distinct from old.category_id) and not v_category.is_active then
      raise exception 'La categoría está inactiva' using errcode = 'check_violation';
    end if;
  end if;

  -- Una anulación se registra con fecha
  if new.status = 'voided' and new.voided_at is null then
    new.voided_at := now();
  elsif new.status = 'active' then
    new.voided_at := null;
    new.void_reason := null;
  end if;
  return new;
end $$;

create trigger transactions_validate before insert or update on public.transactions
for each row execute function public.validate_transaction();

-- Los movimientos no se borran físicamente: se anulan
create or replace function public.prevent_delete() returns trigger
language plpgsql as $$
begin
  raise exception 'Este registro no se elimina: anúlalo para conservar el historial' using errcode = 'check_violation';
end $$;

create trigger transactions_no_delete before delete on public.transactions
for each row execute function public.prevent_delete();
create trigger transfers_no_delete before delete on public.transfers
for each row execute function public.prevent_delete();

-- ---------------------------------------------------------------------
-- Saldos
-- ---------------------------------------------------------------------
create or replace function public.account_balance(p_account_id uuid, p_as_of timestamptz default null)
returns numeric
language sql stable security invoker as $$
  select a.opening_balance + coalesce(sum(t.direction * t.amount) filter (
           where t.status = 'active' and (p_as_of is null or t.occurred_at <= p_as_of)), 0)
  from public.accounts a
  left join public.transactions t on t.account_id = a.id
  where a.id = p_account_id
  group by a.id, a.opening_balance
$$;

-- ---------------------------------------------------------------------
-- Tipo de cambio de referencia: el más reciente vigente a la fecha.
-- Devuelve cuántas unidades de p_to vale 1 unidad de p_from, o null si no hay.
-- ---------------------------------------------------------------------
create or replace function public.fx_rate(p_from char(3), p_to char(3), p_on date default current_date)
returns table (rate numeric, effective_date date)
language sql stable security invoker as $$
  select r.rate, r.effective_date from (
    select 1::numeric as rate, p_on as effective_date, 0 as pri
    where p_from = p_to
    union all
    select x.rate, x.effective_date, 1
    from public.exchange_rates x
    where x.user_id = auth.uid() and x.base_currency = p_from and x.quote_currency = p_to and x.effective_date <= p_on
    union all
    select 1 / x.rate, x.effective_date, 1
    from public.exchange_rates x
    where x.user_id = auth.uid() and x.base_currency = p_to and x.quote_currency = p_from and x.effective_date <= p_on
  ) r
  order by r.pri, r.effective_date desc
  limit 1
$$;

-- ---------------------------------------------------------------------
-- Transferencias: todo en una sola transacción
-- ---------------------------------------------------------------------
create or replace function public.bank_fee_category_id() returns uuid
language plpgsql security invoker as $$
declare v_id uuid;
begin
  select id into v_id from public.categories where user_id = auth.uid() and system_key = 'bank_fees';
  if v_id is null then
    insert into public.categories (user_id, type, name, icon, color, is_default, system_key)
    values (auth.uid(), 'expense', 'Comisiones bancarias', 'landmark', '#64748B', true, 'bank_fees')
    returning id into v_id;
  end if;
  return v_id;
end $$;

create or replace function public.resolve_transfer_amounts(
  p_from public.accounts, p_to public.accounts,
  p_amount_sent numeric, p_amount_received numeric, p_exchange_rate numeric,
  out amount_received numeric, out exchange_rate numeric)
language plpgsql immutable as $$
begin
  if p_from.currency = p_to.currency then
    if p_amount_received is not null and p_amount_received <> p_amount_sent then
      raise exception 'En cuentas de la misma moneda el monto recibido debe ser igual al enviado'
        using errcode = 'check_violation';
    end if;
    amount_received := p_amount_sent;
    exchange_rate := null;
  else
    if p_amount_received is null and p_exchange_rate is null then
      raise exception 'Las cuentas tienen monedas distintas: indica el tipo de cambio o el monto recibido'
        using errcode = 'check_violation';
    end if;
    -- exchange_rate = unidades de la moneda destino por 1 unidad de la moneda origen
    amount_received := coalesce(p_amount_received, round(p_amount_sent * p_exchange_rate, 2));
    exchange_rate := coalesce(p_exchange_rate, round(p_amount_received / p_amount_sent, 6));
  end if;
end $$;

create or replace function public.create_transfer(
  p_from_account_id uuid,
  p_to_account_id   uuid,
  p_amount_sent     numeric,
  p_occurred_at     timestamptz default now(),
  p_description     text default null,
  p_amount_received numeric default null,
  p_exchange_rate   numeric default null,
  p_fee_amount      numeric default 0,
  p_idempotency_key uuid default null
) returns uuid
language plpgsql security invoker as $$
declare
  v_from public.accounts;
  v_to   public.accounts;
  v_id   uuid;
  v_amt  record;
  v_fee  numeric := coalesce(p_fee_amount, 0);
begin
  if p_idempotency_key is not null then
    select id into v_id from public.transfers where user_id = auth.uid() and idempotency_key = p_idempotency_key;
    if v_id is not null then return v_id; end if;
  end if;

  if p_from_account_id = p_to_account_id then
    raise exception 'La cuenta de origen y la de destino deben ser distintas' using errcode = 'check_violation';
  end if;
  if p_amount_sent is null or p_amount_sent <= 0 then
    raise exception 'El monto debe ser mayor que cero' using errcode = 'check_violation';
  end if;
  if v_fee < 0 then
    raise exception 'La comisión no puede ser negativa' using errcode = 'check_violation';
  end if;

  -- Bloquea ambas cuentas en orden fijo para evitar interbloqueos
  perform 1 from public.accounts where id in (p_from_account_id, p_to_account_id) order by id for update;
  select * into v_from from public.accounts where id = p_from_account_id;
  select * into v_to   from public.accounts where id = p_to_account_id;
  if v_from.id is null or v_to.id is null then
    raise exception 'Cuenta no encontrada' using errcode = 'foreign_key_violation';
  end if;

  select * into v_amt from public.resolve_transfer_amounts(v_from, v_to, p_amount_sent, p_amount_received, p_exchange_rate);

  perform set_config('app.transfer_op', 'on', true);

  insert into public.transfers (user_id, from_account_id, to_account_id, amount_sent, amount_received,
                                exchange_rate, fee_amount, occurred_at, description, idempotency_key)
  values (auth.uid(), v_from.id, v_to.id, p_amount_sent, v_amt.amount_received,
          v_amt.exchange_rate, v_fee, coalesce(p_occurred_at, now()), p_description, p_idempotency_key)
  returning id into v_id;

  insert into public.transactions (user_id, kind, direction, account_id, amount, currency, occurred_at, description, transfer_id)
  values (auth.uid(), 'transfer_out', -1, v_from.id, p_amount_sent, v_from.currency, coalesce(p_occurred_at, now()), p_description, v_id),
         (auth.uid(), 'transfer_in',   1, v_to.id,   v_amt.amount_received, v_to.currency, coalesce(p_occurred_at, now()), p_description, v_id);

  if v_fee > 0 then
    insert into public.transactions (user_id, kind, direction, account_id, category_id, amount, currency, occurred_at, description, transfer_id)
    values (auth.uid(), 'expense', -1, v_from.id, public.bank_fee_category_id(), v_fee, v_from.currency,
            coalesce(p_occurred_at, now()), 'Comisión de transferencia', v_id);
  end if;

  perform set_config('app.transfer_op', 'off', true);
  return v_id;
end $$;

create or replace function public.update_transfer(
  p_transfer_id     uuid,
  p_amount_sent     numeric,
  p_occurred_at     timestamptz,
  p_description     text default null,
  p_amount_received numeric default null,
  p_exchange_rate   numeric default null,
  p_fee_amount      numeric default 0
) returns uuid
language plpgsql security invoker as $$
declare
  v_tr   public.transfers;
  v_from public.accounts;
  v_to   public.accounts;
  v_amt  record;
  v_fee  numeric := coalesce(p_fee_amount, 0);
begin
  select * into v_tr from public.transfers where id = p_transfer_id for update;
  if v_tr.id is null then
    raise exception 'Transferencia no encontrada' using errcode = 'no_data_found';
  end if;
  if v_tr.status = 'voided' then
    raise exception 'La transferencia está anulada' using errcode = 'check_violation';
  end if;
  if p_amount_sent is null or p_amount_sent <= 0 then
    raise exception 'El monto debe ser mayor que cero' using errcode = 'check_violation';
  end if;
  if v_fee < 0 then
    raise exception 'La comisión no puede ser negativa' using errcode = 'check_violation';
  end if;

  select * into v_from from public.accounts where id = v_tr.from_account_id;
  select * into v_to   from public.accounts where id = v_tr.to_account_id;
  select * into v_amt from public.resolve_transfer_amounts(v_from, v_to, p_amount_sent, p_amount_received, p_exchange_rate);

  perform set_config('app.transfer_op', 'on', true);

  update public.transfers
     set amount_sent = p_amount_sent, amount_received = v_amt.amount_received, exchange_rate = v_amt.exchange_rate,
         fee_amount = v_fee, occurred_at = p_occurred_at, description = p_description
   where id = v_tr.id;

  update public.transactions set amount = p_amount_sent, occurred_at = p_occurred_at, description = p_description
   where transfer_id = v_tr.id and kind = 'transfer_out';
  update public.transactions set amount = v_amt.amount_received, occurred_at = p_occurred_at, description = p_description
   where transfer_id = v_tr.id and kind = 'transfer_in';

  if v_fee > 0 then
    update public.transactions set amount = v_fee, occurred_at = p_occurred_at, status = 'active'
     where transfer_id = v_tr.id and kind = 'expense';
    if not found then
      insert into public.transactions (user_id, kind, direction, account_id, category_id, amount, currency, occurred_at, description, transfer_id)
      values (v_tr.user_id, 'expense', -1, v_from.id, public.bank_fee_category_id(), v_fee, v_from.currency,
              p_occurred_at, 'Comisión de transferencia', v_tr.id);
    end if;
  else
    update public.transactions set status = 'voided', void_reason = 'Comisión eliminada'
     where transfer_id = v_tr.id and kind = 'expense' and status = 'active';
  end if;

  perform set_config('app.transfer_op', 'off', true);
  return v_tr.id;
end $$;

create or replace function public.void_transfer(p_transfer_id uuid, p_reason text default null)
returns void
language plpgsql security invoker as $$
begin
  perform set_config('app.transfer_op', 'on', true);
  update public.transfers set status = 'voided', voided_at = now(), void_reason = p_reason
   where id = p_transfer_id and status = 'active';
  if not found then
    raise exception 'Transferencia no encontrada o ya anulada' using errcode = 'no_data_found';
  end if;
  update public.transactions set status = 'voided', void_reason = p_reason
   where transfer_id = p_transfer_id and status = 'active';
  perform set_config('app.transfer_op', 'off', true);
end $$;

-- ---------------------------------------------------------------------
-- Metas: los retiros no pueden dejar el acumulado en negativo;
-- la moneda de la meta es la de su cuenta asociada.
-- ---------------------------------------------------------------------
create or replace function public.validate_goal() returns trigger
language plpgsql as $$
declare v_currency char(3);
begin
  if new.account_id is not null then
    select currency into v_currency from public.accounts where id = new.account_id;
    if v_currency <> new.currency then
      raise exception 'La meta debe estar en la moneda de su cuenta asociada (%)', v_currency using errcode = 'check_violation';
    end if;
  end if;
  return new;
end $$;

create trigger savings_goals_validate before insert or update on public.savings_goals
for each row execute function public.validate_goal();

create or replace function public.validate_goal_entry() returns trigger
language plpgsql as $$
declare v_total numeric;
begin
  if new.status = 'voided' and new.voided_at is null then new.voided_at := now(); end if;
  if new.status = 'active' then new.voided_at := null; end if;

  select coalesce(sum(case when e.kind = 'contribution' then e.amount else -e.amount end), 0)
    into v_total
    from public.goal_entries e
   where e.goal_id = new.goal_id and e.status = 'active' and e.id <> new.id;

  if new.status = 'active' then
    v_total := v_total + case when new.kind = 'contribution' then new.amount else -new.amount end;
  end if;
  if v_total < 0 then
    raise exception 'El retiro supera el monto acumulado de la meta' using errcode = 'check_violation';
  end if;
  return new;
end $$;

create trigger goal_entries_validate before insert or update on public.goal_entries
for each row execute function public.validate_goal_entry();

-- ---------------------------------------------------------------------
-- Presupuestos: solo categorías de gasto de primer nivel
-- ---------------------------------------------------------------------
create or replace function public.validate_budget() returns trigger
language plpgsql as $$
declare v_cat public.categories;
begin
  select * into v_cat from public.categories where id = new.category_id;
  if v_cat.type <> 'expense' or v_cat.parent_id is not null then
    raise exception 'Los presupuestos se definen por categoría de gasto principal' using errcode = 'check_violation';
  end if;
  return new;
end $$;

create trigger budgets_validate before insert or update on public.budgets
for each row execute function public.validate_budget();

-- ---------------------------------------------------------------------
-- Reglas recurrentes: categoría acorde al tipo
-- ---------------------------------------------------------------------
create or replace function public.validate_recurring_rule() returns trigger
language plpgsql as $$
declare v_type public.category_type;
begin
  select type into v_type from public.categories where id = new.category_id;
  if v_type <> new.kind then
    raise exception 'La categoría no corresponde al tipo de la regla' using errcode = 'check_violation';
  end if;
  return new;
end $$;

create trigger recurring_rules_validate before insert or update on public.recurring_rules
for each row execute function public.validate_recurring_rule();
