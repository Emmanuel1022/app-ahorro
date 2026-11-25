import type { Metadata } from "next";
import { AuthCard } from "../auth-card";
import { ResetRequestForm } from "./reset-request-form";

export const metadata: Metadata = { title: "Recuperar contraseña" };

export default function ResetRequestPage() {
  return (
    <AuthCard title="Recuperar contraseña" description="Te enviaremos un enlace para crear una nueva contraseña.">
      <ResetRequestForm />
    </AuthCard>
  );
}
