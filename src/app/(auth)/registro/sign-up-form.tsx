"use client";

import Link from "next/link";
import { MailCheck } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Field } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { PasswordInput } from "@/components/ui/password-input";
import { signUp } from "@/modules/auth/actions";
import { MIN_PASSWORD, signUpSchema } from "@/modules/auth/schemas";
import { useValidatedForm } from "@/modules/auth/use-validated-form";

export function SignUpForm() {
  const { state, formAction, pending, errors, onSubmit, fieldProps } = useValidatedForm(signUpSchema, signUp);

  if (state.ok) {
    return (
      <div className="space-y-4 text-center">
        <MailCheck className="mx-auto h-10 w-10 text-income" aria-hidden />
        <p className="text-sm">{state.message}</p>
        <Link href="/login" className="text-sm font-medium text-primary hover:underline">
          Volver a iniciar sesión
        </Link>
      </div>
    );
  }

  return (
    <form action={formAction} onSubmit={onSubmit} noValidate className="space-y-4">
      <Field id="fullName" label="Nombre" error={errors.fullName}>
        <Input {...fieldProps("fullName")} autoComplete="name" placeholder="Tu nombre" />
      </Field>
      <Field id="email" label="Correo electrónico" error={errors.email}>
        <Input {...fieldProps("email")} type="email" autoComplete="email" placeholder="tu@correo.com" />
      </Field>
      <Field id="password" label="Contraseña" error={errors.password}>
        <PasswordInput {...fieldProps("password")} autoComplete="new-password" />
      </Field>
      <p className="-mt-2 text-xs text-muted">Mínimo {MIN_PASSWORD} caracteres, con letras y números.</p>
      <Field id="confirmPassword" label="Confirmar contraseña" error={errors.confirmPassword}>
        <PasswordInput {...fieldProps("confirmPassword")} autoComplete="new-password" />
      </Field>
      <Button type="submit" className="w-full" loading={pending}>
        Crear cuenta
      </Button>
      <p className="text-center text-sm text-muted">
        ¿Ya tienes cuenta?{" "}
        <Link href="/login" className="font-medium text-primary hover:underline">
          Inicia sesión
        </Link>
      </p>
    </form>
  );
}
