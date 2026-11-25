import { redirect } from "next/navigation";
import { AppShell } from "@/components/layout/app-shell";
import { getCurrentUser } from "@/lib/supabase/server";

export default async function AppLayout({ children }: { children: React.ReactNode }) {
  // El middleware ya protege estas rutas; esta verificación es una segunda barrera.
  const user = await getCurrentUser();
  if (!user) redirect("/login");
  const name = typeof user.user_metadata?.full_name === "string" ? user.user_metadata.full_name : "";
  return <AppShell user={{ name, email: user.email ?? "" }}>{children}</AppShell>;
}
