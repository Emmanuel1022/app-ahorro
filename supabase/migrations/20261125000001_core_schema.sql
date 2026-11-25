-- =====================================================================
-- App Ahorro · Esquema principal
-- Montos: NUMERIC(18,2). Tipos de cambio: NUMERIC(18,6).
-- El saldo de una cuenta NO se guarda: se calcula en v_account_balances.
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- Tipos enumerados
-- ---------------------------------------------------------------------
create type public.account_type        as enum ('savings', 'checking', 'cash', 'investment', 'other');
create type public.category_type       as enum ('income', 'expense');
create type public.transaction_kind    as enum ('income', 'expense', 'transfer_out', 'transfer_in', 'adjustment');
create type public.record_status       as enum ('active', 'voided');
create type public.goal_priority       as enum ('high', 'medium', 'low');
create type public.goal_status         as enum ('active', 'paused', 'completed', 'cancelled');
create type public.goal_entry_kind     as enum ('contribution', 'withdrawal');
create type public.recurring_frequency as enum ('weekly', 'biweekly', 'monthly', 'yearly');
create type public.recurring_mode      as enum ('automatic', 'confirm');
create type public.occurrence_status   as enum ('pending', 'registered', 'skipped');

-- ---------------------------------------------------------------------
-- Utilidades
-- ---------------------------------------------------------------------
create or replace function public.set_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

-- ---------------------------------------------------------------------
-- Catálogo global de monedas
-- ---------------------------------------------------------------------
create table public.currencies (
  code      char(3) primary key check (code ~ '^[A-Z]{3}$'),
  name      text not null,
  symbol    text not null,
  decimals  smallint not null default 2 check (decimals between 0 and 4)
);

-- ---------------------------------------------------------------------
-- Perfil del usuario (1 a 1 con auth.users)
-- ---------------------------------------------------------------------
create table public.profiles (
  id            uuid primary key references auth.users (id) on delete cascade,
  full_name     text,
  base_currency char(3) not null default 'CRC' references public.currencies (code),
  timezone      text not null default 'America/Costa_Rica',
  hide_amounts  boolean not null default false,
  theme         text not null default 'system' check (theme in ('light', 'dark', 'system')),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Tipos de cambio: 1 base_currency = rate quote_currency, vigente desde effective_date
-- ---------------------------------------------------------------------
create table public.exchange_rates (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null default auth.uid() references auth.users (id) on delete cascade,
  base_currency  char(3) not null references public.currencies (code),
  quote_currency char(3) not null references public.currencies (code),
  rate           numeric(18, 6) not null check (rate > 0),
  effective_date date not null,
  source         text not null default 'manual',
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  check (base_currency <> quote_currency),
  unique (user_id, base_currency, quote_currency, effective_date)
);

-- ---------------------------------------------------------------------
-- Bancos
-- ---------------------------------------------------------------------
create table public.banks (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name        text not null check (char_length(btrim(name)) between 1 and 100),
  logo_url    text,
  icon        text,
  color       text check (color is null or color ~ '^#[0-9A-Fa-f]{6}$'),
  description text,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (id, user_id)
);
create unique index banks_user_name_uq on public.banks (user_id, lower(btrim(name)));

-- ---------------------------------------------------------------------
-- Cuentas bancarias
-- ---------------------------------------------------------------------
create table public.accounts (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null default auth.uid() references auth.users (id) on delete cascade,
  bank_id          uuid not null,
  name             text not null check (char_length(btrim(name)) between 1 and 100),
  account_number   text,
  type             public.account_type not null default 'savings',
  currency         char(3) not null references public.currencies (code),
  opening_balance  numeric(18, 2) not null default 0,
  opening_date     date not null default current_date,
  description      text,
  is_active        boolean not null default true,
  include_in_total boolean not null default true,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique (id, user_id),
  foreign key (bank_id, user_id) references public.banks (id, user_id) on delete restrict
);
create unique index accounts_user_bank_name_uq on public.accounts (user_id, bank_id, lower(btrim(name)));
create index accounts_bank_idx on public.accounts (bank_id);

-- ---------------------------------------------------------------------
-- Categorías y subcategorías (un solo nivel de anidación)
-- ---------------------------------------------------------------------
create table public.categories (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
  parent_id   uuid,
  type        public.category_type not null,
  name        text not null check (char_length(btrim(name)) between 1 and 60),
  icon        text,
  color       text check (color is null or color ~ '^#[0-9A-Fa-f]{6}$'),
  description text,
  is_active   boolean not null default true,
  is_default  boolean not null default false,
  system_key  text,  -- marca categorías que usa el sistema (p. ej. 'bank_fees')
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (id, user_id),
  check (parent_id is null or parent_id <> id),
  foreign key (parent_id, user_id) references public.categories (id, user_id) on delete restrict
);
create unique index categories_user_parent_name_uq
  on public.categories (user_id, coalesce(parent_id, '00000000-0000-0000-0000-000000000000'::uuid), type, lower(btrim(name)));
create unique index categories_user_system_key_uq on public.categories (user_id, system_key) where system_key is not null;

-- ---------------------------------------------------------------------
-- Métodos de pago
-- ---------------------------------------------------------------------
create table public.payment_methods (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name       text not null check (char_length(btrim(name)) between 1 and 60),
  is_active  boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, user_id)
);
create unique index payment_methods_user_name_uq on public.payment_methods (user_id, lower(btrim(name)));

-- ---------------------------------------------------------------------
-- Transferencias entre cuentas propias (agrupan 2 o 3 movimientos)
-- ---------------------------------------------------------------------
create table public.transfers (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null default auth.uid() references auth.users (id) on delete cascade,
  from_account_id uuid not null,
  to_account_id   uuid not null,
  amount_sent     numeric(18, 2) not null check (amount_sent > 0),
  amount_received numeric(18, 2) not null check (amount_received > 0),
  exchange_rate   numeric(18, 6) check (exchange_rate is null or exchange_rate > 0),
  fee_amount      numeric(18, 2) not null default 0 check (fee_amount >= 0),
  occurred_at     timestamptz not null default now(),
  description     text,
  status          public.record_status not null default 'active',
  voided_at       timestamptz,
  void_reason     text,
  idempotency_key uuid,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (id, user_id),
  check (from_account_id <> to_account_id),
  check ((status = 'voided') = (voided_at is not null)),
  foreign key (from_account_id, user_id) references public.accounts (id, user_id) on delete restrict,
  foreign key (to_account_id, user_id)   references public.accounts (id, user_id) on delete restrict
);
create unique index transfers_idempotency_uq on public.transfers (user_id, idempotency_key) where idempotency_key is not null;
create index transfers_user_date_idx on public.transfers (user_id, occurred_at desc);

-- ---------------------------------------------------------------------
-- Movimientos recurrentes
-- ---------------------------------------------------------------------
create table public.recurring_rules (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null default auth.uid() references auth.users (id) on delete cascade,
  kind              public.category_type not null,
  account_id        uuid not null,
  category_id       uuid not null,
  amount            numeric(18, 2) not null check (amount > 0),
  description       text not null check (char_length(btrim(description)) between 1 and 200),
  payment_method_id uuid,
  frequency         public.recurring_frequency not null,
  start_date        date not null,
  end_date          date,
  next_due_date     date not null,
  mode              public.recurring_mode not null default 'confirm',
  is_active         boolean not null default true,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  unique (id, user_id),
  check (end_date is null or end_date >= start_date),
  foreign key (account_id, user_id)        references public.accounts (id, user_id) on delete restrict,
  foreign key (category_id, user_id)       references public.categories (id, user_id) on delete restrict,
  foreign key (payment_method_id, user_id) references public.payment_methods (id, user_id) on delete restrict
);

create table public.recurring_occurrences (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  rule_id    uuid not null,
  due_date   date not null,
  status     public.occurrence_status not null default 'pending',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, user_id),
  unique (rule_id, due_date),  -- imposible generar la misma ocurrencia dos veces
  foreign key (rule_id, user_id) references public.recurring_rules (id, user_id) on delete cascade
);

-- ---------------------------------------------------------------------
-- Movimientos: el libro mayor
-- ---------------------------------------------------------------------
create table public.transactions (
  id                      uuid primary key default gen_random_uuid(),
  user_id                 uuid not null default auth.uid() references auth.users (id) on delete cascade,
  kind                    public.transaction_kind not null,
  direction               smallint not null check (direction in (-1, 1)),
  account_id              uuid not null,
  category_id             uuid,
  amount                  numeric(18, 2) not null check (amount > 0),
  currency                char(3) not null references public.currencies (code),
  occurred_at             timestamptz not null default now(),
  description             text,
  reference               text,
  payment_method_id       uuid,
  attachment_path         text,
  notes                   text,
  transfer_id             uuid,
  recurring_occurrence_id uuid unique,
  status                  public.record_status not null default 'active',
  voided_at               timestamptz,
  void_reason             text,
  idempotency_key         uuid,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  check ((status = 'voided') = (voided_at is not null)),
  check (
       (kind = 'income'       and direction =  1 and category_id is not null)
    or (kind = 'expense'      and direction = -1 and category_id is not null)
    or (kind = 'transfer_out' and direction = -1 and category_id is null and transfer_id is not null)
    or (kind = 'transfer_in'  and direction =  1 and category_id is null and transfer_id is not null)
    or (kind = 'adjustment'   and category_id is null and transfer_id is null
        and description is not null and char_length(btrim(description)) > 0)
  ),
  foreign key (account_id, user_id)              references public.accounts (id, user_id) on delete restrict,
  foreign key (category_id, user_id)             references public.categories (id, user_id) on delete restrict,
  foreign key (payment_method_id, user_id)       references public.payment_methods (id, user_id) on delete restrict,
  foreign key (transfer_id, user_id)             references public.transfers (id, user_id) on delete restrict,
  foreign key (recurring_occurrence_id, user_id) references public.recurring_occurrences (id, user_id) on delete restrict
);
create unique index transactions_idempotency_uq on public.transactions (user_id, idempotency_key) where idempotency_key is not null;
create index transactions_account_status_idx on public.transactions (account_id, status);
create index transactions_user_date_idx      on public.transactions (user_id, occurred_at desc);
create index transactions_category_idx       on public.transactions (category_id);
create index transactions_transfer_idx       on public.transactions (transfer_id);

-- ---------------------------------------------------------------------
-- Metas de ahorro (apartados: no mueven dinero)
-- ---------------------------------------------------------------------
create table public.savings_goals (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name          text not null check (char_length(btrim(name)) between 1 and 100),
  target_amount numeric(18, 2) not null check (target_amount > 0),
  currency      char(3) not null references public.currencies (code),
  target_date   date,
  account_id    uuid,
  priority      public.goal_priority not null default 'medium',
  description   text,
  status        public.goal_status not null default 'active',
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (id, user_id),
  foreign key (account_id, user_id) references public.accounts (id, user_id) on delete restrict
);

create table public.goal_entries (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
  goal_id     uuid not null,
  kind        public.goal_entry_kind not null,
  amount      numeric(18, 2) not null check (amount > 0),
  entry_date  date not null default current_date,
  note        text,
  status      public.record_status not null default 'active',
  voided_at   timestamptz,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  check ((status = 'voided') = (voided_at is not null)),
  foreign key (goal_id, user_id) references public.savings_goals (id, user_id) on delete cascade
);
create index goal_entries_goal_idx on public.goal_entries (goal_id);

-- ---------------------------------------------------------------------
-- Presupuestos mensuales por categoría de gasto
-- ---------------------------------------------------------------------
create table public.budgets (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
  category_id uuid not null,
  month       date not null check (extract(day from month) = 1),
  amount      numeric(18, 2) not null check (amount > 0),
  currency    char(3) not null references public.currencies (code),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  unique (user_id, category_id, month),
  foreign key (category_id, user_id) references public.categories (id, user_id) on delete restrict
);

-- ---------------------------------------------------------------------
-- Historial de modificaciones
-- ---------------------------------------------------------------------
create table public.audit_log (
  id          bigint generated always as identity primary key,
  user_id     uuid,  -- sin FK: el historial sobrevive aunque cambien los registros
  table_name  text not null,
  record_id   uuid,
  action      text not null check (action in ('insert', 'update', 'delete', 'void', 'restore')),
  old_data    jsonb,
  new_data    jsonb,
  changed_at  timestamptz not null default now()
);
create index audit_log_record_idx on public.audit_log (table_name, record_id);
create index audit_log_user_idx   on public.audit_log (user_id, changed_at desc);

-- ---------------------------------------------------------------------
-- updated_at automático
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['profiles', 'exchange_rates', 'banks', 'accounts', 'categories', 'payment_methods',
                           'transfers', 'recurring_rules', 'recurring_occurrences', 'transactions',
                           'savings_goals', 'goal_entries', 'budgets']
  loop
    execute format('create trigger %I before update on public.%I for each row execute function public.set_updated_at()',
                   t || '_set_updated_at', t);
  end loop;
end $$;
