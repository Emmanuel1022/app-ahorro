-- =====================================================================
-- App Ahorro · Datos predeterminados
-- =====================================================================

insert into public.currencies (code, name, symbol, decimals) values
  ('CRC', 'Colón costarricense', '₡', 2),
  ('USD', 'Dólar estadounidense', '$', 2),
  ('EUR', 'Euro', '€', 2)
on conflict (code) do nothing;

-- Crea perfil, categorías y métodos de pago predeterminados de un usuario.
create or replace function public.seed_user_defaults(p_user_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, full_name)
  values (p_user_id, null)
  on conflict (id) do nothing;

  insert into public.categories (user_id, type, name, icon, color, is_default, system_key) values
    (p_user_id, 'expense', 'Alimentación',         'utensils',        '#F97316', true, null),
    (p_user_id, 'expense', 'Transporte',           'bus',             '#0EA5E9', true, null),
    (p_user_id, 'expense', 'Combustible',          'fuel',            '#EAB308', true, null),
    (p_user_id, 'expense', 'Vivienda',             'house',           '#8B5CF6', true, null),
    (p_user_id, 'expense', 'Servicios públicos',   'plug-zap',        '#06B6D4', true, null),
    (p_user_id, 'expense', 'Salud',                'heart-pulse',     '#EF4444', true, null),
    (p_user_id, 'expense', 'Educación',            'graduation-cap',  '#3B82F6', true, null),
    (p_user_id, 'expense', 'Entretenimiento',      'clapperboard',    '#EC4899', true, null),
    (p_user_id, 'expense', 'Suscripciones',        'repeat',          '#A855F7', true, null),
    (p_user_id, 'expense', 'Compras',              'shopping-bag',    '#F43F5E', true, null),
    (p_user_id, 'expense', 'Deudas',               'credit-card',     '#DC2626', true, null),
    (p_user_id, 'expense', 'Comisiones bancarias', 'landmark',        '#64748B', true, 'bank_fees'),
    (p_user_id, 'expense', 'Otros gastos',         'circle-ellipsis', '#78716C', true, null),
    (p_user_id, 'income',  'Salario',              'briefcase',       '#16A34A', true, null),
    (p_user_id, 'income',  'Bonificaciones',       'gift',            '#22C55E', true, null),
    (p_user_id, 'income',  'Intereses',            'percent',         '#10B981', true, null),
    (p_user_id, 'income',  'Ventas',               'store',           '#14B8A6', true, null),
    (p_user_id, 'income',  'Ingresos adicionales', 'plus-circle',     '#84CC16', true, null),
    (p_user_id, 'income',  'Otros ingresos',       'circle-ellipsis', '#65A30D', true, null)
  on conflict do nothing;

  insert into public.payment_methods (user_id, name) values
    (p_user_id, 'Efectivo'),
    (p_user_id, 'Tarjeta de débito'),
    (p_user_id, 'Tarjeta de crédito'),
    (p_user_id, 'SINPE Móvil'),
    (p_user_id, 'Transferencia bancaria')
  on conflict do nothing;
end $$;

revoke execute on function public.seed_user_defaults(uuid) from public, anon, authenticated;

-- Al registrarse un usuario en Supabase Auth se crean sus datos iniciales
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public.seed_user_defaults(new.id);
  update public.profiles set full_name = new.raw_user_meta_data ->> 'full_name' where id = new.id;
  return new;
end $$;

create trigger on_auth_user_created after insert on auth.users
for each row execute function public.handle_new_user();
