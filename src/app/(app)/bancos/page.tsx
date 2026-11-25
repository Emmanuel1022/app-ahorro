import type { Metadata } from "next";
import { Building2 } from "lucide-react";
import { ModulePlaceholder } from "@/components/module-placeholder";

export const metadata: Metadata = { title: "Bancos" };

export default function Page() {
  return (
    <ModulePlaceholder
      title="Bancos"
      description="Las entidades donde tienes tus cuentas."
      icon={Building2}
      emptyTitle="Aún no hay bancos"
      emptyText="Agrega tu primer banco para empezar a registrar cuentas."
      stage={2}
    />
  );
}
