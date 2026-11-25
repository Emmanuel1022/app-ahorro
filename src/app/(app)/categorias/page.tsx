import type { Metadata } from "next";
import { Tags } from "lucide-react";
import { ModulePlaceholder } from "@/components/module-placeholder";

export const metadata: Metadata = { title: "Categorías" };

export default function Page() {
  return (
    <ModulePlaceholder
      title="Categorías"
      description="Clasifica tus ingresos y gastos."
      icon={Tags}
      emptyTitle="Tus categorías predeterminadas ya están creadas"
      emptyText="Pronto podrás verlas, editarlas y crear subcategorías."
      stage={2}
    />
  );
}
