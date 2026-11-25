import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";
import { AUTH_ONLY_PATHS, HOME_PATH, isPublicPath } from "@/config/routes";
import { getSupabaseEnv } from "./env";

/**
 * Refresca la sesión en cada petición y protege las rutas de la app.
 * Sin sesión → /login?next=<ruta>. Con sesión en /login, /registro o /recuperar → /inicio.
 */
export async function updateSession(request: NextRequest) {
  const { pathname, search } = request.nextUrl;
  const env = getSupabaseEnv();

  if (!env) {
    if (pathname === "/configurar") return NextResponse.next();
    const url = request.nextUrl.clone();
    url.pathname = "/configurar";
    url.search = "";
    return NextResponse.redirect(url);
  }

  let response = NextResponse.next({ request });
  const supabase = createServerClient(env.url, env.anonKey, {
    cookies: {
      getAll: () => request.cookies.getAll(),
      setAll: (toSet) => {
        toSet.forEach(({ name, value }) => request.cookies.set(name, value));
        response = NextResponse.next({ request });
        toSet.forEach(({ name, value, options }) => response.cookies.set(name, value, options));
      },
    },
  });

  let user = null;
  try {
    const { data } = await supabase.auth.getUser();
    user = data.user;
  } catch {
    user = null; // Si Auth no responde, se trata como sin sesión.
  }

  const redirectTo = (path: string, params?: Record<string, string>) => {
    const url = request.nextUrl.clone();
    url.pathname = path;
    url.search = params ? `?${new URLSearchParams(params)}` : "";
    const r = NextResponse.redirect(url);
    response.cookies.getAll().forEach((c) => r.cookies.set(c));
    return r;
  };

  if (!user && !isPublicPath(pathname)) {
    return redirectTo("/login", pathname === "/" ? undefined : { next: pathname + search });
  }
  if (user && (AUTH_ONLY_PATHS.includes(pathname) || pathname === "/")) {
    return redirectTo(HOME_PATH);
  }
  return response;
}
