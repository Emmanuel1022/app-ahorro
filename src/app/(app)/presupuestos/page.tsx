import type { Metadata } from "next";
import { PiggyBank } from "lucide-react";
import { ModulePlaceholder } from "@/components/module-placeholder";

export const metadata: Metadata = { title: "Presupuestos" };

export default function Page() {
  return (
    <ModulePlaceholder
      title="Presupuestos"
      description="Límites mensuales por categoría de gasto."
      icon={PiggyBank}
      emptyTitle="Aún no hay presupuestos"
      emptyText="Define cuánto quieres gastar por categoría y recibe alertas al 80 % y 100 %."
      stage={6}
    />
  );
}
