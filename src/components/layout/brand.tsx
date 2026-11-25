import { PiggyBank } from "lucide-react";
import { cn } from "@/lib/utils";

export function Brand({ className }: { className?: string }) {
  return (
    <div className={cn("flex items-center gap-2.5", className)}>
      <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-primary text-primary-foreground">
        <PiggyBank className="h-5 w-5" aria-hidden />
      </div>
      <span className="text-lg font-semibold tracking-tight">App Ahorro</span>
    </div>
  );
}
