-- App Ahorro: elimina la versión anterior (nombres en inglés) del esquema.
-- Ejecútalo SOLO si ya habías corrido el primer supabase-esquema.sql.
-- Borra todos los datos de la app (no toca los usuarios de Authentication).
drop trigger if exists on_auth_user_created on auth.users;

drop view if exists public.v_account_balances, public.v_monthly_summary, public.v_goal_progress cascade;

drop table if exists
  public.audit_log, public.budgets, public.goal_entries, public.savings_goals, public.transactions,
  public.recurring_occurrences, public.recurring_rules, public.transfers, public.payment_methods,
  public.categories, public.accounts, public.banks, public.exchange_rates, public.profiles, public.currencies
cascade;

drop function if exists
  public.handle_new_user(), public.seed_user_defaults(uuid), public.audit_changes(),
  public.create_transfer(uuid, uuid, numeric, timestamptz, text, numeric, numeric, numeric, uuid),
  public.update_transfer(uuid, numeric, timestamptz, text, numeric, numeric, numeric),
  public.void_transfer(uuid, text), public.bank_fee_category_id(),
  public.account_balance(uuid, timestamptz), public.fx_rate(char, char, date),
  public.validate_category(), public.validate_account_update(), public.validate_bank_update(),
  public.validate_transaction(), public.prevent_delete(), public.validate_goal(), public.validate_goal_entry(),
  public.validate_budget(), public.validate_recurring_rule(), public.set_updated_at()
cascade;

drop function if exists public.resolve_transfer_amounts cascade;

drop type if exists
  public.account_type, public.category_type, public.transaction_kind, public.record_status, public.goal_priority,
  public.goal_status, public.goal_entry_kind, public.recurring_frequency, public.recurring_mode, public.occurrence_status
cascade;
