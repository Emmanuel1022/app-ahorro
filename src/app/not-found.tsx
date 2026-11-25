import Link from "next/link";
import { buttonClasses } from "@/components/ui/button";

export default function NotFound() {
  return (
    <main className="flex min-h-dvh flex-col items-center justify-center gap-4 px-4 text-center">
      <p className="text-sm font-semibold text-primary">404</p>
      <h1 className="text-2xl font-semibold">Página no encontrada</h1>
      <p className="text-sm text-muted">La dirección que buscas no existe o fue movida.</p>
      <Link href="/inicio" className={buttonClasses("primary")}>
        Volver al inicio
      </Link>
    </main>
  );
}
