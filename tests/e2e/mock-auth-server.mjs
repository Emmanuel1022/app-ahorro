// Servidor mínimo que imita Supabase Auth (GoTrue) para las pruebas de punta a punta.
// Solo se usa en pruebas: la app real habla con Supabase.
import { createServer } from "node:http";
import { randomUUID } from "node:crypto";

const PORT = Number(process.env.MOCK_AUTH_PORT ?? 54329);
export const TEST_USER = { email: "erick@prueba.cr", password: "Correcta1234", name: "Erick Prueba" };

const user = {
  id: randomUUID(),
  aud: "authenticated",
  role: "authenticated",
  email: TEST_USER.email,
  email_confirmed_at: new Date().toISOString(),
  app_metadata: { provider: "email", providers: ["email"] },
  user_metadata: { full_name: TEST_USER.name },
  identities: [],
  created_at: new Date().toISOString(),
  updated_at: new Date().toISOString(),
};

const b64 = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");
const tokens = new Set();

function session() {
  const exp = Math.floor(Date.now() / 1000) + 3600;
  const access_token = `${b64({ alg: "HS256", typ: "JWT" })}.${b64({ sub: user.id, email: user.email, role: "authenticated", aud: "authenticated", exp, session_id: randomUUID() })}.firma`;
  tokens.add(access_token);
  return { access_token, token_type: "bearer", expires_in: 3600, expires_at: exp, refresh_token: randomUUID(), user };
}

const send = (res, status, body) => {
  res.writeHead(status, { "content-type": "application/json", "access-control-allow-origin": "*", "access-control-allow-headers": "*", "access-control-allow-methods": "*" });
  res.end(body === undefined ? "" : JSON.stringify(body));
};
const fail = (res, status, error_code, msg) => send(res, status, { code: status, error_code, msg });

createServer(async (req, res) => {
  if (req.method === "OPTIONS") return send(res, 204);
  let raw = "";
  for await (const chunk of req) raw += chunk;
  const body = raw ? JSON.parse(raw) : {};
  const url = new URL(req.url, `http://localhost:${PORT}`);
  const path = url.pathname.replace(/^\/auth\/v1/, "");
  const bearer = (req.headers.authorization ?? "").replace(/^Bearer /, "");

  if (path === "/token" && url.searchParams.get("grant_type") === "password") {
    if (body.email === TEST_USER.email && body.password === TEST_USER.password) return send(res, 200, session());
    return fail(res, 400, "invalid_credentials", "Invalid login credentials");
  }
  if (path === "/token" && url.searchParams.get("grant_type") === "refresh_token") return send(res, 200, session());
  if (path === "/user" && req.method === "GET") {
    return tokens.has(bearer) ? send(res, 200, user) : fail(res, 401, "bad_jwt", "invalid JWT");
  }
  if (path === "/user" && req.method === "PUT") {
    return tokens.has(bearer) ? send(res, 200, user) : fail(res, 401, "bad_jwt", "invalid JWT");
  }
  if (path === "/signup") {
    return send(res, 200, { ...user, id: randomUUID(), email: body.email, email_confirmed_at: null, confirmation_sent_at: new Date().toISOString() });
  }
  if (path === "/recover") return send(res, 200, {});
  if (path === "/logout") {
    tokens.delete(bearer);
    return send(res, 204);
  }
  return fail(res, 404, "not_found", `Ruta simulada no implementada: ${req.method} ${path}`);
}).listen(PORT, () => console.log(`mock-auth escuchando en ${PORT}`));
