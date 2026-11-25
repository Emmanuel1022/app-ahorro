"use client";

import { AlertTriangle } from "lucide-react";
import { Button } from "@/components/ui/button";
import { EmptyState } from "@/components/ui/empty-state";

export default function AppError({ reset }: { error: Error; reset: () => void }) {
  return (
    <EmptyState
      icon={AlertTriangle}
      title="Algo salió mal"
      description="No pudimos cargar esta sección. Intenta de nuevo en unos segundos."
      action={<Button onClick={reset}>Reintentar</Button>}
    />
  );
}
