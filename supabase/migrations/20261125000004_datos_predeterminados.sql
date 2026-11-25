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
