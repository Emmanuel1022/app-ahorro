"use server";

import { headers } from "next/headers";
import { redirect } from "next/navigation";
import { safeNext } from "@/config/routes";
import { createClient } from "@/lib/supabase/server";
import { authErrorMessage } from "./errors";
import {
  formToObject,
  resetRequestSchema,
  signInSchema,
  signUpSchema,
  toFieldErrors,
  updatePasswordSchema,
  type FormState,
} from "./schemas";

async function siteOrigin() {
  if (process.env.NEXT_PUBLIC_SITE_URL) return process.env.NEXT_PUBLIC_SITE_URL.replace(/\/$/, "");
  const h = await headers();
  const host = h.get("x-forwarded-host") ?? h.get("host") ?? "localhost:3000";
  const proto = h.get("x-forwarded-proto") ?? (host.startsWith("localhost") ? "http" : "https");
  return `${proto}://${host}`;
}

async function callSafely<T>(fn: () => Promise<T>): Promise<T | { error: { message: string; status: number } }> {
  try {
    return await fn();
  } catch (e) {
    return { error: { message: e instanceof Error ? e.message : "network", status: 0 } };
  }
}

export async function signIn(_prev: FormState, formData: FormData): Promise<FormState> {
  const parsed = signInSchema.safeParse(formToObject(formData));
  if (!parsed.success) return { fieldErrors: toFieldErrors(parsed.error) };

  const supabase = await createClient();
  const res = await callSafely(() => supabase.auth.signInWithPassword(parsed.data));
  if (res.error) return { error: authErrorMessage(res.error) };

  redirect(safeNext(formData.get("next")?.toString()));
}

export async function signUp(_prev: FormState, formData: FormData): Promise<FormState> {
  const parsed = signUpSchema.safeParse(formToObject(formData));
  if (!parsed.success) return { fieldErrors: toFieldErrors(parsed.error) };

  const supabase = await createClient();
  const origin = await siteOrigin();
  const res = await callSafely(() =>
    supabase.auth.signUp({
      email: parsed.data.email,
      password: parsed.data.password,
      options: {
        data: { full_name: parsed.data.fullName },
        emailRedirectTo: `${origin}/auth/callback?next=/inicio`,
      },
    }),
  );
  if (res.error) return { error: authErrorMessage(res.error) };

  // Si la confirmación por correo está desactivada, ya hay sesión
  if ("data" in res && res.data.session) redirect("/inicio");
  return {
    ok: true,
    message: "Te enviamos un correo para confirmar tu cuenta. Abre el enlace para empezar a usar la app.",
  };
}

export async function requestPasswordReset(_prev: FormState, formData: FormData): Promise<FormState> {
  const parsed = resetRequestSchema.safeParse(formToObject(formData));
  if (!parsed.success) return { fieldErrors: toFieldErrors(parsed.error) };

  const supabase = await createClient();
  const origin = await siteOrigin();
  const res = await callSafely(() =>
    supabase.auth.resetPasswordForEmail(parsed.data.email, {
      redirectTo: `${origin}/auth/callback?next=/actualizar-contrasena`,
    }),
  );
  // Solo se informa de fallos de conexión o límite: nunca si el correo existe o no.
  if (res.error && (res.error.status === 0 || res.error.status === 429)) return { error: authErrorMessage(res.error) };
  return {
    ok: true,
    message: "Si el correo está registrado, recibirás un enlace para crear una nueva contraseña.",
  };
}

export async function updatePassword(_prev: FormState, formData: FormData): Promise<FormState> {
  const parsed = updatePasswordSchema.safeParse(formToObject(formData));
  if (!parsed.success) return { fieldErrors: toFieldErrors(parsed.error) };

  const supabase = await createClient();
  const res = await callSafely(() => supabase.auth.updateUser({ password: parsed.data.password }));
  if (res.error) return { error: authErrorMessage(res.error) };

  redirect("/inicio?contrasena=actualizada");
}

export async function signOut() {
  const supabase = await createClient();
  await callSafely(() => supabase.auth.signOut());
  redirect("/login");
}
