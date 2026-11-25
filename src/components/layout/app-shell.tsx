"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { Menu, Plus, X } from "lucide-react";
import { Brand } from "./brand";
import { PrivacyToggle } from "./privacy-toggle";
import { SidebarNav } from "./sidebar-nav";
import { ThemeToggle } from "./theme-toggle";
import { UserMenu } from "./user-menu";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";

export function AppShell({ user, children }: { user: { name: string; email: string }; children: React.ReactNode }) {
  const [open, setOpen] = useState(false);
  const pathname = usePathname();

  useEffect(() => setOpen(false), [pathname]);
  useEffect(() => {
    document.body.style.overflow = open ? "hidden" : "";
    return () => {
      document.body.style.overflow = "";
    };
  }, [open]);

  return (
    <div className="min-h-dvh">
      {/* Menú lateral fijo en escritorio */}
      <aside className="fixed inset-y-0 left-0 z-30 hidden w-64 flex-col border-r border-border bg-surface lg:flex">
        <div className="flex h-16 items-center px-5">
          <Link href="/inicio" aria-label="Ir al inicio">
            <Brand />
          </Link>
        </div>
        <div className="flex-1 overflow-y-auto px-3 pb-6">
          <SidebarNav />
        </div>
      </aside>

      {/* Menú deslizable en móvil y tablet */}
      <div
        className={cn("fixed inset-0 z-40 bg-black/40 transition-opacity lg:hidden", open ? "opacity-100" : "pointer-events-none opacity-0")}
        onClick={() => setOpen(false)}
        aria-hidden
      />
      <aside
        id="mobile-nav"
        className={cn(
          "fixed inset-y-0 left-0 z-50 flex w-72 max-w-[85vw] flex-col bg-surface shadow-xl transition-transform lg:hidden",
          open ? "translate-x-0" : "-translate-x-full",
        )}
        aria-hidden={!open}
        inert={!open}
      >
        <div className="flex h-16 items-center justify-between px-5">
          <Brand />
          <Button variant="ghost" size="icon" onClick={() => setOpen(false)} aria-label="Cerrar menú">
            <X className="h-5 w-5" />
          </Button>
        </div>
        <div className="flex-1 overflow-y-auto px-3 pb-6">
          <SidebarNav onNavigate={() => setOpen(false)} />
        </div>
      </aside>

      <div className="lg:pl-64">
        <header className="sticky top-0 z-20 flex h-16 items-center gap-2 border-b border-border bg-background/85 px-4 backdrop-blur sm:px-6">
          <Button
            variant="ghost"
            size="icon"
            className="lg:hidden"
            onClick={() => setOpen(true)}
            aria-label="Abrir menú"
            aria-controls="mobile-nav"
            aria-expanded={open}
          >
            <Menu className="h-5 w-5" />
          </Button>
          <div className="lg:hidden">
            <Brand className="[&_span]:hidden sm:[&_span]:inline" />
          </div>
          <div className="ml-auto flex items-center gap-1">
            <PrivacyToggle />
            <ThemeToggle />
            <div className="ml-1">
              <UserMenu name={user.name} email={user.email} />
            </div>
          </div>
        </header>

        <main className="mx-auto w-full max-w-7xl px-4 py-6 pb-28 sm:px-6 lg:py-8">{children}</main>
      </div>

      {/* Acceso rápido para registrar un movimiento */}
      <Link
        href="/movimientos/nuevo"
        className="fixed bottom-6 right-6 z-30 flex h-14 items-center gap-2 rounded-full bg-primary px-5 text-sm font-semibold text-primary-foreground shadow-lg transition-transform hover:scale-105 hover:bg-primary-hover focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2"
        aria-label="Registrar movimiento"
      >
        <Plus className="h-5 w-5" aria-hidden />
        <span className="hidden sm:inline">Registrar movimiento</span>
      </Link>
    </div>
  );
}
