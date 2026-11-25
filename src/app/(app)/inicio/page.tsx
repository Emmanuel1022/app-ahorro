import type { Metadata } from "next";
import Link from "next/link";
import { ArrowDownRight, ArrowUpRight, Building2, PiggyBank, Scale, Wallet } from "lucide-react";
import { Amount } from "@/components/privacy";
import { buttonClasses } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { EmptyState } from "@/components/ui/empty-state";
import { PageHeader } from "@/components/ui/page-header";

export const metadata: Metadata = { title: "Inicio" };

const cards = [
  { title: "Saldo total", icon: Wallet, tone: "neutral" as const },
  { title: "Ingresos del mes", icon: ArrowUpRight, tone: "income" as const },
  { title: "Gastos del mes", icon: ArrowDownRight, tone: "expense" as const },
  { title: "Balance del mes", icon: Scale, tone: "neutral" as const },
  { title: "Total ahorrado", icon: PiggyBank, tone: "neutral" as const },
];

export default async function HomePage({ searchParams }: { searchParams: Promise<Record<string, string | undefined>> }) {
  const { contrasena } = await searchParams;
  return (
    <>
      <PageHeader title="Inicio" description="Resumen de tus finanzas." />
      {contrasena === "actualizada" && (
        <p className="mb-4 rounded-lg bg-income-soft px-3 py-2 text-sm text-income" role="status">
          Tu contraseña se actualizó correctamente.
        </p>
      )}
      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-5">
        {cards.map(({ title, icon: Icon, tone }) => (
          <Card key={title}>
            <CardHeader>
              <CardTitle>{title}</CardTitle>
              <Icon className="h-4 w-4 text-muted" aria-hidden />
            </CardHeader>
            <CardContent>
              <Amount value="0" currency="CRC" tone={tone} className="text-2xl font-semibold" />
            </CardContent>
          </Card>
        ))}
      </div>
      <EmptyState
        className="mt-6"
        icon={Building2}
        title="Empieza agregando tu primer banco"
        description="Cuando registres bancos, cuentas y movimientos, aquí verás tus saldos, gráficos y últimos movimientos."
        action={
          <Link href="/bancos" className={buttonClasses("primary")}>
            Ir a Bancos
          </Link>
        }
      />
    </>
  );
}
