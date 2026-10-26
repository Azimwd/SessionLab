export type Json = Record<string, any>;
export type Page<T = Json> = {
  count: number;
  next: string | null;
  previous: string | null;
  results: T[];
};
export class ApiError extends Error {
  constructor(
    message: string,
    public status: number,
  ) {
    super(message);
  }
}
let csrf = "";
export function clearCsrf() {
  csrf = "";
}
function explain(value: any): string {
  if (typeof value === "string") return value;
  if (Array.isArray(value)) return value.map(explain).join(" ");
  if (value && typeof value === "object")
    return Object.entries(value)
      .map(([k, v]) => `${k === "detail" ? "" : k + ": "}${explain(v)}`)
      .join(" ");
  return "Не удалось выполнить запрос";
}
export async function request<T = Json>(
  path: string,
  method = "GET",
  body?: unknown,
): Promise<T> {
  if (method !== "GET" && !csrf) {
    const r = await fetch("/api/auth/csrf/", { credentials: "include" });
    const j = await r.json();
    csrf = j.data.csrfToken;
  }
  const pendingKey = `sl:pending:${method}:${path}:${body instanceof FormData ? Array.from(body.entries()).map(([k,v]) => [k, v instanceof File ? [v.name,v.size,v.lastModified] : v]).join(':') : JSON.stringify(body)}`;
  let id = "";
  if (method !== "GET") {
    id = sessionStorage.getItem(pendingKey) || crypto.randomUUID();
    sessionStorage.setItem(pendingKey, id);
  }
  let response: Response;
  try {
    response = await fetch("/api" + path, {
      method,
      credentials: "include",
      headers: {
        ...(body instanceof FormData ? {} : { "Content-Type": "application/json" }),
        ...(method !== "GET"
          ? { "X-CSRFToken": csrf, "Idempotency-Key": id }
          : {}),
      },
      body: body === undefined ? undefined : body instanceof FormData ? body : JSON.stringify(body),
      signal: AbortSignal.timeout(20000),
    });
  } catch {
    throw new Error(
      "Связь прервалась. Повторите действие: сохранённый ключ защитит от дубля.",
    );
  }
  let payload: any;
  try {
    payload = await response.json();
  } catch {
    throw new Error("Сервер недоступен. Повторите запрос с теми же данными.");
  }
  if (!response.ok) {
    if (response.status < 500) sessionStorage.removeItem(pendingKey);
    if (response.status === 403) csrf = "";
    throw new ApiError(explain(payload.error || payload), response.status);
  }
  if (method !== "GET") sessionStorage.removeItem(pendingKey);
  return payload.data as T;
}
export const list = (path: string) => request<Page>(path);
