import type { Metadata } from "next";
import { Repeat } from "lucide-react";
import { ModulePlaceholder } from "@/components/module-placeholder";

export const metadata: Metadata = { title: "Movimientos recurrentes" };

export default function Page() {
  return (
    <ModulePlaceholder
      title="Movimientos recurrentes"
      description="Salario, alquiler, servicios y suscripciones que se repiten."
      icon={Repeat}
      emptyTitle="Aún no hay movimientos recurrentes"
      emptyText="Configura movimientos semanales, quincenales, mensuales o anuales."
      stage={7}
    />
  );
}
