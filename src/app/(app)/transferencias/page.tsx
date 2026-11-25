import type { Metadata } from "next";
import { ArrowLeftRight } from "lucide-react";
import { ModulePlaceholder } from "@/components/module-placeholder";

export const metadata: Metadata = { title: "Transferencias" };

export default function Page() {
  return (
    <ModulePlaceholder
      title="Transferencias"
      description="Mueve dinero entre tus cuentas, incluso entre bancos y monedas."
      icon={ArrowLeftRight}
      emptyTitle="Aún no hay transferencias"
      emptyText="Registra transferencias entre cuentas propias con comisión y tipo de cambio."
      stage={4}
    />
  );
}
