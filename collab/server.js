'use strict';
// Collaborative web terminal + chat.
// Multiple pseudo-terminal TABS shared by every connected browser. Each user
// picks which tab they view/type into locally; output is broadcast per tab.
// Auth = shared password via ?key= on the WS.

const http = require('http');
const fs   = require('fs');
const path = require('path');

let pty;
try { pty = require('@homebridge/node-pty-prebuilt-multiarch'); }
catch (e) { console.error('FATAL: node-pty not installed. Run npm install here.\n' + (e && e.message)); process.exit(1); }

let WebSocketServer;
try { ({ WebSocketServer } = require('ws')); }
catch (e) { console.error('FATAL: ws not installed. Run npm install here.'); process.exit(1); }

const PORT     = parseInt(process.env.PORT || '7681', 10);
const PASSWORD = process.env.SHARE_PASSWORD || 'changeme';
// Host-only kill switch. The launcher generates this and prints it ONLY in the
// local host console (never over the tunnel); a WS that presents ?admin=<token>
// matching it is treated as the host and may stop the whole session.
const ADMIN_TOKEN = process.env.SHARE_ADMIN_TOKEN || '';
const CWD      = process.env.SHARE_CWD || process.cwd();
const SHELL    = process.env.SHARE_SHELL || 'powershell.exe';
const COLS = 120, ROWS = 32;
const MAX_TABS = 10;
const SCROLL_LIMIT = 120000; // chars kept per tab for late joiners

const SHELL_ARGS  = /powershell|pwsh/i.test(SHELL) ? ['-NoLogo'] : [];
const SHELL_LABEL = path.basename(SHELL, path.extname(SHELL)).replace(/^powershell$/i, 'ps').toLowerCase();

// ---------- shared terminal tabs ----------
let tabSeq = 0;
let shuttingDown = false;
const tabs = new Map(); // id -> { id, title, term, scrollback }

function createTab() {
  const id = ++tabSeq;
  const tab = { id, title: SHELL_LABEL + ' ' + id, term: null, scrollback: '' };
  tabs.set(id, tab);
  tab.term = pty.spawn(SHELL, SHELL_ARGS, {
    name: 'xterm-256color', cols: COLS, rows: ROWS, cwd: CWD, env: process.env,
  });
  tab.term.onData(d => {
    tab.scrollback += d;
    if (tab.scrollback.length > SCROLL_LIMIT) tab.scrollback = tab.scrollback.slice(-SCROLL_LIMIT);
    broadcast({ type: 'out', tab: id, data: d });
  });
  tab.term.onExit(() => {
    if (shuttingDown) return;          // whole session is being torn down; don't respawn
    if (!tabs.has(id)) return;
    tabs.delete(id);
    broadcast({ type: 'sys', text: `— tab "${tab.title}" exited —` });
    if (tabs.size === 0) createTab();
    broadcastTabs();
  });
  return tab;
}

function tabList() { return [...tabs.values()].map(t => ({ id: t.id, title: t.title })); }
function broadcastTabs() { broadcast({ type: 'tabs', tabs: tabList() }); }
// The first tab is created lazily on the first client connect (see upgrade
// handler) so every pty we spawn is already inside the launcher's kill-on-close
// job object, and nothing is running before anyone is actually watching.

// Stop the whole session: kill every shared terminal (and the shells/agents
// running in them), then exit. The launcher supervises this process and, when it
// sees us exit, also stops the public tunnel - so one stop closes everything.
function shutdown(reason) {
  if (shuttingDown) return;
  shuttingDown = true;
  console.log('shutting down: ' + reason);
  for (const t of tabs.values()) { try { if (t.term) t.term.kill(); } catch (e) {} }
  setTimeout(() => process.exit(0), 300); // let final WS frames flush first
}
process.on('SIGINT',  () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));

// ---------- http: serve the single page ----------
const INDEX = path.join(__dirname, 'public', 'index.html');
const server = http.createServer((req, res) => {
  const u = (req.url || '/').split('?')[0];
  if (u === '/' || u === '/index.html') {
    fs.readFile(INDEX, (err, buf) => {
      if (err) { res.writeHead(500); res.end('index.html missing'); return; }
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      res.end(buf);
    });
  } else { res.writeHead(404); res.end('not found'); }
});

// ---------- websocket: shared tabs + chat ----------
const wss = new WebSocketServer({ noServer: true });
const clients = new Map(); // ws -> { name, color, tab }
let counter = 0;

// ---------- keepalive heartbeat ----------
// Cloudflare quick tunnels drop a proxied WebSocket that sees no frames for
// ~100s, so an idle terminal (open but nobody typing) gets disconnected. We
// ping every client every 30s; the browser auto-replies with a pong, which
// keeps the tunnel's WS warm in BOTH directions and resets Cloudflare's idle
// timer. The same round-trip lets us detect and reap dead/half-open sockets:
// a client that misses a full interval (no pong) is terminated. See the
// per-connection `pong` handler in the upgrade handler below.
const HEARTBEAT_MS = 30000;
const heartbeat = setInterval(() => {
  for (const ws of wss.clients) {
    if (ws.isAlive === false) { try { ws.terminate(); } catch (e) {} continue; }
    ws.isAlive = false;
    try { ws.ping(); } catch (e) {}
  }
}, HEARTBEAT_MS);
if (heartbeat.unref) heartbeat.unref(); // don't let the timer keep the process alive
wss.on('close', () => clearInterval(heartbeat));

const ADJ   = ['Swift','Calm','Brave','Lucky','Witty','Cosmic','Mellow','Nimble','Sunny','Quiet'];
const NOUN  = ['Otter','Falcon','Lynx','Heron','Bison','Marten','Raven','Ibex','Koi','Moth'];
const COLORS= ['#d97757','#9ec07c','#7aa2c9','#e0c285','#c08fc0','#7fc0bf','#e89177','#b3d99a'];
function autoName(i){ return ADJ[i % ADJ.length] + NOUN[(i * 7) % NOUN.length]; }

function broadcast(msg){ const s = JSON.stringify(msg); for (const ws of clients.keys()) if (ws.readyState === 1) ws.send(s); }
function roster(){ return [...clients.values()].map(c => ({ name: c.name, color: c.color, tab: c.tab, host: !!c.isHost })); }

server.on('upgrade', (req, socket, head) => {
  let url; try { url = new URL(req.url, 'http://localhost'); } catch { socket.destroy(); return; }
  if (url.searchParams.get('key') !== PASSWORD) { socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n'); socket.destroy(); return; }
  wss.handleUpgrade(req, socket, head, ws => {
    ws.isAlive = true;
    ws.on('pong', () => { ws.isAlive = true; }); // heartbeat: proof the peer is alive
    const idx = counter++;
    const reqName = (url.searchParams.get('name') || '').trim().slice(0, 24);
    const name = reqName || autoName(idx);
    const color = COLORS[idx % COLORS.length];
    // Host = presented the matching admin token (only the local host console has it).
    const isHost = !!ADMIN_TOKEN && url.searchParams.get('admin') === ADMIN_TOKEN;
    if (tabs.size === 0) createTab();   // spawn the first terminal on demand
    const firstTab = tabs.keys().next().value;
    clients.set(ws, { name, color, tab: firstTab, isHost });

    ws.send(JSON.stringify({
      type: 'init', you: { name, color, isHost }, users: roster(), cols: COLS, rows: ROWS,
      tabs: [...tabs.values()].map(t => ({ id: t.id, title: t.title, scrollback: t.scrollback })),
    }));
    broadcast({ type: 'sys', text: `${name} joined` });
    broadcast({ type: 'users', users: roster() });

    ws.on('message', raw => {
      let m; try { m = JSON.parse(raw.toString()); } catch { return; }
      const c = clients.get(ws); if (!c) return;
      if (m.type === 'in') {
        const t = tabs.get(m.tab);
        if (t && t.term) t.term.write(m.data);
      }
      else if (m.type === 'tab-new') {
        if (tabs.size >= MAX_TABS) { ws.send(JSON.stringify({ type: 'sys', text: `— tab limit (${MAX_TABS}) reached —` })); return; }
        const t = createTab();
        broadcast({ type: 'sys', text: `${c.name} opened tab "${t.title}"` });
        broadcastTabs();
        ws.send(JSON.stringify({ type: 'tab-created', id: t.id }));
      }
      else if (m.type === 'tab-close') {
        const t = tabs.get(m.tab);
        if (t) { broadcast({ type: 'sys', text: `${c.name} closed tab "${t.title}"` }); t.term.kill(); }
      }
      else if (m.type === 'kill-all') {
        if (!c.isHost) return;          // enforced server-side: only the host may stop the session
        broadcast({ type: 'sys', text: `— ${c.name} (host) stopped the session —` });
        broadcast({ type: 'killed', by: c.name });
        shutdown(`kill-all from host ${c.name}`);
      }
      else if (m.type === 'tab-rename') {
        const t = tabs.get(m.tab);
        const title = String(m.title || '').trim().slice(0, 32);
        if (t && title && title !== t.title) { t.title = title; broadcastTabs(); }
      }
      else if (m.type === 'tab-view') {
        if (tabs.has(m.tab) && c.tab !== m.tab) { c.tab = m.tab; broadcast({ type: 'users', users: roster() }); }
      }
      else if (m.type === 'chat') { const t = String(m.text || '').slice(0, 800); if (t) broadcast({ type: 'chat', name: c.name, color: c.color, text: t }); }
      else if (m.type === 'name') {
        const nn = String(m.name || '').trim().slice(0, 24);
        if (nn && nn !== c.name) { const old = c.name; c.name = nn; broadcast({ type: 'sys', text: `${old} → ${nn}` }); broadcast({ type: 'users', users: roster() }); }
      }
    });
    ws.on('close', () => {
      const c = clients.get(ws); clients.delete(ws);
      if (c) { broadcast({ type: 'sys', text: `${c.name} left` }); broadcast({ type: 'users', users: roster() }); }
    });
  });
});

server.listen(PORT, () => console.log(`collab terminal on http://localhost:${PORT} (cwd=${CWD})`));
