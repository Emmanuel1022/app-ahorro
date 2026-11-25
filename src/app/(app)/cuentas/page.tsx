import type { Metadata } from "next";
import { WalletCards } from "lucide-react";
import { ModulePlaceholder } from "@/components/module-placeholder";

export const metadata: Metadata = { title: "Cuentas" };

export default function Page() {
  return (
    <ModulePlaceholder
      title="Cuentas"
      description="Tus cuentas de ahorro, corrientes, efectivo e inversión."
      icon={WalletCards}
      emptyTitle="Aún no hay cuentas"
      emptyText="Crea una cuenta dentro de un banco, con su moneda y saldo inicial."
      stage={2}
    />
  );
}
