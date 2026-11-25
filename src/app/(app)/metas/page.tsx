import type { Metadata } from "next";
import { Target } from "lucide-react";
import { ModulePlaceholder } from "@/components/module-placeholder";

export const metadata: Metadata = { title: "Metas de ahorro" };

export default function Page() {
  return (
    <ModulePlaceholder
      title="Metas de ahorro"
      description="Aparta dinero para tus objetivos y sigue tu avance."
      icon={Target}
      emptyTitle="Aún no hay metas"
      emptyText="Define una meta con monto objetivo y fecha, y registra aportes."
      stage={6}
    />
  );
}
