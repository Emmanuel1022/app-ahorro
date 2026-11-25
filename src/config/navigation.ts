import {
  ArrowLeftRight,
  BarChart3,
  Building2,
  House,
  ListOrdered,
  PiggyBank,
  Repeat,
  Settings,
  Tags,
  Target,
  WalletCards,
  type LucideIcon,
} from "lucide-react";

export type NavItem = { label: string; href: string; icon: LucideIcon };

export const NAV_ITEMS: NavItem[] = [
  { label: "Inicio", href: "/inicio", icon: House },
  { label: "Movimientos", href: "/movimientos", icon: ListOrdered },
  { label: "Transferencias", href: "/transferencias", icon: ArrowLeftRight },
  { label: "Bancos", href: "/bancos", icon: Building2 },
  { label: "Cuentas", href: "/cuentas", icon: WalletCards },
  { label: "Categorías", href: "/categorias", icon: Tags },
  { label: "Metas de ahorro", href: "/metas", icon: Target },
  { label: "Presupuestos", href: "/presupuestos", icon: PiggyBank },
  { label: "Movimientos recurrentes", href: "/recurrentes", icon: Repeat },
  { label: "Reportes", href: "/reportes", icon: BarChart3 },
  { label: "Configuración", href: "/configuracion", icon: Settings },
];

export const isActive = (pathname: string, href: string) => pathname === href || pathname.startsWith(`${href}/`);
