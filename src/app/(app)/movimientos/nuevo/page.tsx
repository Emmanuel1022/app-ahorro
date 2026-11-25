import type { Metadata } from "next";
import { Plus } from "lucide-react";
import { ModulePlaceholder } from "@/components/module-placeholder";

export const metadata: Metadata = { title: "Registrar movimiento" };

export default function Page() {
  return (
    <ModulePlaceholder
      title="Registrar movimiento"
      description="Ingreso, gasto o ajuste en una de tus cuentas."
      icon={Plus}
      emptyTitle="El formulario de movimientos está en camino"
      emptyText="Primero necesitarás un banco y una cuenta."
      stage={3}
    />
  );
}
