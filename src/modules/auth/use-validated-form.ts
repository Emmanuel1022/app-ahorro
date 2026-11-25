"use client";

import { useActionState, useEffect, useState } from "react";
import { toast } from "sonner";
import type { z } from "zod";
import { formToObject, toFieldErrors, type FieldErrors, type FormState } from "./schemas";

/**
 * Valida en el navegador con el mismo esquema Zod que usa el servidor
 * y, si todo está bien, envía la Server Action.
 */
export function useValidatedForm(
  schema: z.ZodType,
  action: (prev: FormState, formData: FormData) => Promise<FormState>,
) {
  const [state, formAction, pending] = useActionState(action, {});
  const [clientErrors, setClientErrors] = useState<FieldErrors>({});

  useEffect(() => {
    if (state.error) toast.error(state.error);
    if (state.ok && state.message) toast.success(state.message);
  }, [state]);

  const onSubmit = (e: React.FormEvent<HTMLFormElement>) => {
    const parsed = schema.safeParse(formToObject(new FormData(e.currentTarget)));
    if (!parsed.success) {
      e.preventDefault();
      setClientErrors(toFieldErrors(parsed.error));
    } else {
      setClientErrors({});
    }
  };

  const errors: FieldErrors = { ...state.fieldErrors, ...clientErrors };
  const fieldProps = (name: string) => ({
    id: name,
    name,
    "aria-invalid": errors[name] ? true : undefined,
    "aria-describedby": errors[name] ? `${name}-error` : undefined,
  });

  return { state, formAction, pending, errors, onSubmit, fieldProps };
}
