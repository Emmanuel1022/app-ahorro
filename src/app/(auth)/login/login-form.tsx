"use client";

import Link from "next/link";
import { Button } from "@/components/ui/button";
import { Field } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { PasswordInput } from "@/components/ui/password-input";
import { signIn } from "@/modules/auth/actions";
import { signInSchema } from "@/modules/auth/schemas";
import { useValidatedForm } from "@/modules/auth/use-validated-form";

export function LoginForm({ next }: { next?: string }) {
  const { formAction, pending, errors, onSubmit, fieldProps } = useValidatedForm(signInSchema, signIn);
  return (
    <form action={formAction} onSubmit={onSubmit} noValidate className="space-y-4">
      <input type="hidden" name="next" value={next ?? ""} />
      <Field id="email" label="Correo electrónico" error={errors.email}>
        <Input {...fieldProps("email")} type="email" autoComplete="email" placeholder="tu@correo.com" />
      </Field>
      <Field
        id="password"
        label="Contraseña"
        error={errors.password}
        hint={
          <Link href="/recuperar" className="text-xs font-medium text-primary hover:underline">
            ¿Olvidaste tu contraseña?
          </Link>
        }
      >
        <PasswordInput {...fieldProps("password")} autoComplete="current-password" />
      </Field>
      <Button type="submit" className="w-full" loading={pending}>
        Iniciar sesión
      </Button>
      <p className="text-center text-sm text-muted">
        ¿No tienes cuenta?{" "}
        <Link href="/registro" className="font-medium text-primary hover:underline">
          Crear cuenta
        </Link>
      </p>
    </form>
  );
}
