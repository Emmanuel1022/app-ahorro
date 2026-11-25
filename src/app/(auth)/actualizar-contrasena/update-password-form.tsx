"use client";

import { Button } from "@/components/ui/button";
import { Field } from "@/components/ui/field";
import { PasswordInput } from "@/components/ui/password-input";
import { updatePassword } from "@/modules/auth/actions";
import { MIN_PASSWORD, updatePasswordSchema } from "@/modules/auth/schemas";
import { useValidatedForm } from "@/modules/auth/use-validated-form";

export function UpdatePasswordForm() {
  const { formAction, pending, errors, onSubmit, fieldProps } = useValidatedForm(updatePasswordSchema, updatePassword);
  return (
    <form action={formAction} onSubmit={onSubmit} noValidate className="space-y-4">
      <Field id="password" label="Nueva contraseña" error={errors.password}>
        <PasswordInput {...fieldProps("password")} autoComplete="new-password" />
      </Field>
      <p className="-mt-2 text-xs text-muted">Mínimo {MIN_PASSWORD} caracteres, con letras y números.</p>
      <Field id="confirmPassword" label="Confirmar contraseña" error={errors.confirmPassword}>
        <PasswordInput {...fieldProps("confirmPassword")} autoComplete="new-password" />
      </Field>
      <Button type="submit" className="w-full" loading={pending}>
        Guardar contraseña
      </Button>
    </form>
  );
}
