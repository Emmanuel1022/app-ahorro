import type { Metadata } from "next";
import { BarChart3 } from "lucide-react";
import { ModulePlaceholder } from "@/components/module-placeholder";

export const metadata: Metadata = { title: "Reportes" };

export default function Page() {
  return (
    <ModulePlaceholder
      title="Reportes"
      description="Analiza tus finanzas por período, categoría y cuenta."
      icon={BarChart3}
      emptyTitle="Los reportes aparecerán cuando tengas movimientos"
      emptyText="Ingresos y gastos, flujo de efectivo, patrimonio y exportación a Excel, CSV y PDF."
      stage={8}
    />
  );
}
