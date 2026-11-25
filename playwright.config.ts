import { defineConfig, devices } from "@playwright/test";

const PORT = 3100;
const AUTH_PORT = 54329;

export default defineConfig({
  testDir: "tests/e2e",
  fullyParallel: false,
  workers: 1,
  retries: 0,
  reporter: [["list"]],
  use: { baseURL: `http://localhost:${PORT}`, trace: "off", locale: "es-CR" },
  projects: [
    { name: "escritorio", use: { ...devices["Desktop Chrome"] }, grepInvert: /@movil/ },
    { name: "movil", use: { ...devices["Pixel 7"] }, grep: /@movil/ },
  ],
  webServer: [
    {
      command: "node tests/e2e/mock-auth-server.mjs",
      port: AUTH_PORT,
      env: { MOCK_AUTH_PORT: String(AUTH_PORT) },
      reuseExistingServer: false,
    },
    {
      command: `npx next start -p ${PORT}`,
      port: PORT,
      reuseExistingServer: false,
      env: {
        NEXT_PUBLIC_SUPABASE_URL: `http://localhost:${AUTH_PORT}`,
        NEXT_PUBLIC_SUPABASE_ANON_KEY: "clave-de-prueba",
      },
    },
  ],
});
