/** Rutas accesibles sin sesión. */
export const PUBLIC_PATHS = ["/login", "/registro", "/recuperar", "/auth/callback", "/configurar"];

/** Rutas de autenticación: con sesión iniciada redirigen al inicio. */
export const AUTH_ONLY_PATHS = ["/login", "/registro", "/recuperar"];

export const HOME_PATH = "/inicio";

export const isPublicPath = (pathname: string) =>
  PUBLIC_PATHS.some((p) => pathname === p || pathname.startsWith(`${p}/`));

/** Evita redirecciones abiertas: solo rutas internas. */
export function safeNext(next: string | null | undefined): string {
  if (!next || !next.startsWith("/") || next.startsWith("//") || next.startsWith("/\\")) return HOME_PATH;
  return next;
}
