/** Optional combined local runner. Install backend and frontend dependencies first. */
import { spawn } from "node:child_process";
import { existsSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { resolve, dirname } from "node:path";
const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
try {
  process.loadEnvFile(resolve(root, ".env"));
} catch (e) {
  if (e.code !== "ENOENT") throw e;
}
const python =
  process.env.PYTHON_EXECUTABLE ||
  (existsSync(resolve(root, ".venv/Scripts/python.exe"))
    ? resolve(root, ".venv/Scripts/python.exe")
    : existsSync(resolve(root, ".venv/bin/python"))
    ? resolve(root, ".venv/bin/python")
    : "python");
const opts = { cwd: root, env: process.env, stdio: "inherit" };
const backend = spawn(
  python,
  ["backend/manage.py", "runserver", "0.0.0.0:8000", "--noreload"],
  opts,
);
const forwarded = process.argv.slice(2);
const portIndex = forwarded.indexOf("--port");
const port = portIndex >= 0 ? forwarded[portIndex + 1] : "5173";
const frontend = spawn(
  process.execPath,
  ["node_modules/vite/bin/vite.js", "--host", "0.0.0.0", ...forwarded],
  { ...opts, cwd: resolve(root, "frontend") },
);
const stop = () => {
  backend.kill("SIGTERM");
  frontend.kill("SIGTERM");
};
process.on("SIGTERM", stop);
process.on("SIGINT", stop);
for (const p of [backend, frontend]) {
  p.on("error", (e) => {
    console.error(e.message);
    stop();
    process.exitCode = 1;
  });
  p.on("exit", (code) => {
    if (code) {
      stop();
      process.exitCode = code;
    }
  });
}
// Explicit opt-in creates a disposable QA account using normal CSRF/session HTTP endpoints.
if (process.env.SESSIONLAB_SMOKE === "1") {
  const base = `http://localhost:${port}`;
  let tries = 0;
  const timer = setInterval(async () => {
    try {
      const r = await fetch(base + "/api/auth/csrf/");
      if (!r.ok) throw Error(r.status);
      clearInterval(timer);
      const smoke = spawn(python, ["scripts/smoke_http.py", base], {
        ...opts,
        stdio: ["ignore", "pipe", "pipe"],
      });
      let output = "";
      smoke.stdout.on("data", (s) => {
        output += s;
        process.stdout.write(s);
      });
      smoke.stderr.on("data", (s) => {
        output += s;
        process.stderr.write(s);
      });
      smoke.on("exit", (code) =>
        writeFileSync(
          resolve(root, ".qa-http-smoke.log"),
          `Exit: ${code}\n${output}`,
        ),
      );
    } catch (e) {
      if (++tries > 30) {
        clearInterval(timer);
        writeFileSync(
          resolve(root, ".qa-http-smoke.log"),
          "FAIL: local services did not become ready",
        );
      }
    }
  }, 1000);
}
