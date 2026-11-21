// EZTiger song requests online (Cloudflare Worker).
//
// The same request list as app/requests/request-server.ps1, on the internet
// instead of the venue Wi-Fi: singers open the page on their own mobile data,
// and EZTiger (with the DJ link, ☰ Menu → Song requests) collects the songs
// the DJ adds to the singing queue. The DJ list works in any browser with the
// DJ link.
//
// One Worker serves many DJs. The owner's list is at the root (its code is
// the DJ_KEY secret); every other DJ gets their own list under /v/<id>/
// (POST /register from EZTiger, when the ALLOW_SIGNUPS variable is "yes").
// Each DJ's page, list and settings are kept apart by that id.
//
//   GET  /                 the singers' page (EZTiger publishes it: PUT /dj/page)
//   GET  /status           open or closed
//   POST /request          a singer's request
//   GET  /dj?key=          the DJ list         GET /poster?key=   the poster
//   GET  /dj/list?key=     the list as JSON    POST /dj/act, /dj/open, /dj/clear
//   GET  /app/next?key=    EZTiger: queued songs it hasn't taken yet
//   POST /app/sent?key=    EZTiger: that one is in Tonight's playlist
//   PUT  /dj/page?key=     EZTiger: the singers' page, gzipped (&name=&tz=)
//   POST /register         EZTiger: a new DJ's own list (name=) → { link, dj }
// The same paths work under /v/<id>/ for each DJ.
//
// dj.html, qr.txt and poster.html are copied from request-server.ps1
// (make-pages.ps1), so both lists look and work the same.
import DJ_HTML from './dj.html';
import QR_JS from './qr.txt';
import POSTER_HTML from './poster.html';
import ICON_48 from './icon-48.png';
import ICON_192 from './icon-192.png';
import ICON_512 from './icon-512.png';

// The tiger icon, so the DJ list has its own icon in the browser tab and,
// installed as an app (Chrome ⋮ → Cast, save and share → Install page as app),
// its own window and taskbar button.
const ICONS = { '/icon-48.png': ICON_48, '/icon-192.png': ICON_192, '/icon-512.png': ICON_512, '/favicon.ico': ICON_48 };
const ICON_HEAD = '<link rel="icon" type="image/png" sizes="48x48" href="/icon-48.png">' +
  '<link rel="apple-touch-icon" href="/icon-192.png"><meta name="theme-color" content="#14151C">';
// Src: 'dj' for a song the DJ put in Tonight's playlist in EZTiger with a
// singer's name (a paper slip, say): POST /app/sync. Shown shaded.
const FIELDS = ['Id', 'At', 'Time', 'Singer', 'Title', 'Artist', 'Version', 'Disc', 'Others', 'Note', 'Status', 'Pos', 'Closed', 'Brand', 'Code', 'File', 'Path', 'Sent', 'Src'];
const CLOSED_MSG = 'Sorry, no more requests tonight. The DJ has closed the list.';
const SIGNUPS_PER_IP_PER_DAY = 3, SIGNUPS_PER_DAY = 100;

const json = (v, status = 200) =>
  new Response(JSON.stringify(v), { status, headers: { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' } });
const html = (s, status = 200) =>
  new Response(s, { status, headers: { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' } });
const text = (s, status = 200) => new Response(s, { status, headers: { 'Content-Type': 'text/plain; charset=utf-8' } });
const escHtml = s => String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const notYet = msg => html('<!doctype html><meta name="viewport" content="width=device-width, initial-scale=1"><body style="font:18px system-ui;padding:24px;text-align:center"><h1>Song requests</h1><p>' + msg + '</p>', 503);

function clean(s, max) {
  s = String(s ?? '').replace(/[\x00-\x1f]+/g, ' ').trim();
  if (s.length > max) s = s.slice(0, max);
  if (/^[=+\-@]/.test(s)) s = "'" + s;   // so Excel never runs it as a formula
  return s;
}

function sameKey(a, b) {
  if (!a || !b || a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}

function randomCode(n) {
  const chars = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  const b = crypto.getRandomValues(new Uint8Array(n));
  return [...b].map(x => chars[x % chars.length]).join('');
}
function randomId() {
  const chars = 'abcdefghjkmnpqrstuvwxyz23456789';
  return [...crypto.getRandomValues(new Uint8Array(8))].map(x => chars[x % chars.length]).join('');
}

// ---------- The tables (made the first time, on a new Cloudflare account) ----------
const SCHEMA = [
  `CREATE TABLE IF NOT EXISTS requests (
    Id TEXT PRIMARY KEY, At TEXT, Time TEXT, Singer TEXT, Title TEXT, Artist TEXT, Version TEXT, Disc TEXT,
    Others TEXT, Note TEXT, Status TEXT, Pos INTEGER, Closed TEXT, Brand TEXT, Code TEXT, File TEXT, Path TEXT, Sent TEXT,
    T TEXT NOT NULL DEFAULT '', Src TEXT NOT NULL DEFAULT '')`,
  `CREATE TABLE IF NOT EXISTS cleared (
    ClearedAt TEXT, Id TEXT, At TEXT, Time TEXT, Singer TEXT, Title TEXT, Artist TEXT, Version TEXT, Disc TEXT,
    Others TEXT, Note TEXT, Status TEXT, Pos INTEGER, Closed TEXT, Brand TEXT, Code TEXT, File TEXT, Path TEXT, Sent TEXT,
    T TEXT NOT NULL DEFAULT '', Src TEXT NOT NULL DEFAULT '')`,
  `CREATE TABLE IF NOT EXISTS meta2 (T TEXT NOT NULL, k TEXT NOT NULL, v TEXT, PRIMARY KEY (T, k))`,
  `CREATE TABLE IF NOT EXISTS tenants (id TEXT PRIMARY KEY, key TEXT NOT NULL, name TEXT, created INTEGER, ip TEXT)`,
  `CREATE INDEX IF NOT EXISTS requests_t ON requests (T, Status)`,
];
let schemaReady = false;
async function ensureSchema(env) {
  if (schemaReady) return;
  await env.DB.batch(SCHEMA.map(s => env.DB.prepare(s)));
  // Lists made before Src was added get the column (an error just means it's there).
  for (const t of ['requests', 'cleared']) {
    try {
      await env.DB.prepare(`ALTER TABLE ${t} ADD COLUMN Src TEXT NOT NULL DEFAULT ''`).run();
    } catch (_) {}
  }
  schemaReady = true;
}

// ---------- One DJ's list ----------
async function meta(env, T) {
  const m = {};
  for (const r of (await env.DB.prepare('SELECT k, v FROM meta2 WHERE T = ?').bind(T).all()).results) m[r.k] = r.v;
  return m;
}
const setMeta = (env, T, k, v) =>
  env.DB.prepare('INSERT INTO meta2 (T, k, v) VALUES (?, ?, ?) ON CONFLICT(T, k) DO UPDATE SET v = excluded.v').bind(T, k, String(v)).run();
const pageKey = (T, what) => (T ? `${what}:${T}` : what);

// The DJ's own clock (EZTiger says its time zone when it publishes the page).
function local(m, date = new Date()) {
  const off = Number(m.tz || 0);
  return new Date(date.getTime() + off * 60000).toISOString().slice(0, 19);
}

async function rows(env, T, where = '', binds = []) {
  return (await env.DB.prepare(`SELECT * FROM requests WHERE T = ? ${where}`).bind(T, ...binds).all()).results.map(r => {
    const o = {};
    for (const f of FIELDS) o[f] = r[f] == null ? '' : String(r[f]);
    return o;
  });
}

async function act(env, T, m, id, what) {
  const r = await env.DB.prepare('SELECT Id, Status, Pos FROM requests WHERE T = ? AND Id = ?').bind(T, id).first();
  if (!r) return;
  const now = local(m);
  const nextPos = async () => ((await env.DB.prepare("SELECT MAX(Pos) AS p FROM requests WHERE T = ? AND Status = 'queue'").bind(T).first()).p || 0) + 1;
  switch (what) {
    case 'approve':
      if (r.Status === 'new') await env.DB.prepare("UPDATE requests SET Status = 'queue', Pos = ? WHERE T = ? AND Id = ?").bind(await nextPos(), T, id).run();
      break;
    case 'reject':
    case 'done':
      await env.DB.prepare('UPDATE requests SET Status = ?, Pos = NULL, Closed = ? WHERE T = ? AND Id = ?').bind(what === 'done' ? 'done' : 'rejected', now, T, id).run();
      break;
    case 'back':
      await env.DB.prepare("UPDATE requests SET Status = 'new', Pos = NULL, Closed = '' WHERE T = ? AND Id = ?").bind(T, id).run();
      break;
    case 'up':
    case 'down': {
      if (r.Status !== 'queue') return;
      const other = await env.DB.prepare(
        what === 'up'
          ? "SELECT Id, Pos FROM requests WHERE T = ? AND Status = 'queue' AND Pos < ? ORDER BY Pos DESC LIMIT 1"
          : "SELECT Id, Pos FROM requests WHERE T = ? AND Status = 'queue' AND Pos > ? ORDER BY Pos ASC LIMIT 1",
      ).bind(T, r.Pos).first();
      if (other) {
        await env.DB.batch([
          env.DB.prepare('UPDATE requests SET Pos = ? WHERE T = ? AND Id = ?').bind(other.Pos, T, id),
          env.DB.prepare('UPDATE requests SET Pos = ? WHERE T = ? AND Id = ?').bind(r.Pos, T, other.Id),
        ]);
      }
      break;
    }
  }
}

async function singersPage(request, env, T) {
  const gz = await env.PAGES.get(pageKey(T, 'page.gz'), 'arrayBuffer');
  if (!gz) return notYet('The song list isn\'t up yet – please ask the DJ.');
  const headers = { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-cache' };
  if (/gzip/.test(request.headers.get('Accept-Encoding') || '')) {
    return new Response(gz, { headers: { ...headers, 'Content-Encoding': 'gzip' }, encodeBody: 'manual' });
  }
  return new Response(new Blob([gz]).stream().pipeThrough(new DecompressionStream('gzip')), { headers });
}

// A new DJ's own list (EZTiger: ☰ Menu → Song requests → Get my online request page).
async function register(request, env, origin) {
  if (String(env.ALLOW_SIGNUPS || '').trim().toLowerCase() !== 'yes') {
    return json({ ok: false, error: 'This request service isn\'t taking new DJs.' }, 403);
  }
  const ip = request.headers.get('CF-Connecting-IP') || '';
  const day = Date.now() - 86400000;
  const mine = await env.DB.prepare('SELECT COUNT(*) AS n FROM tenants WHERE ip = ? AND created > ?').bind(ip, day).first();
  const all = await env.DB.prepare('SELECT COUNT(*) AS n FROM tenants WHERE created > ?').bind(day).first();
  if (mine.n >= SIGNUPS_PER_IP_PER_DAY || all.n >= SIGNUPS_PER_DAY) {
    return json({ ok: false, error: 'Too many new request pages today – please try again tomorrow.' }, 429);
  }
  const body = Object.fromEntries(new URLSearchParams(await request.text()));
  const name = clean(body.name, 80) || 'Karaoke';
  const id = randomId(), key = randomCode(20);
  await env.DB.prepare('INSERT INTO tenants (id, key, name, created, ip) VALUES (?, ?, ?, ?, ?)').bind(id, key, name, Date.now(), ip).run();
  await setMeta(env, id, 'name', name);
  const link = `${origin}/v/${id}`;
  return json({ ok: true, link: link + '/', dj: `${link}/dj?key=${key}` });
}

async function handle(request, env, ctx) {
  await ensureSchema(env);
  const url = new URL(request.url);
  const method = request.method;

  // Whose list: the owner's at the root, or a DJ's under /v/<id>/.
  let T = '', prefix = '', djKey = String(env.DJ_KEY || '').trim();   // a secret piped in can end with a line break
  let raw = url.pathname;
  const v = /^\/v\/([a-z0-9]{6,16})(\/.*)?$/.exec(raw);
  if (v) {
    T = v[1]; prefix = '/v/' + T; raw = v[2] || '';
    const t = await env.DB.prepare('SELECT key FROM tenants WHERE id = ?').bind(T).first();
    if (!t) return text('There is no request page here. Check the link with your DJ.', 404);
    djKey = t.key;
    // The singers' page asks for "request" and "status" next to itself, so it needs the closing slash.
    if (raw === '' && method === 'GET') return Response.redirect(url.origin + prefix + '/' + url.search, 301);
  }
  const path = raw.replace(/\/+$/, '') || '/';
  const djOk = sameKey((url.searchParams.get('key') || '').trim(), djKey);
  const link = url.origin + prefix;

  if (method === 'GET' && ICONS[path] && !T) {
    return new Response(ICONS[path], { headers: { 'Content-Type': 'image/png', 'Cache-Control': 'public, max-age=86400' } });
  }
  if (method === 'POST' && path === '/register' && !T) return register(request, env, url.origin);
  if (method === 'GET' && (path === '/' || path === '/index.html')) {
    ctx.waitUntil(setMeta(env, T, 'phone', (request.headers.get('CF-IPCountry') || 'a phone') + '|' + Date.now()).catch(() => {}));
    return singersPage(request, env, T);
  }
  if (method === 'GET' && path === '/status') {
    const m = await meta(env, T);
    return json({ open: m.closed !== '1', message: CLOSED_MSG });
  }
  if (method === 'POST' && path === '/request') {
    const m = await meta(env, T);
    if (m.closed === '1') return json({ ok: false, closed: true, error: CLOSED_MSG });
    const body = await request.text();
    if (body.length > 32768) return json({ ok: false, error: 'Too large' }, 413);
    const f = Object.fromEntries(new URLSearchParams(body));
    const singer = clean(f.singer, 40), title = clean(f.title, 120);
    if (!singer || !title) return json({ ok: false, error: 'Please put your name and choose a song.' });
    const now = new Date(), at = local(m, now);
    // The same singer and song again within 2 minutes is a repeat tap: keep one.
    const dup = await env.DB.prepare('SELECT Id FROM requests WHERE T = ? AND Singer = ? AND Title = ? AND At > ? LIMIT 1')
      .bind(T, singer, title, local(m, new Date(now.getTime() - 120000))).first();
    if (!dup) {
      await env.DB.prepare(
        `INSERT INTO requests (Id, At, Time, Singer, Title, Artist, Version, Disc, Others, Note, Status, Pos, Closed, Brand, Code, File, Path, Sent, T)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'new', NULL, '', ?, ?, '', '', '', ?)`,
      ).bind(String(now.getTime()) + String(Math.floor(Math.random() * 1e6)).padStart(6, '0'), at, at.slice(11, 16), singer, title,
        clean(f.artist, 120), clean(f.version, 40), clean(f.disc, 60), clean(f.others, 300), clean(f.note, 200),
        clean(f.brand, 40), clean(f.code, 60), T).run();
    }
    const w = await env.DB.prepare("SELECT COUNT(*) AS n FROM requests WHERE T = ? AND Status IN ('new', 'queue')").bind(T).first();
    return json({ ok: true, waiting: w.n });
  }

  // ---------- Everything below needs the DJ link's code ----------
  if (!djOk) {
    if (!djKey) return notYet('This request list isn\'t set up yet: the owner needs to add the DJ_KEY secret.');
    if (path.startsWith('/dj') || path === '/poster') return text('The DJ list needs the DJ link.', 403);
    if (path.startsWith('/app')) return json([], 403);
    return text('Not found', 404);
  }
  const key = djKey, k = encodeURIComponent(key);

  if (method === 'GET' && path === '/dj') {
    const m = await meta(env, T);
    const page = DJ_HTML
      .replace('Singers open <b>__LINK__</b> on the Wi-Fi', 'Singers open <b>__LINK__</b> on their phones')
      .replace('Join the phone to this Wi-Fi (turn off mobile data) and scan the QR code.', 'Scan the QR code with a phone to try it.')
      .replace('The list is saved on this PC and kept until you clear it.', 'The list is kept online until you clear it.')
      .replace('A copy is saved in the requests folder first.', 'A copy is kept online first.')
      .replaceAll("fetch('/dj/", `fetch('${prefix}/dj/`).replaceAll('href="/poster?', `href="${prefix}/poster?`)
      .replaceAll('__QRJS__', QR_JS).replaceAll('__NAME__', escHtml(m.name || 'Karaoke'))
      .replaceAll('__LINK__', link).replaceAll('__KEY__', key)
      .replace('</title>', `</title>${ICON_HEAD}<link rel="manifest" href="${prefix}/dj/app.webmanifest?key=${k}">`);
    return html(page);
  }
  if (method === 'GET' && path === '/dj/app.webmanifest') {
    const m = await meta(env, T);
    return new Response(JSON.stringify({
      name: (m.name || 'Karaoke') + ' · Requests', short_name: 'Requests',
      id: prefix + '/dj', start_url: `${prefix}/dj?key=${k}`, scope: prefix + '/dj',
      display: 'standalone', background_color: '#14151C', theme_color: '#14151C',
      icons: [
        { src: '/icon-192.png', sizes: '192x192', type: 'image/png' },
        { src: '/icon-512.png', sizes: '512x512', type: 'image/png' },
      ],
    }), { headers: { 'Content-Type': 'application/manifest+json', 'Cache-Control': 'no-store' } });
  }
  if (method === 'GET' && path === '/poster') {
    const m = await meta(env, T);
    const logo = (await env.PAGES.get(pageKey(T, 'logo'))) || '';
    const page = POSTER_HTML
      .replace('<li>Join the Wi-Fi here</li>', '')
      .replaceAll('__QRJS__', QR_JS).replaceAll('__LINK__', link).replaceAll('__NAME__', escHtml(m.name || 'Karaoke'))
      .replaceAll('__LOGO__', logo).replaceAll('__POWERED__', '')
      .replace('</title>', '</title>' + ICON_HEAD);
    return html(page);
  }
  if (method === 'GET' && path === '/dj/list') {
    const m = await meta(env, T);
    // EZTiger's "still here" is saved once a minute (to stay within the free plan), so up to 90 s counts as now.
    const age = m.app ? Math.round((Date.now() - Number(m.app)) / 1000) : -1;
    const app = age >= 0 && age < 90 ? 0 : age;
    let phone = '';
    if (m.phone) {
      const [where, ms] = m.phone.split('|');
      phone = `${where} at ${local(m, new Date(Number(ms))).slice(11, 16)}`;
    }
    return json({ app, link, phone, blocked: '', open: m.closed !== '1', rows: await rows(env, T, 'ORDER BY At') });
  }
  if (method === 'POST' && path === '/dj/act') {
    await act(env, T, await meta(env, T), url.searchParams.get('id') || '', url.searchParams.get('do') || '');
    return json({ ok: true });
  }
  if (method === 'POST' && path === '/dj/open') {
    await setMeta(env, T, 'closed', url.searchParams.get('open') === '0' ? '1' : '0');
    return json({ ok: true });
  }
  if (method === 'POST' && path === '/dj/clear') {
    const m = await meta(env, T);
    const cols = FIELDS.join(', ');
    await env.DB.batch([
      env.DB.prepare(`INSERT INTO cleared (ClearedAt, ${cols}, T) SELECT ?, ${cols}, T FROM requests WHERE T = ?`).bind(local(m), T),
      env.DB.prepare('DELETE FROM requests WHERE T = ?').bind(T),
    ]);
    return json({ ok: true });
  }
  if (method === 'PUT' && path === '/dj/page') {
    const gz = await request.arrayBuffer();
    if (gz.byteLength < 100 || gz.byteLength > 24 * 1024 * 1024) return json({ ok: false, error: 'The page is empty or too big.' }, 400);
    const page = await new Response(new Blob([gz]).stream().pipeThrough(new DecompressionStream('gzip'))).text();
    if (!page.includes('<html')) return json({ ok: false, error: 'That is not the singers\' page.' }, 400);
    await env.PAGES.put(pageKey(T, 'page.gz'), gz);
    const logo = /src="data:image\/png;base64,([A-Za-z0-9+/=]+)"/.exec(page);
    await env.PAGES.put(pageKey(T, 'logo'), logo ? logo[1] : '');
    const name = clean(url.searchParams.get('name'), 80);
    if (name) await setMeta(env, T, 'name', name);
    const tz = Number(url.searchParams.get('tz'));
    if (Number.isFinite(tz) && Math.abs(tz) <= 14 * 60) await setMeta(env, T, 'tz', Math.round(tz));
    return json({ ok: true, link });
  }
  if (method === 'GET' && path === '/app/next') {
    const m = await meta(env, T);
    if (!m.app || Date.now() - Number(m.app) > 60000) await setMeta(env, T, 'app', Date.now());
    const list = await rows(env, T, "AND Status = 'queue' AND (Sent IS NULL OR Sent = '') ORDER BY Pos");
    return json(list.map(r => ({ Id: r.Id, Singer: r.Singer, Title: r.Title, Artist: r.Artist, Version: r.Version, Disc: r.Disc, File: r.File, Path: r.Path })));
  }
  // EZTiger sends the songs in Tonight's playlist that have a singer's name
  // but didn't come from this list (paper slips, songs added by hand): they
  // join the singing queue marked as the DJ's, are ticked off when played,
  // and go when taken out of the playlist. [{id, singer, title, artist, played}]
  if (method === 'POST' && path === '/app/sync') {
    let items;
    try {
      items = JSON.parse((await request.text()) || '[]');
    } catch (_) {
      items = null;
    }
    if (!Array.isArray(items) || items.length > 500) return json({ ok: false }, 400);
    const m = await meta(env, T);
    if (!m.app || Date.now() - Number(m.app) > 60000) await setMeta(env, T, 'app', Date.now());
    const now = local(m);
    const all = await rows(env, T);
    const byId = new Map(all.map(r => [r.Id, r]));
    let pos = all.filter(r => r.Status === 'queue').reduce((p, r) => Math.max(p, Number(r.Pos) || 0), 0);
    const keep = new Set(), writes = [];
    for (const it of items) {
      if (!it || it.id == null) continue;
      const id = 'dj-' + String(it.id).slice(0, 20);
      keep.add(id);
      const singer = clean(it.singer, 40), title = clean(it.title, 120), artist = clean(it.artist, 120);
      const r = byId.get(id);
      if (r) {
        if (r.Singer !== singer || r.Title !== title || r.Artist !== artist) {
          writes.push(env.DB.prepare('UPDATE requests SET Singer = ?, Title = ?, Artist = ? WHERE T = ? AND Id = ?').bind(singer, title, artist, T, id));
        }
        if (it.played && (r.Status === 'queue' || r.Status === 'new')) {
          writes.push(env.DB.prepare("UPDATE requests SET Status = 'done', Pos = NULL, Closed = ? WHERE T = ? AND Id = ?").bind(now, T, id));
        }
        continue;
      }
      // Already on the list as a singer's own request: not twice.
      const same = s => s.toLowerCase();
      if (all.some(o => o.Src !== 'dj' && o.Status !== 'rejected' && same(o.Singer) === same(singer) && same(o.Title) === same(title))) continue;
      const played = !!it.played;
      writes.push(env.DB.prepare(
        `INSERT INTO requests (Id, At, Time, Singer, Title, Artist, Version, Disc, Others, Note, Status, Pos, Closed, Brand, Code, File, Path, Sent, T, Src)
         VALUES (?, ?, ?, ?, ?, ?, '', '', '', '', ?, ?, ?, '', '', '', '', 'yes', ?, 'dj')`,
      ).bind(id, now, now.slice(11, 16), singer, title, artist, played ? 'done' : 'queue', played ? null : ++pos, played ? now : '', T));
    }
    for (const r of all) {
      if (r.Src === 'dj' && !keep.has(r.Id)) writes.push(env.DB.prepare('DELETE FROM requests WHERE T = ? AND Id = ?').bind(T, r.Id));
    }
    if (writes.length) await env.DB.batch(writes);
    return json({ ok: true });
  }
  if (method === 'POST' && path === '/app/sent') {
    await setMeta(env, T, 'app', Date.now());
    await env.DB.prepare('UPDATE requests SET Sent = ? WHERE T = ? AND Id = ?')
      .bind(url.searchParams.get('found') === '0' ? 'missing' : 'yes', T, url.searchParams.get('id') || '').run();
    return json({ ok: true });
  }
  return text('Not found', 404);
}

export default {
  async fetch(request, env, ctx) {
    try {
      return await handle(request, env, ctx);
    } catch (e) {
      return json({ ok: false, error: 'Something went wrong: ' + (e && e.message ? e.message : e) }, 500);
    }
  },
};
