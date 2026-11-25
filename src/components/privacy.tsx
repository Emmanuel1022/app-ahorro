"use client";

import { createContext, useCallback, useContext, useEffect, useState } from "react";
import { formatMoney, type MoneyInput } from "@/lib/money";
import { cn } from "@/lib/utils";

const STORAGE_KEY = "app-ahorro:ocultar-montos";

type PrivacyContextValue = { hidden: boolean; toggle: () => void };
const PrivacyContext = createContext<PrivacyContextValue>({ hidden: false, toggle: () => {} });

export function PrivacyProvider({ children }: { children: React.ReactNode }) {
  const [hidden, setHidden] = useState(false);

  useEffect(() => {
    try {
      setHidden(localStorage.getItem(STORAGE_KEY) === "1");
    } catch {
      /* almacenamiento no disponible: se usa el valor por defecto */
    }
  }, []);

  const toggle = useCallback(() => {
    setHidden((h) => {
      const next = !h;
      try {
        localStorage.setItem(STORAGE_KEY, next ? "1" : "0");
      } catch {
        /* sin almacenamiento: el cambio vale solo para esta sesión */
      }
      return next;
    });
  }, []);

  return <PrivacyContext.Provider value={{ hidden, toggle }}>{children}</PrivacyContext.Provider>;
}

export const usePrivacy = () => useContext(PrivacyContext);

type Tone = "income" | "expense" | "transfer" | "neutral";
const toneClass: Record<Tone, string> = {
  income: "text-income",
  expense: "text-expense",
  transfer: "text-transfer",
  neutral: "",
};

/** Muestra un monto respetando el modo privacidad. */
export function Amount({
  value,
  currency,
  tone = "neutral",
  className,
}: {
  value: MoneyInput;
  currency: string;
  tone?: Tone;
  className?: string;
}) {
  const { hidden } = usePrivacy();
  return (
    <span className={cn("tabular", toneClass[tone], className)} data-amount>
      {formatMoney(value, currency, { hidden })}
    </span>
  );
}
