"use client";

import Link from "next/link";
import { MailCheck } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Field } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { requestPasswordReset } from "@/modules/auth/actions";
import { resetRequestSchema } from "@/modules/auth/schemas";
import { useValidatedForm } from "@/modules/auth/use-validated-form";

export function ResetRequestForm() {
  const { state, formAction, pending, errors, onSubmit, fieldProps } = useValidatedForm(resetRequestSchema, requestPasswordReset);

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
      <Field id="email" label="Correo electrónico" error={errors.email}>
        <Input {...fieldProps("email")} type="email" autoComplete="email" placeholder="tu@correo.com" />
      </Field>
      <Button type="submit" className="w-full" loading={pending}>
        Enviar enlace
      </Button>
      <p className="text-center text-sm">
        <Link href="/login" className="font-medium text-primary hover:underline">
          Volver a iniciar sesión
        </Link>
      </p>
    </form>
  );
}
