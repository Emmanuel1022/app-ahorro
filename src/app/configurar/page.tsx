import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { Brand } from "@/components/layout/brand";
import { isSupabaseConfigured } from "@/lib/supabase/env";

export const metadata: Metadata = { title: "Configuración pendiente" };
export const dynamic = "force-dynamic";

export default function ConfigurePage() {
  if (isSupabaseConfigured()) redirect("/login");
  return (
    <main className="mx-auto flex min-h-dvh max-w-lg flex-col justify-center gap-6 px-4">
      <Brand />
      <div className="rounded-2xl border border-border bg-surface p-6 shadow-sm">
        <h1 className="text-lg font-semibold">Falta conectar la base de datos</h1>
        <p className="mt-2 text-sm text-muted">
          Crea el archivo <code className="rounded bg-surface-muted px-1">.env.local</code> a partir de{" "}
          <code className="rounded bg-surface-muted px-1">.env.example</code> con la URL y la clave pública (anon) de tu
          proyecto Supabase, y reinicia la aplicación.
        </p>
      </div>
    </main>
  );
}
