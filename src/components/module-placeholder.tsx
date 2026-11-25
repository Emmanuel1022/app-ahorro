import type { LucideIcon } from "lucide-react";
import { EmptyState } from "@/components/ui/empty-state";
import { PageHeader } from "@/components/ui/page-header";

/** Página de un módulo cuyo contenido llega en una etapa posterior del plan. */
export function ModulePlaceholder({
  title,
  description,
  icon,
  emptyTitle,
  emptyText,
  stage,
}: {
  title: string;
  description: string;
  icon: LucideIcon;
  emptyTitle: string;
  emptyText: string;
  stage: number;
}) {
  return (
    <>
      <PageHeader title={title} description={description} />
      <EmptyState
        icon={icon}
        title={emptyTitle}
        description={emptyText}
        action={
          <span className="rounded-full bg-surface-muted px-3 py-1 text-xs font-medium text-muted">
            Disponible en la etapa {stage}
          </span>
        }
      />
    </>
  );
}
