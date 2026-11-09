import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, mkdirSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import http from 'node:http';
import { createApp } from './server.mjs';

async function listen(server) {
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  return `http://127.0.0.1:${server.address().port}`;
}
async function close(server) { await new Promise((resolve, reject) => server.close(error => error ? reject(error) : resolve())); }

test('production frontend serves SPA and forwards session, CSRF, POST and event stream', async () => {
  const dist = mkdtempSync(join(tmpdir(), 'sessionlab-'));
  mkdirSync(join(dist, 'assets'));
  writeFileSync(join(dist, 'index.html'), '<h1>SessionLab</h1>');
  writeFileSync(join(dist, 'assets', 'bundle.js'), 'export {}');
  const backend = http.createServer(async (req, res) => {
    if (req.url === '/api/stream/') {
      res.writeHead(200, { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-cache' });
      res.end('data: ready\n\n'); return;
    }
    let body = '';
    for await (const part of req) body += part.toString();
    res.writeHead(200, { 'Content-Type': 'application/json', 'Set-Cookie': ['sessionid=abc; HttpOnly; Secure; SameSite=Lax', 'csrftoken=xyz; HttpOnly; Secure; SameSite=Lax'] });
    res.end(JSON.stringify({ path: req.url, method: req.method, body, host: req.headers.host, scheme: req.headers['x-forwarded-proto'], csrf: req.headers['x-csrftoken'] }));
  });
  let frontend;
  try {
    const backendUrl = await listen(backend);
    frontend = createApp({ backendUrl, dist, publicScheme: 'https' });
    const origin = await listen(frontend);
    const page = await fetch(origin + '/sheet');
    assert.equal(page.status, 200);
    assert.match(await page.text(), /SessionLab/);
    const asset = await fetch(origin + '/assets/bundle.js');
    assert.match(asset.headers.get('cache-control'), /immutable/);
    assert.equal((await fetch(origin + '/missing.js')).status, 404);
    const action = await fetch(origin + '/api/room/initiative/?campaign=1', { method: 'POST', headers: { 'X-CSRFToken': 'xyz', Cookie: 'sessionid=abc' }, body: '{"action":"reset"}' });
    assert.equal(action.status, 200);
    const data = await action.json();
    assert.equal(data.path, '/api/room/initiative/?campaign=1');
    assert.equal(data.body, '{"action":"reset"}');
    assert.equal(data.scheme, 'https');
    assert.equal(data.csrf, 'xyz');
    assert.match(data.host, /^127\.0\.0\.1:/);
    assert.equal(action.headers.getSetCookie().length, 2);
    assert.match(await (await fetch(origin + '/api/stream/')).text(), /data: ready/);
    const traversal = await new Promise((resolve, reject) => {
      const target = new URL(origin);
      http.get({ hostname: target.hostname, port: target.port, path: '/%2e%2e/%2e%2e/package.json' }, response => {
        response.resume(); response.on('end', () => resolve(response.statusCode));
      }).on('error', reject);
    });
    assert.equal(traversal, 400);
  } finally {
    if (frontend) await close(frontend);
    await close(backend);
    rmSync(dist, { recursive: true, force: true });
  }
});

test('closing the browser stream also closes the upstream response', { timeout: 3000 }, async () => {
  let disconnected;
  const closed = new Promise(resolve => { disconnected = resolve; });
  const backend = http.createServer((req, res) => {
    res.once('close', disconnected);
    res.writeHead(200, { 'Content-Type': 'text/event-stream' });
    res.write(': heartbeat\n\n');
  });
  const frontend = createApp({ backendUrl: await listen(backend) });
  try {
    const origin = await listen(frontend);
    const controller = new AbortController();
    const response = await fetch(origin + '/api/stream/', { signal: controller.signal });
    assert.equal(response.status, 200);
    controller.abort();
    await closed;
  } finally {
    frontend.closeAllConnections();
    backend.closeAllConnections();
    await Promise.all([close(frontend), close(backend)]);
  }
});
