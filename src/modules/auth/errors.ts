/** Traduce errores de Supabase Auth a mensajes en español, sin revelar si una cuenta existe. */
export function authErrorMessage(error: { message?: string; code?: string; status?: number } | null | undefined): string {
  if (!error) return "Ocurrió un error inesperado. Intenta de nuevo.";
  const msg = (error.message ?? "").toLowerCase();
  const code = error.code ?? "";
  if (code === "invalid_credentials" || msg.includes("invalid login credentials")) return "Correo o contraseña incorrectos.";
  if (code === "email_not_confirmed" || msg.includes("email not confirmed"))
    return "Confirma tu correo antes de iniciar sesión. Revisa tu bandeja de entrada.";
  if (code === "over_request_rate_limit" || code === "over_email_send_rate_limit" || error.status === 429)
    return "Demasiados intentos. Espera unos minutos e intenta de nuevo.";
  if (code === "weak_password" || msg.includes("weak password")) return "La contraseña es demasiado débil.";
  if (code === "same_password") return "La nueva contraseña debe ser distinta de la anterior.";
  if (msg.includes("fetch failed") || msg.includes("network") || msg.includes("econnrefused") || error.status === 0)
    return "No se pudo conectar con el servidor. Revisa tu conexión e intenta de nuevo.";
  return "No se pudo completar la operación. Intenta de nuevo.";
}
