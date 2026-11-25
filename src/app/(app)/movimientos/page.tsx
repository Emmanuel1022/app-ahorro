import type { Metadata } from "next";
import { ListOrdered } from "lucide-react";
import { ModulePlaceholder } from "@/components/module-placeholder";

export const metadata: Metadata = { title: "Movimientos" };

export default function Page() {
  return (
    <ModulePlaceholder
      title="Movimientos"
      description="Ingresos, gastos y ajustes de todas tus cuentas."
      icon={ListOrdered}
      emptyTitle="Aún no hay movimientos"
      emptyText="Aquí verás tus ingresos y gastos con filtros, búsqueda y orden."
      stage={3}
    />
  );
}
