import type { Metadata } from "next";
import { AuthCard } from "../auth-card";
import { UpdatePasswordForm } from "./update-password-form";

export const metadata: Metadata = { title: "Nueva contraseña" };

export default function UpdatePasswordPage() {
  return (
    <AuthCard title="Crea una nueva contraseña" description="Elige una contraseña que no uses en otros sitios.">
      <UpdatePasswordForm />
    </AuthCard>
  );
}
