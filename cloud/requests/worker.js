// EZTiger song requests online (Cloudflare Worker).
//
// The same request list as app/requests/request-server.ps1, on the internet
// instead of the venue Wi-Fi: singers open the page on their own mobile data,
// and EZTiger (with the DJ link, ☰ Menu → Song requests) collects the songs
// the DJ adds to the singing queue. The DJ list works in any browser with the
// DJ link.
//
//   GET  /                 the singers' page (EZTiger publishes it: PUT /dj/page)
//   GET  /status           open or closed
//   POST /request          a singer's request
//   GET  /dj?key=          the DJ list         GET /poster?key=   the poster
//   GET  /dj/list?key=     the list as JSON    POST /dj/act, /dj/open, /dj/clear
//   GET  /app/next?key=    EZTiger: queued songs it hasn't taken yet
//   POST /app/sent?key=    EZTiger: that one is in Tonight's playlist
//   PUT  /dj/page?key=     EZTiger: the singers' page, gzipped (&name=&tz=)
//
// dj.html, qr.txt and poster.html are copied from request-server.ps1
// (make-pages.ps1), so both lists look and work the same.
import DJ_HTML from './dj.html';
import QR_JS from './qr.txt';
import POSTER_HTML from './poster.html';

const FIELDS = ['Id', 'At', 'Time', 'Singer', 'Title', 'Artist', 'Version', 'Disc', 'Others', 'Note', 'Status', 'Pos', 'Closed', 'Brand', 'Code', 'File', 'Path', 'Sent'];
const CLOSED_MSG = 'Sorry, no more requests tonight. The DJ has closed the list.';

const json = (v, status = 200) =>
  new Response(JSON.stringify(v), { status, headers: { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' } });
const html = (s, status = 200) =>
  new Response(s, { status, headers: { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' } });
const text = (s, status = 200) => new Response(s, { status, headers: { 'Content-Type': 'text/plain; charset=utf-8' } });
const escHtml = s => String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

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

async function meta(env) {
  const m = {};
  for (const r of (await env.DB.prepare('SELECT k, v FROM meta').all()).results) m[r.k] = r.v;
  return m;
}
const setMeta = (env, k, v) => env.DB.prepare('INSERT INTO meta (k, v) VALUES (?, ?) ON CONFLICT(k) DO UPDATE SET v = excluded.v').bind(k, String(v)).run();

// The DJ's own clock (EZTiger says its time zone when it publishes the page).
function local(m, date = new Date()) {
  const off = Number(m.tz || 0);
  return new Date(date.getTime() + off * 60000).toISOString().slice(0, 19);
}

async function rows(env, where = '', binds = []) {
  return (await env.DB.prepare(`SELECT * FROM requests ${where}`).bind(...binds).all()).results.map(r => {
    const o = {};
    for (const f of FIELDS) o[f] = r[f] == null ? '' : String(r[f]);
    return o;
  });
}

async function act(env, m, id, what) {
  const r = await env.DB.prepare('SELECT Id, Status, Pos FROM requests WHERE Id = ?').bind(id).first();
  if (!r) return;
  const now = local(m);
  const nextPos = async () => ((await env.DB.prepare("SELECT MAX(Pos) AS p FROM requests WHERE Status = 'queue'").first()).p || 0) + 1;
  switch (what) {
    case 'approve':
      if (r.Status === 'new') await env.DB.prepare("UPDATE requests SET Status = 'queue', Pos = ? WHERE Id = ?").bind(await nextPos(), id).run();
      break;
    case 'reject':
    case 'done':
      await env.DB.prepare('UPDATE requests SET Status = ?, Pos = NULL, Closed = ? WHERE Id = ?').bind(what === 'done' ? 'done' : 'rejected', now, id).run();
      break;
    case 'back':
      await env.DB.prepare("UPDATE requests SET Status = 'new', Pos = NULL, Closed = '' WHERE Id = ?").bind(id).run();
      break;
    case 'up':
    case 'down': {
      if (r.Status !== 'queue') return;
      const other = await env.DB.prepare(
        what === 'up'
          ? "SELECT Id, Pos FROM requests WHERE Status = 'queue' AND Pos < ? ORDER BY Pos DESC LIMIT 1"
          : "SELECT Id, Pos FROM requests WHERE Status = 'queue' AND Pos > ? ORDER BY Pos ASC LIMIT 1",
      ).bind(r.Pos).first();
      if (other) {
        await env.DB.batch([
          env.DB.prepare('UPDATE requests SET Pos = ? WHERE Id = ?').bind(other.Pos, id),
          env.DB.prepare('UPDATE requests SET Pos = ? WHERE Id = ?').bind(r.Pos, other.Id),
        ]);
      }
      break;
    }
  }
}

async function singersPage(request, env) {
  const gz = await env.PAGES.get('page.gz', 'arrayBuffer');
  if (!gz) return html('<!doctype html><meta name="viewport" content="width=device-width, initial-scale=1"><body style="font:18px system-ui;padding:24px;text-align:center"><h1>Song requests</h1><p>The song list isn\'t up yet – please ask the DJ.</p>', 503);
  const headers = { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-cache' };
  if (/gzip/.test(request.headers.get('Accept-Encoding') || '')) {
    return new Response(gz, { headers: { ...headers, 'Content-Encoding': 'gzip' }, encodeBody: 'manual' });
  }
  return new Response(new Blob([gz]).stream().pipeThrough(new DecompressionStream('gzip')), { headers });
}

async function handle(request, env, ctx) {
  const url = new URL(request.url);
  const path = url.pathname.replace(/\/+$/, '') || '/';
  const method = request.method;
  const djOk = sameKey(url.searchParams.get('key') || '', env.DJ_KEY || '');
  const link = url.origin;

  if (method === 'GET' && (path === '/' || path === '/index.html')) {
    ctx.waitUntil(setMeta(env, 'phone', (request.headers.get('CF-IPCountry') || 'a phone') + '|' + Date.now()).catch(() => {}));
    return singersPage(request, env);
  }
  if (method === 'GET' && path === '/status') {
    const m = await meta(env);
    return json({ open: m.closed !== '1', message: CLOSED_MSG });
  }
  if (method === 'POST' && path === '/request') {
    const m = await meta(env);
    if (m.closed === '1') return json({ ok: false, closed: true, error: CLOSED_MSG });
    const body = await request.text();
    if (body.length > 32768) return json({ ok: false, error: 'Too large' }, 413);
    const f = Object.fromEntries(new URLSearchParams(body));
    const singer = clean(f.singer, 40), title = clean(f.title, 120);
    if (!singer || !title) return json({ ok: false, error: 'Please put your name and choose a song.' });
    const now = new Date(), at = local(m, now);
    // The same singer and song again within 2 minutes is a repeat tap: keep one.
    const dup = await env.DB.prepare('SELECT Id FROM requests WHERE Singer = ? AND Title = ? AND At > ? LIMIT 1')
      .bind(singer, title, local(m, new Date(now.getTime() - 120000))).first();
    if (!dup) {
      await env.DB.prepare(
        `INSERT INTO requests (Id, At, Time, Singer, Title, Artist, Version, Disc, Others, Note, Status, Pos, Closed, Brand, Code, File, Path, Sent)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'new', NULL, '', ?, ?, '', '', '')`,
      ).bind(String(now.getTime()) + String(Math.floor(Math.random() * 1000)).padStart(3, '0'), at, at.slice(11, 16), singer, title,
        clean(f.artist, 120), clean(f.version, 40), clean(f.disc, 60), clean(f.others, 300), clean(f.note, 200),
        clean(f.brand, 40), clean(f.code, 60)).run();
    }
    const w = await env.DB.prepare("SELECT COUNT(*) AS n FROM requests WHERE Status IN ('new', 'queue')").first();
    return json({ ok: true, waiting: w.n });
  }

  // ---------- Everything below needs the DJ link's code ----------
  if (!djOk) {
    if (path.startsWith('/dj') || path === '/poster') return text('The DJ list needs the DJ link.', 403);
    if (path.startsWith('/app')) return json([], 403);
    return text('Not found', 404);
  }
  const key = env.DJ_KEY;

  if (method === 'GET' && path === '/dj') {
    const m = await meta(env);
    const page = DJ_HTML
      .replace('Singers open <b>__LINK__</b> on the Wi-Fi', 'Singers open <b>__LINK__</b> on their phones')
      .replace('Join the phone to this Wi-Fi (turn off mobile data) and scan the QR code.', 'Scan the QR code with a phone to try it.')
      .replace('The list is saved on this PC and kept until you clear it.', 'The list is kept online until you clear it.')
      .replace('A copy is saved in the requests folder first.', 'A copy is kept online first.')
      .replaceAll('__QRJS__', QR_JS).replaceAll('__NAME__', escHtml(m.name || 'Karaoke'))
      .replaceAll('__LINK__', link).replaceAll('__KEY__', key);
    return html(page);
  }
  if (method === 'GET' && path === '/poster') {
    const m = await meta(env);
    const logo = (await env.PAGES.get('logo')) || '';
    const page = POSTER_HTML
      .replace('<li>Join the Wi-Fi here</li>', '')
      .replaceAll('__QRJS__', QR_JS).replaceAll('__LINK__', link).replaceAll('__NAME__', escHtml(m.name || 'Karaoke'))
      .replaceAll('__LOGO__', logo).replaceAll('__POWERED__', '');
    return html(page);
  }
  if (method === 'GET' && path === '/dj/list') {
    const m = await meta(env);
    const app = m.app ? Math.round((Date.now() - Number(m.app)) / 1000) : -1;
    let phone = '';
    if (m.phone) {
      const [where, ms] = m.phone.split('|');
      phone = `${where} at ${local(m, new Date(Number(ms))).slice(11, 16)}`;
    }
    return json({ app, link, phone, blocked: '', open: m.closed !== '1', rows: await rows(env, 'ORDER BY At') });
  }
  if (method === 'POST' && path === '/dj/act') {
    await act(env, await meta(env), url.searchParams.get('id') || '', url.searchParams.get('do') || '');
    return json({ ok: true });
  }
  if (method === 'POST' && path === '/dj/open') {
    await setMeta(env, 'closed', url.searchParams.get('open') === '0' ? '1' : '0');
    return json({ ok: true });
  }
  if (method === 'POST' && path === '/dj/clear') {
    const m = await meta(env);
    await env.DB.batch([
      env.DB.prepare('INSERT INTO cleared SELECT ?, * FROM requests').bind(local(m)),
      env.DB.prepare('DELETE FROM requests'),
    ]);
    return json({ ok: true });
  }
  if (method === 'PUT' && path === '/dj/page') {
    const gz = await request.arrayBuffer();
    if (gz.byteLength < 100 || gz.byteLength > 24 * 1024 * 1024) return json({ ok: false, error: 'The page is empty or too big.' }, 400);
    const page = await new Response(new Blob([gz]).stream().pipeThrough(new DecompressionStream('gzip'))).text();
    if (!page.includes('<html')) return json({ ok: false, error: 'That is not the singers\' page.' }, 400);
    await env.PAGES.put('page.gz', gz);
    const logo = /src="data:image\/png;base64,([A-Za-z0-9+/=]+)"/.exec(page);
    await env.PAGES.put('logo', logo ? logo[1] : '');
    const name = clean(url.searchParams.get('name'), 80);
    if (name) await setMeta(env, 'name', name);
    const tz = Number(url.searchParams.get('tz'));
    if (Number.isFinite(tz) && Math.abs(tz) <= 14 * 60) await setMeta(env, 'tz', Math.round(tz));
    return json({ ok: true, link });
  }
  if (method === 'GET' && path === '/app/next') {
    const m = await meta(env);
    if (!m.app || Date.now() - Number(m.app) > 5000) await setMeta(env, 'app', Date.now());
    const list = await rows(env, "WHERE Status = 'queue' AND (Sent IS NULL OR Sent = '') ORDER BY Pos");
    return json(list.map(r => ({ Id: r.Id, Singer: r.Singer, Title: r.Title, Artist: r.Artist, Version: r.Version, Disc: r.Disc, File: r.File, Path: r.Path })));
  }
  if (method === 'POST' && path === '/app/sent') {
    await setMeta(env, 'app', Date.now());
    await env.DB.prepare('UPDATE requests SET Sent = ? WHERE Id = ?')
      .bind(url.searchParams.get('found') === '0' ? 'missing' : 'yes', url.searchParams.get('id') || '').run();
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
