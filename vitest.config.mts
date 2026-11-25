import { defineConfig } from "vitest/config";
import path from "node:path";

export default defineConfig({
  resolve: { alias: { "@": path.resolve(import.meta.dirname, "src") } },
  test: {
    include: ["tests/**/*.test.ts"],
    environment: "node",
    fileParallelism: false,
    globalSetup: process.env.SKIP_DB_TESTS ? [] : ["tests/integration/global-setup.ts"],
    exclude: process.env.SKIP_DB_TESTS ? ["tests/integration/**", "node_modules/**"] : ["node_modules/**"],
  },
});
