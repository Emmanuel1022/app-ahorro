import type { Metadata } from "next";
import { Settings } from "lucide-react";
import { ModulePlaceholder } from "@/components/module-placeholder";

export const metadata: Metadata = { title: "Configuración" };

export default function Page() {
  return (
    <ModulePlaceholder
      title="Configuración"
      description="Moneda principal, tipos de cambio y preferencias."
      icon={Settings}
      emptyTitle="Configuración en camino"
      emptyText="Aquí elegirás la moneda principal, registrarás tipos de cambio y descargarás tus datos."
      stage={4}
    />
  );
}
