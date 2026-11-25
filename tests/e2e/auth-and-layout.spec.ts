import { expect, test, type Page } from "@playwright/test";

const USER = { email: "erick@prueba.cr", password: "Correcta1234" };

async function login(page: Page, next?: string) {
  await page.goto(next ? `/login?next=${encodeURIComponent(next)}` : "/login");
  await page.getByLabel("Correo electrónico").fill(USER.email);
  await page.getByLabel("Contraseña", { exact: true }).fill(USER.password);
  await page.getByRole("button", { name: "Iniciar sesión" }).click();
  await page.waitForURL((url) => !url.pathname.startsWith("/login"));
}

test.describe("protección de rutas", () => {
  test("sin sesión, la raíz y las rutas de la app llevan al login", async ({ page }) => {
    await page.goto("/");
    await expect(page).toHaveURL(/\/login$/);
    await page.goto("/movimientos");
    await expect(page).toHaveURL(/\/login\?next=%2Fmovimientos/);
    await expect(page.getByRole("heading", { name: "Iniciar sesión" })).toBeVisible();
  });

  test("después de iniciar sesión vuelve a la ruta pedida", async ({ page }) => {
    await login(page, "/movimientos");
    await expect(page).toHaveURL(/\/movimientos$/);
    await expect(page.getByRole("heading", { name: "Movimientos", level: 1 })).toBeVisible();
  });

  test("no permite redirecciones a otros sitios", async ({ page }) => {
    await login(page, "//sitio-malicioso.com");
    await expect(page).toHaveURL(/\/inicio$/);
  });

  test("con sesión, /login lleva al inicio", async ({ page }) => {
    await login(page);
    await expect(page).toHaveURL(/\/inicio$/);
    await page.goto("/login");
    await expect(page).toHaveURL(/\/inicio$/);
  });
});

test.describe("inicio de sesión", () => {
  test("valida los campos en el navegador", async ({ page }) => {
    await page.goto("/login");
    await page.getByRole("button", { name: "Iniciar sesión" }).click();
    await expect(page.getByText("Ingresa tu correo")).toBeVisible();
    await expect(page.getByText("Ingresa tu contraseña")).toBeVisible();
    await page.getByLabel("Correo electrónico").fill("no-es-correo");
    await page.getByRole("button", { name: "Iniciar sesión" }).click();
    await expect(page.getByText("Correo no válido")).toBeVisible();
  });

  test("credenciales incorrectas muestran un error claro", async ({ page }) => {
    await page.goto("/login");
    await page.getByLabel("Correo electrónico").fill(USER.email);
    await page.getByLabel("Contraseña", { exact: true }).fill("incorrecta123");
    await page.getByRole("button", { name: "Iniciar sesión" }).click();
    await expect(page.getByText("Correo o contraseña incorrectos.")).toBeVisible();
    await expect(page).toHaveURL(/\/login/);
  });

  test("muestra y oculta la contraseña", async ({ page }) => {
    await page.goto("/login");
    const input = page.getByLabel("Contraseña", { exact: true });
    await expect(input).toHaveAttribute("type", "password");
    await page.getByRole("button", { name: "Mostrar contraseña" }).click();
    await expect(input).toHaveAttribute("type", "text");
  });
});

test.describe("registro y recuperación", () => {
  test("registro valida contraseña y confirma por correo", async ({ page }) => {
    await page.goto("/registro");
    await page.getByLabel("Nombre").fill("Erick");
    await page.getByLabel("Correo electrónico").fill("nuevo@prueba.cr");
    await page.getByLabel("Contraseña", { exact: true }).fill("corta");
    await page.getByLabel("Confirmar contraseña").fill("otra");
    await page.getByRole("button", { name: "Crear cuenta" }).click();
    await expect(page.getByText("al menos 10 caracteres")).toBeVisible();
    await expect(page.getByText("Las contraseñas no coinciden")).toBeVisible();

    await page.getByLabel("Contraseña", { exact: true }).fill("Segura12345");
    await page.getByLabel("Confirmar contraseña").fill("Segura12345");
    await page.getByRole("button", { name: "Crear cuenta" }).click();
    await expect(page.getByText(/Te enviamos un correo para confirmar tu cuenta/).first()).toBeVisible();
  });

  test("recuperar contraseña no revela si el correo existe", async ({ page }) => {
    await page.goto("/login");
    await page.getByRole("link", { name: "¿Olvidaste tu contraseña?" }).click();
    await expect(page).toHaveURL(/\/recuperar$/);
    await page.getByLabel("Correo electrónico").fill("cualquiera@prueba.cr");
    await page.getByRole("button", { name: "Enviar enlace" }).click();
    await expect(page.getByText(/Si el correo está registrado/).first()).toBeVisible();
  });

  test("actualizar contraseña requiere sesión", async ({ page }) => {
    await page.goto("/actualizar-contrasena");
    await expect(page).toHaveURL(/\/login\?next=%2Factualizar-contrasena/);
  });
});

test.describe("layout de la aplicación", () => {
  test("menú lateral con los 11 módulos y navegación", async ({ page }) => {
    await login(page);
    const nav = page.getByRole("navigation", { name: "Menú principal" }).first();
    const labels = [
      "Inicio", "Movimientos", "Transferencias", "Bancos", "Cuentas", "Categorías",
      "Metas de ahorro", "Presupuestos", "Movimientos recurrentes", "Reportes", "Configuración",
    ];
    for (const label of labels) await expect(nav.getByRole("link", { name: label, exact: true })).toBeVisible();

    await nav.getByRole("link", { name: "Bancos", exact: true }).click();
    await expect(page).toHaveURL(/\/bancos$/);
    await expect(nav.getByRole("link", { name: "Bancos", exact: true })).toHaveAttribute("aria-current", "page");
    await expect(page.getByText("Aún no hay bancos")).toBeVisible();
  });

  test("modo privacidad oculta los montos", async ({ page }) => {
    await login(page);
    const amount = page.locator("[data-amount]").first();
    await expect(amount).toContainText("0,00");
    await page.getByRole("button", { name: "Ocultar montos" }).click();
    await expect(amount).toHaveText("••••••");
    await page.reload();
    await expect(page.locator("[data-amount]").first()).toHaveText("••••••");
    await page.getByRole("button", { name: "Mostrar montos" }).click();
    await expect(page.locator("[data-amount]").first()).toContainText("0,00");
  });

  test("modo oscuro y claro", async ({ page }) => {
    await login(page);
    await page.getByRole("button", { name: "Cambiar a modo oscuro" }).click();
    await expect(page.locator("html")).toHaveClass(/dark/);
    await page.getByRole("button", { name: "Cambiar a modo claro" }).click();
    await expect(page.locator("html")).not.toHaveClass(/dark/);
  });

  test("botón de acceso rápido para registrar movimiento", async ({ page }) => {
    await login(page);
    await page.getByRole("link", { name: "Registrar movimiento" }).click();
    await expect(page).toHaveURL(/\/movimientos\/nuevo$/);
  });

  test("cerrar sesión", async ({ page }) => {
    await login(page);
    await page.getByRole("button", { name: "Menú de usuario" }).click();
    await expect(page.getByText(USER.email)).toBeVisible();
    await page.getByRole("menuitem", { name: "Cerrar sesión" }).click();
    await expect(page).toHaveURL(/\/login$/);
    await page.goto("/inicio");
    await expect(page).toHaveURL(/\/login\?next=%2Finicio/);
  });

  test("página no encontrada en español", async ({ page }) => {
    await login(page);
    await page.goto("/no-existe");
    await expect(page.getByRole("heading", { name: "Página no encontrada" })).toBeVisible();
  });
});

test.describe("móvil @movil", () => {
  test("el menú se abre desde el botón y navega @movil", async ({ page }) => {
    await login(page);
    await expect(page.getByRole("button", { name: "Abrir menú" })).toBeVisible();
    await page.getByRole("button", { name: "Abrir menú" }).click();
    const drawer = page.locator("#mobile-nav");
    await drawer.getByRole("link", { name: "Cuentas", exact: true }).click();
    await expect(page).toHaveURL(/\/cuentas$/);
    await expect(page.getByRole("heading", { name: "Cuentas", level: 1 })).toBeVisible();
    await expect(page.getByRole("link", { name: "Registrar movimiento" })).toBeVisible();
  });

  test("sin desbordamiento horizontal @movil", async ({ page }) => {
    await login(page);
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
    expect(overflow).toBeLessThanOrEqual(0);
  });
});
