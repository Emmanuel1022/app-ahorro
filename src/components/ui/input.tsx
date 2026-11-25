import { forwardRef } from "react";
import { cn } from "@/lib/utils";

export const Input = forwardRef<HTMLInputElement, React.InputHTMLAttributes<HTMLInputElement>>(function Input(
  { className, ...props },
  ref,
) {
  return (
    <input
      ref={ref}
      className={cn(
        "h-10 w-full rounded-lg border border-border bg-surface px-3 text-sm text-foreground placeholder:text-muted",
        "focus:outline-none focus:ring-2 focus:ring-ring focus:border-transparent",
        "aria-[invalid=true]:border-expense aria-[invalid=true]:focus:ring-expense",
        "disabled:opacity-50",
        className,
      )}
      {...props}
    />
  );
});
