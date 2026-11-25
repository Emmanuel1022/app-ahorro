import type { Metadata } from "next";
import { AuthCard } from "../auth-card";
import { SignUpForm } from "./sign-up-form";

export const metadata: Metadata = { title: "Crear cuenta" };

export default function SignUpPage() {
  return (
    <AuthCard title="Crear cuenta" description="Empieza a controlar tus cuentas, gastos y ahorros.">
      <SignUpForm />
    </AuthCard>
  );
}
