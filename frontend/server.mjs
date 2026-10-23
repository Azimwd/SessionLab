// Railway production entry point: one browser origin for SPA, Django sessions and SSE.
import http from 'node:http';
import https from 'node:https';
import { createReadStream, statSync } from 'node:fs';
import { resolve, extname, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const types = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8', '.json': 'application/json',
  '.svg': 'image/svg+xml', '.png': 'image/png', '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg', '.ico': 'image/x-icon', '.webp': 'image/webp',
  '.woff': 'font/woff', '.woff2': 'font/woff2', '.txt': 'text/plain; charset=utf-8',
};
const hopHeaders = new Set(['connection', 'keep-alive', 'proxy-authenticate', 'proxy-authorization', 'te', 'trailer', 'transfer-encoding', 'upgrade']);

export function createApp({ backendUrl, dist = resolve(fileURLToPath(new URL('./dist/', import.meta.url))), publicScheme = 'https' }) {
  if (!backendUrl) throw new Error('BACKEND_URL must point to the Django Railway service');
  const backend = new URL(backendUrl);
  if (!['http:', 'https:'].includes(backend.protocol) || backend.pathname !== '/' || backend.search || backend.hash || backend.username || backend.password) {
    throw new Error('BACKEND_URL must be a bare http(s) origin');
  }
  if (!['http', 'https'].includes(publicScheme)) throw new Error('Invalid PUBLIC_SCHEME');
  const base = resolve(dist);
  return http.createServer((req, res) => {
    const raw = req.url || '/';
    let pathname;
    try { pathname = decodeURIComponent(raw.split('?', 1)[0]); }
    catch { res.writeHead(400).end('Bad URL'); return; }
    if (!pathname.startsWith('/')) { res.writeHead(400).end('Bad URL'); return; }
    const proxied = ['/api', '/admin', '/static'].some(prefix => pathname === prefix || pathname.startsWith(prefix + '/'));
    if (proxied) {
      const headers = { ...req.headers };
      for (const key of [...hopHeaders, 'x-forwarded-proto', 'x-forwarded-host', 'forwarded']) delete headers[key];
      headers.host = req.headers.host || backend.host;
      headers['x-forwarded-proto'] = publicScheme;
      const upstream = (backend.protocol === 'https:' ? https : http).request(
        { protocol: backend.protocol, hostname: backend.hostname, port: backend.port || undefined,
          method: req.method, path: raw, headers },
        response => {
          const outgoing = { ...response.headers };
          for (const key of hopHeaders) delete outgoing[key];
          // Django normally uses relative redirects. Never expose a private URL.
          if (outgoing.location?.startsWith(backend.origin)) {
            outgoing.location = outgoing.location.slice(backend.origin.length) || '/';
          }
          res.writeHead(response.statusCode || 502, outgoing);
          response.pipe(res);
        },
      );
      upstream.on('error', () => { if (!res.headersSent) res.writeHead(502, { 'Content-Type': 'text/plain; charset=utf-8' }); res.end('Backend unavailable'); });
      req.on('aborted', () => upstream.destroy());
      req.pipe(upstream);
      return;
    }
    if (req.method !== 'GET' && req.method !== 'HEAD') { res.writeHead(405, { Allow: 'GET, HEAD' }).end(); return; }
    if (pathname === '/healthz') { res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' }).end('ok'); return; }
    if (pathname.includes('\\') || pathname.includes('\0') || pathname.split('/').includes('..')) {
      res.writeHead(400).end('Bad path'); return;
    }
    const candidate = resolve(base, '.' + pathname);
    if (candidate !== base && !candidate.startsWith(base + sep)) { res.writeHead(400).end('Bad path'); return; }
    let file = candidate;
    try { if (!statSync(file).isFile()) file = ''; } catch { file = ''; }
    if (!file && !extname(pathname) && !pathname.startsWith('/assets/')) file = resolve(base, 'index.html');
    if (!file) { res.writeHead(404).end('Not found'); return; }
    let size;
    try { size = statSync(file).size; } catch { res.writeHead(404).end('Not found'); return; }
    res.writeHead(200, {
      'Content-Type': types[extname(file)] || 'application/octet-stream',
      'Content-Length': size,
      'X-Content-Type-Options': 'nosniff',
      'Cache-Control': pathname.startsWith('/assets/') ? 'public, max-age=31536000, immutable' : 'no-cache',
    });
    if (req.method === 'HEAD') { res.end(); return; }
    createReadStream(file).pipe(res);
  });
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const server = createApp({ backendUrl: process.env.BACKEND_URL, publicScheme: process.env.PUBLIC_SCHEME || 'https' });
  const port = Number(process.env.PORT || 3000);
  server.listen(port, '::', () => process.stdout.write(`SessionLab frontend on port ${port}\n`));
}
