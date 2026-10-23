import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";
const target = process.env.API_PROXY || "http://127.0.0.1:8000";
export default defineConfig({
  plugins: [react(), tailwindcss()],
  server: {
    allowedHosts: ["terminal.local"],
    proxy: {
      "/api": { target, changeOrigin: false },
      "/admin": { target, changeOrigin: false },
      "/static": { target, changeOrigin: false },
    },
  },
  test: { environment: "jsdom", setupFiles: ["./src/test-setup.ts"] },
});
