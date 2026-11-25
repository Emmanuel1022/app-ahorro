import type { Metadata } from "next";
import { AuthCard } from "../auth-card";
import { LoginForm } from "./login-form";

export const metadata: Metadata = { title: "Iniciar sesión" };

export default async function LoginPage({ searchParams }: { searchParams: Promise<Record<string, string | undefined>> }) {
  const { next, error } = await searchParams;
  return (
    <AuthCard title="Iniciar sesión" description="Bienvenido de nuevo. Ingresa para ver tus finanzas.">
      {error === "enlace" && (
        <p className="mb-4 rounded-lg bg-warning-soft px-3 py-2 text-sm text-warning" role="alert">
          El enlace no es válido o ya expiró. Solicita uno nuevo.
        </p>
      )}
      <LoginForm next={next} />
    </AuthCard>
  );
}
