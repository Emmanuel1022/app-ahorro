import { z } from "zod";

export const MIN_PASSWORD = 10;

const email = z.string().trim().min(1, "Ingresa tu correo").email("Correo no válido").max(254);
const password = z
  .string()
  .min(MIN_PASSWORD, `La contraseña debe tener al menos ${MIN_PASSWORD} caracteres`)
  .max(72, "La contraseña es demasiado larga")
  .regex(/[A-Za-z]/, "Incluye al menos una letra")
  .regex(/\d/, "Incluye al menos un número");

export const signInSchema = z.object({
  email,
  password: z.string().min(1, "Ingresa tu contraseña"),
});

export const signUpSchema = z
  .object({
    fullName: z.string().trim().min(2, "Ingresa tu nombre").max(100),
    email,
    password,
    confirmPassword: z.string(),
  })
  .refine((v) => v.password === v.confirmPassword, {
    path: ["confirmPassword"],
    message: "Las contraseñas no coinciden",
  });

export const resetRequestSchema = z.object({ email });

export const updatePasswordSchema = z
  .object({ password, confirmPassword: z.string() })
  .refine((v) => v.password === v.confirmPassword, {
    path: ["confirmPassword"],
    message: "Las contraseñas no coinciden",
  });

export type FieldErrors = Partial<Record<string, string>>;

export type FormState = {
  ok?: boolean;
  message?: string;
  error?: string;
  fieldErrors?: FieldErrors;
};

/** Primer error de cada campo, listo para mostrar. */
export function toFieldErrors(error: z.ZodError): FieldErrors {
  const out: FieldErrors = {};
  for (const issue of error.issues) {
    const key = String(issue.path[0] ?? "form");
    out[key] ??= issue.message;
  }
  return out;
}

export function formToObject(formData: FormData): Record<string, string> {
  const obj: Record<string, string> = {};
  formData.forEach((v, k) => {
    if (typeof v === "string") obj[k] = v;
  });
  return obj;
}
