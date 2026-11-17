# Song requests on the venue Wi-Fi, no internet needed.
#
# Run it on the DJ PC (double-click "Start requests.cmd"). It:
#   - serves request-songs.html to any phone on the same Wi-Fi/router,
#     at the link it prints (e.g. http://192.168.1.20:8080),
#   - takes the singers' requests and keeps the list in requests\request-list.csv.
#     It stays there when the window is closed, until the DJ clears it
#     ("Clear whole list", which first saves a copy as requests\cleared <date>.csv),
#   - opens the DJ list on this PC (http://localhost:8080/dj), which updates
#     by itself. New requests wait in "New requests" until the DJ adds them to
#     the singing queue (or rejects them); the queue can be put in any order;
#     sung and rejected requests go to a box at the bottom.
#     The DJ list also works on a tablet with the "DJ link" it prints (it has
#     a code in it, so singers can't open it).
# The first time, Windows asks whether PowerShell may use the network: tick
# "Private networks" and Allow.
param(
  [int]$Port = 8080,
  [string]$Page = (Join-Path $PSScriptRoot 'request-songs.html'),
  [string]$Folder = (Join-Path $PSScriptRoot 'requests'),
  [switch]$NoBrowser
)
$ErrorActionPreference = 'Stop'
Write-Host '  Starting...'
if (-not (Test-Path $Page)) { throw "Page not found: $Page (run build_songbook.ps1 first)" }
New-Item -ItemType Directory -Force $Folder | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding $false
$latin1 = [Text.Encoding]::GetEncoding(28591)

# ---------- The page, and a zipped copy for phones (about a quarter of the size) ----------
$pageBytes = [IO.File]::ReadAllBytes($Page)

# ---------- Venue branding (shared with Music Bingo and Quiz Night) ----------
# When a venue is switched on in any EZTiger app (Documents\EZTiger Venues\active.json), singers' phones and
# the poster show the venue's logo and name, with a small "Powered by EZTiger Entertainment" line.
$venuesDir = if ($env:EZ_VENUES) { $env:EZ_VENUES } else { Join-Path $env:USERPROFILE 'Documents\EZTiger Venues' }   # same folder the Python apps use
$imgTypes = @{ '.png' = 'image/png'; '.jpg' = 'image/jpeg'; '.jpeg' = 'image/jpeg'; '.webp' = 'image/webp'; '.gif' = 'image/gif'; '.svg' = 'image/svg+xml' }
function Get-Venue {
  try {
    $a = [IO.File]::ReadAllText((Join-Path $venuesDir 'active.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json
    if (-not $a.on -or -not $a.venue -or $a.venue -match '[\\/:*?"<>|]' -or $a.venue -match '^\.') { return $null }
    $d = Join-Path $venuesDir $a.venue
    $v = [IO.File]::ReadAllText((Join-Path $d 'venue.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json
    $base = '/venue/img/' + [Uri]::EscapeDataString($a.venue) + '/'
    $logo = if ($v.logo -and (Test-Path -LiteralPath (Join-Path $d $v.logo))) { $base + [Uri]::EscapeDataString($v.logo) } else { '' }
    $photos = @($v.photos | Where-Object { $_ -and (Test-Path -LiteralPath (Join-Path $d $_)) } | ForEach-Object { $base + [Uri]::EscapeDataString($_) })
    $name = if ($v.name) { [string]$v.name } else { [string]$a.venue }
    return [pscustomobject]@{ id = [string]$a.venue; name = $name; tagline = [string]$v.tagline; logoUrl = $logo; photoUrls = $photos; poweredBy = 'Powered by EZTiger Entertainment' }
  } catch { return $null }
}
function Venue-Json {
  $v = Get-Venue
  if (-not $v) { return '{"venue":null}' }
  '{"venue":{"id":' + (JStr $v.id) + ',"name":' + (JStr $v.name) + ',"tagline":' + (JStr $v.tagline) + ',"logoUrl":' + (JStr $v.logoUrl) +
    ',"photoUrls":[' + (($v.photoUrls | ForEach-Object { JStr $_ }) -join ',') + '],"poweredBy":' + (JStr $v.poweredBy) + '}}'
}
# The singers' page swaps in the venue's logo and name when one is on.
$venueJs = @'
<script>
fetch('/venue/active.json', { cache: 'no-store' }).then(r => r.json()).then(({ venue: v }) => {
  if (!v) return;
  const h1 = document.querySelector('header h1'); if (h1) h1.textContent = v.name;
  if (v.logoUrl) document.querySelectorAll('img[src^="data:image/png"]').forEach(i => { i.src = v.logoUrl; i.style.objectFit = 'contain'; });
  const f = document.querySelector('footer'); if (f) f.innerHTML = f.innerHTML.replace(/Powered by EZTiger(?! Entertainment)/, v.poweredBy);
  document.title = document.title.replace(/^.*? · /, v.name + ' · ');
}).catch(() => {});
</script>
'@
$pageText = $utf8.GetString($pageBytes)
$at = $pageText.LastIndexOf('</body>')
if ($at -gt 0) { $pageBytes = $utf8.GetBytes($pageText.Substring(0, $at) + $venueJs + $pageText.Substring($at)) }
Remove-Variable pageText
$ms = New-Object IO.MemoryStream
$gz = New-Object IO.Compression.GZipStream($ms, [IO.Compression.CompressionMode]::Compress)
$gz.Write($pageBytes, 0, $pageBytes.Length); $gz.Close()
$pageGz = $ms.ToArray()
$showName = 'Karaoke'
if ($utf8.GetString($pageBytes, 0, [Math]::Min(4000, $pageBytes.Length)) -match '<title>(.*?) · ') { $showName = [Net.WebUtility]::HtmlDecode($matches[1]) }

# ---------- The request list: kept until the DJ clears it ----------
# Status: new (waiting for the DJ), queue (approved; Pos is its place),
# done (sung) or rejected. At / Closed: when it came in / was sung or rejected.
# Brand / Code: the version asked for; File / Path: that song's file inside the
# library and its full path; Sent: yes once EZTiger has put it in Tonight's
# playlist (missing if EZTiger couldn't find the song).
$fields = 'Id','At','Time','Singer','Title','Artist','Version','Disc','Others','Note','Status','Pos','Closed','Brand','Code','File','Path','Sent'
$listFile = Join-Path $Folder 'request-list.csv'
$list = New-Object System.Collections.Generic.List[object]
if (Test-Path $listFile) {
  foreach ($r in Import-Csv $listFile) {
    foreach ($f in $fields) { if (-not ($r.PSObject.Properties.Name -contains $f)) { $r | Add-Member NoteProperty $f '' } }
    if (-not $r.Status) { $r.Status = 'new' }
    $list.Add($r)
  }
}
function Save-List {
  if ($list.Count) { $list | Select-Object $fields | Export-Csv -NoTypeInformation -Encoding UTF8 $listFile }
  else { [IO.File]::WriteAllText($listFile, '"' + ($fields -join '","') + '"' + "`r`n") }
}
# Which file each version is (written by build_songbook.ps1 next to the page).
$fileOf = @{}; $libRoot = ''
$filesTsv = Join-Path (Split-Path $Page -Parent) 'request-files.tsv'
if (Test-Path $filesTsv) {
  foreach ($l in [IO.File]::ReadAllLines($filesTsv, $utf8)) {
    $p = $l.Split("`t")
    if ($p[0] -eq '#root') { $libRoot = $p[1] } elseif ($p.Count -ge 3) { $fileOf["$($p[0])|$($p[1])"] = $p[2] }
  }
}
# When EZTiger last asked for songs (it asks every few seconds while it's open).
$script:lastApp = [DateTime]::MinValue

# The DJ can close requests ("no more requests, sorry"); it stays closed after
# a restart until the DJ opens them again.
$closedFile = Join-Path $Folder 'requests-closed.txt'
$script:closed = Test-Path $closedFile
function Set-Closed([bool]$c) {
  $script:closed = $c
  if ($c) { Set-Content $closedFile (Get-Date).ToString('s') } elseif (Test-Path $closedFile) { Remove-Item $closedFile }
  Write-Host ("  {0:HH:mm}  REQUESTS {1}" -f (Get-Date), $(if ($c) { 'CLOSED' } else { 'OPEN' })) -ForegroundColor Cyan
}
$closedMsg = "Sorry, no more requests tonight. The DJ has closed the list."

function Queue { @($list | Where-Object { $_.Status -eq 'queue' } | Sort-Object { [int]$_.Pos }) }
function Next-Pos { $q = Queue; if ($q.Count) { [string]([int]$q[-1].Pos + 1) } else { '1' } }

# The DJ link's code, kept so a bookmarked link keeps working.
$keyFile = Join-Path $Folder 'dj-code.txt'
if (Test-Path $keyFile) { $key = (Get-Content $keyFile -TotalCount 1).Trim() }
if (-not $key) { $key = -join ((1..6) | ForEach-Object { 'abcdefghjkmnpqrstuvwxyz23456789'[(Get-Random -Maximum 31)] }); Set-Content $keyFile $key }

# ---------- Small helpers ----------
function Decode([string]$s) { [Uri]::UnescapeDataString($s.Replace('+', ' ')) }
function Parse-Form([string]$s) {
  $h = @{}
  foreach ($p in ($s -split '&')) {
    if (-not $p) { continue }
    $kv = $p -split '=', 2
    $h[(Decode $kv[0])] = if ($kv.Count -gt 1) { Decode $kv[1] } else { '' }
  }
  $h
}
function Clean($s, [int]$max) {
  $s = (([string]$s) -replace '[\x00-\x1f]+', ' ').Trim()
  if ($s.Length -gt $max) { $s = $s.Substring(0, $max) }
  if ($s -match '^[=+\-@]') { $s = "'" + $s }   # so Excel never runs it as a formula
  $s
}
function Waiting { @($list | Where-Object { $_.Status -eq 'new' -or $_.Status -eq 'queue' }).Count }
function JStr([string]$s) {
  $sb = New-Object System.Text.StringBuilder; [void]$sb.Append('"')
  foreach ($ch in $s.ToCharArray()) {
    if ($ch -eq '"') { [void]$sb.Append('\"') } elseif ($ch -eq '\') { [void]$sb.Append('\\') }
    elseif ([int]$ch -lt 32) { [void]$sb.Append(' ') } elseif ($ch -eq '<') { [void]$sb.Append('<') }
    else { [void]$sb.Append($ch) }
  }
  [void]$sb.Append('"'); $sb.ToString()
}
function RowsJson($rows, $names) {
  $out = foreach ($r in $rows) { '{' + (($names | ForEach-Object { (JStr $_) + ':' + (JStr ([string]$r.$_)) }) -join ',') + '}' }
  '[' + (@($out) -join ',') + ']'
}
function ListJson {
  $ago = if ($script:lastApp -eq [DateTime]::MinValue) { -1 } else { [int]((Get-Date) - $script:lastApp).TotalSeconds }
  '{"app":' + $ago + ',"open":' + $(if ($script:closed) { 'false' } else { 'true' }) + ',"rows":' + (RowsJson $list $fields) + '}'
}

function Send($stream, [int]$code, [string]$type, [byte[]]$bytes, [string]$extra = '') {
  $reason = @{ 200 = 'OK'; 400 = 'Bad Request'; 403 = 'Forbidden'; 404 = 'Not Found'; 413 = 'Too Large' }[$code]
  $head = "HTTP/1.1 $code $reason`r`nContent-Type: $type`r`nContent-Length: $($bytes.Length)`r`n" +
          "Cache-Control: no-store`r`nConnection: close`r`n$extra`r`n"
  $hb = [Text.Encoding]::ASCII.GetBytes($head)
  $stream.Write($hb, 0, $hb.Length); $stream.Write($bytes, 0, $bytes.Length); $stream.Flush()
}
function SendText($stream, [int]$code, [string]$type, [string]$text) { Send $stream $code "$type; charset=utf-8" $utf8.GetBytes($text) }

# ---------- The DJ list page ----------
$djHtml = @'
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Requests · __NAME__</title>
<style>
  :root { --bg:#14151C; --panel:#1C1E28; --raised:#23252F; --line:#2F3140; --text:#E9E8E2; --dim:#8B8D9A; --brass:#E8B34A; --cyan:#3DDBD6; --red:#FF4757; --green:#8FD694; }
  * { box-sizing:border-box }
  body { margin:0; background:var(--bg); color:var(--text); font:15px/1.4 "Segoe UI", system-ui, sans-serif }
  header { display:flex; flex-wrap:wrap; gap:10px 24px; align-items:center; padding:14px 20px; background:var(--panel); border-bottom:1px solid var(--line) }
  h1 { margin:0; font-size:22px; color:var(--brass) }
  .link { color:var(--dim) } .link b { color:var(--cyan); font-size:18px; user-select:all }
  .counts { color:var(--dim) } .counts b { color:var(--brass); font-size:20px }
  .qr { display:flex; align-items:center; gap:10px; color:var(--dim); text-decoration:none; font-size:13px; margin-left:auto }
  .qr u { color:var(--cyan) }
  #qr svg { width:104px; height:104px; display:block; border-radius:6px }
  main { padding:8px 20px 40px; max-width:1280px; display:grid; gap:18px }
  section { background:var(--panel); border:1px solid var(--line); border-radius:12px; overflow:hidden }
  section > h2 { margin:0; padding:12px 16px; font-size:14px; text-transform:uppercase; letter-spacing:.08em; display:flex; align-items:center; gap:10px; border-bottom:1px solid var(--line) }
  section > h2 .c { background:var(--raised); color:var(--text); border-radius:99px; padding:1px 10px; font-size:13px; letter-spacing:0 }
  section > h2 .hint { margin-left:auto; text-transform:none; letter-spacing:0; font-weight:400; color:var(--dim); font-size:13px }
  #newBox > h2 { color:var(--cyan) } #queueBox > h2 { color:var(--brass) } #closedBox > h2 { color:var(--dim) }
  .row { display:grid; grid-template-columns:2.4em 12em minmax(10em,1fr) 13em minmax(6em,.8fr) auto; gap:4px 14px; align-items:start; padding:11px 16px; border-top:1px solid var(--line) }
  .row:first-child { border-top:0 }
  .n { color:var(--brass); font-weight:800; font-size:20px; line-height:1.1 }
  .singer { font-weight:700; font-size:17px; overflow-wrap:anywhere } .time { color:var(--dim); font-size:12px }
  .song { font-size:17px; overflow-wrap:anywhere } .song small { display:block; color:var(--dim); font-size:15px }
  .ver { color:var(--cyan); overflow-wrap:anywhere } .ver small { display:block; color:var(--dim); font-size:12px } .others { color:var(--dim); font-size:12px }
  .note { color:var(--brass); font-style:italic; overflow-wrap:anywhere }
  .acts { display:flex; gap:6px; flex-wrap:wrap; justify-content:flex-end }
  button { font:inherit; font-size:14px; border:1px solid var(--line); background:var(--raised); color:var(--text); border-radius:8px; padding:7px 12px; cursor:pointer; white-space:nowrap }
  button:hover:not(:disabled) { border-color:var(--brass) } button:disabled { opacity:.35; cursor:default }
  button.ok { background:color-mix(in srgb, var(--green) 22%, var(--raised)); border-color:color-mix(in srgb, var(--green) 50%, var(--line)) }
  button.no { color:var(--red) } button.mv { padding:7px 10px }
  .fresh { animation:fresh 3s ease-out }
  @keyframes fresh { from { background:color-mix(in srgb, var(--cyan) 22%, transparent) } to { background:transparent } }
  #closedBox .row { opacity:.6 } #closedBox .singer, #closedBox .song { text-decoration:line-through }
  .tag { font-size:12px; font-weight:700; padding:2px 8px; border-radius:6px; background:var(--raised) }
  .tag.done { color:var(--green) } .tag.rejected { color:var(--red) }
  .empty { color:var(--dim); padding:18px 16px }
  .bar { display:flex; justify-content:flex-end; gap:12px; align-items:center; color:var(--dim); font-size:13px }
  .clear { color:var(--red); border-color:color-mix(in srgb, var(--red) 40%, var(--line)) }
  .off { color:var(--red) }
  .closed { background:color-mix(in srgb, var(--red) 16%, var(--panel)); border:1px solid color-mix(in srgb, var(--red) 50%, var(--line)); border-radius:12px; padding:12px 16px }
  #openBtn.isClosed { color:var(--green); border-color:color-mix(in srgb, var(--green) 50%, var(--line)) }
  .app { font-size:13px; padding:3px 10px; border-radius:99px; background:var(--raised); color:var(--dim) }
  .app.on { color:var(--green) } .app.on::before { content:'● ' }
  .sent { font-size:12px; margin-top:4px } .sent.yes { color:var(--green) } .sent.wait { color:var(--dim) } .sent.missing { color:var(--red); font-weight:700 }
  @media (max-width: 860px) {
    header { padding:12px 16px } h1 { font-size:19px } .qr { margin-left:0 } #qr svg { width:90px; height:90px }
    main { padding:8px 12px 40px }
    .row { grid-template-columns:2em 1fr; padding:11px 12px }
    .row > :not(.n) { grid-column:2 } .n { grid-row:1 / span 6 }
    .acts { justify-content:flex-start; padding-top:4px } .note:empty { display:none }
  }
</style></head><body>
<header>
  <h1>__NAME__ · Requests</h1>
  <span class="link">Singers open <b>__LINK__</b> on the Wi-Fi</span>
  <span class="counts"><b id="nNew">0</b> new · <b id="nQueue">0</b> in the queue</span>
  <span class="app" id="app" title="Songs added to the singing queue go into EZTiger's Tonight's playlist while EZTiger is open"></span>
  <button id="openBtn" class="clear">🔒 Close requests</button>
  <a class="qr" href="/poster?key=__KEY__" target="_blank" title="Open the poster to print"><span id="qr"></span><span>Scan to request<br><u>Print poster</u></span></a>
</header>
<main>
  <div class="closed" id="closedBanner" hidden>🔒 Requests are <b>closed</b>. Phones show "Sorry, no more requests tonight" and can't send. Press <b>Open requests</b> to take them again.</div>
  <section id="newBox"><h2>New requests <span class="c" id="cNew">0</span><span class="hint">Oldest first. Add each one to the queue when you're ready, or reject it.</span></h2>
    <div id="new"></div></section>
  <section id="queueBox"><h2>Singing queue <span class="c" id="cQueue">0</span><span class="hint">Top sings next. ▲ ▼ to change the order.</span></h2>
    <div id="queue"></div></section>
  <section id="closedBox"><h2>Sung &amp; rejected <span class="c" id="cClosed">0</span><span class="hint">Kept until you clear the list. ↩ sends one back to New requests.</span></h2>
    <div id="closed"></div></section>
  <div class="bar"><span>The list is saved on this PC and kept until you clear it.</span><button class="clear" id="clear">Clear whole list…</button></div>
  <div class="bar"><span>On a tablet (EZTiger ☰ Menu → Song requests, or this list): <b style="color:var(--cyan);user-select:all">__LINK__/dj?key=__KEY__</b></span></div>
  <div class="bar" id="stopBar"><span>The request list runs in the background on this PC. Start it again from the taskbar.</span><button id="stop">⏻ Stop the request list</button></div>
  <div class="closed" id="stopped" hidden>The request list is <b>stopped</b>: phones can't open the page or send requests. Your list is saved. Start it again from the taskbar (Start song requests).</div>
</main>
<script>
__QRJS__
document.getElementById('qr').innerHTML = QR.svg('__LINK__');
const KEY = '__KEY__';
const $ = id => document.getElementById(id);
const esc = s => String(s || '').replace(/[&<>"]/g, c => ({ '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;' }[c]));
const hhmm = iso => iso ? iso.slice(11, 16) : '';
let seen = null, last = '', appOn = false, isOpen = true;
const sentTag = r => r.Sent === 'yes' ? '<div class="sent yes">✓ In EZTiger</div>'
  : r.Sent === 'missing' ? '<div class="sent missing">⚠ Not found in EZTiger – add it by hand</div>'
  : `<div class="sent wait">${appOn ? 'Going into EZTiger…' : 'Goes into EZTiger when it’s open'}</div>`;

function row(r, kind, i, count) {
  const fresh = seen && !seen.has(r.Id) ? ' fresh' : '';
  const id = esc(r.Id);
  const b = (act, label, cls = '', dis = false, title = '') =>
    `<button class="${cls}" data-id="${id}" data-do="${act}"${dis ? ' disabled' : ''}${title ? ` title="${title}"` : ''}>${label}</button>`;
  let acts = '';
  if (kind === 'new') acts = b('approve', '✓ Add to queue', 'ok') + b('reject', '✕ Reject', 'no');
  else if (kind === 'queue') acts = b('up', '▲', 'mv', i === 0, 'Move up') + b('down', '▼', 'mv', i === count - 1, 'Move down') +
    b('done', '✓ Sung', 'ok') + b('reject', '✕ Remove', 'no');
  else acts = `<span class="tag ${r.Status}">${r.Status === 'done' ? 'Sung' : 'Rejected'} ${hhmm(r.Closed)}</span>` + b('back', '↩ Back', '', false, 'Back to New requests');
  return `<div class="row${fresh}">
    <div class="n">${kind === 'queue' ? i + 1 : ''}</div>
    <div><div class="singer">${esc(r.Singer)}</div><div class="time">asked ${esc(r.Time)}</div>${kind === 'queue' ? sentTag(r) : ''}</div>
    <div class="song">${esc(r.Title)}<small>${esc(r.Artist)}</small></div>
    <div class="ver">${esc(r.Version)}<small>${esc(r.Disc)}</small>${r.Others ? `<div class="others">also: ${esc(r.Others)}</div>` : ''}</div>
    <div class="note">${esc(r.Note)}</div>
    <div class="acts">${acts}</div></div>`;
}
function fill(id, rows, kind, emptyText) {
  $(id).innerHTML = rows.length ? rows.map((r, i) => row(r, kind, i, rows.length)).join('') : `<div class="empty">${emptyText}</div>`;
}
async function load(force) {
  let text;
  try { text = await (await fetch('/dj/list?key=' + KEY, { cache:'no-store' })).text(); }
  catch { $('nNew').innerHTML = '<span class="off">?</span>'; return; }
  const data = JSON.parse(text), list = data.rows;
  const on = data.app >= 0 && data.app < 15;   // EZTiger asks every few seconds while open
  const appEl = $('app');
  appEl.className = 'app' + (on ? ' on' : '');
  appEl.textContent = on ? 'EZTiger connected' : 'EZTiger not connected';
  isOpen = data.open !== false;
  $('closedBanner').hidden = isOpen;
  $('openBtn').textContent = isOpen ? '🔒 Close requests' : '🔓 Open requests';
  $('openBtn').classList.toggle('isClosed', !isOpen);
  const rowsText = JSON.stringify(list);
  if (rowsText === last && on === appOn && !force) return;   // nothing changed: leave the screen alone
  last = rowsText; appOn = on;
  const byAt = (a, b) => (a.At || '').localeCompare(b.At || '');
  const fresh = list.filter(r => r.Status === 'new').sort(byAt);
  const queue = list.filter(r => r.Status === 'queue').sort((a, b) => (+a.Pos) - (+b.Pos));
  const closed = list.filter(r => r.Status === 'done' || r.Status === 'rejected').sort((a, b) => (a.Closed || '').localeCompare(b.Closed || ''));
  $('nNew').textContent = $('cNew').textContent = fresh.length;
  $('nQueue').textContent = $('cQueue').textContent = queue.length;
  $('cClosed').textContent = closed.length;
  fill('new', fresh, 'new', 'No new requests. They appear here as singers send them.');
  fill('queue', queue, 'queue', 'Nobody in the queue yet. Add requests from New requests above.');
  fill('closed', closed, 'closed', 'Nothing sung or rejected yet.');
  seen = new Set(list.map(r => r.Id));
}
document.querySelector('main').addEventListener('click', async e => {
  const b = e.target.closest('button[data-do]'); if (!b) return;
  document.querySelectorAll('button[data-do]').forEach(x => x.disabled = true);
  try { await fetch('/dj/act?key=' + KEY + '&id=' + encodeURIComponent(b.dataset.id) + '&do=' + b.dataset.do, { method:'POST' }); } catch {}
  load(true);
});
// Stopping only works on the PC that runs the list (not from a tablet).
if (!['localhost', '127.0.0.1'].includes(location.hostname)) $('stopBar').hidden = true;
$('stop').addEventListener('click', async () => {
  if (!confirm('Stop the request list?\n\nPhones won\'t be able to open the page or send requests until you start it again. Your list is kept.')) return;
  try { await fetch('/dj/quit', { method:'POST' }); } catch {}
  stopped = true;
  $('stopped').hidden = false; $('stopBar').hidden = true;
  document.querySelectorAll('button').forEach(b => b.disabled = true);
});
let stopped = false;
$('openBtn').addEventListener('click', async () => {
  if (isOpen && !confirm('Close requests? Phones will show "Sorry, no more requests tonight" and can\'t send any more.\n\nEverything already on the list stays.')) return;
  try { await fetch('/dj/open?key=' + KEY + '&open=' + (isOpen ? '0' : '1'), { method:'POST' }); } catch {}
  load(true);
});
$('clear').addEventListener('click', async () => {
  if (!confirm('Clear the WHOLE list – new requests, the queue, and sung & rejected?\n\nA copy is saved in the requests folder first.')) return;
  try { await fetch('/dj/clear?key=' + KEY, { method:'POST' }); } catch {}
  load(true);
});
load(); setInterval(load, 3000);
</script></body></html>
'@

# ---------- QR codes, made in the browser (no internet needed) ----------
# Byte mode, error correction level M, versions 1-6 (links up to 106 characters).
$qrJs = @'
const QR = (() => {
  // [total codewords, error-correction codewords per block, blocks] for level M
  const EC = [null, [26,10,1], [44,16,1], [70,26,1], [100,18,2], [134,24,2], [172,16,4]];
  const ALIGN = [null, [], [6,18], [6,22], [6,26], [6,30], [6,34]];
  const mul = (x, y) => { let z = 0; for (let i = 7; i >= 0; i--) { z = (z << 1) ^ ((z >>> 7) * 0x11D); z ^= ((y >>> i) & 1) * x; } return z; };
  function divisor(deg) {
    const r = new Array(deg).fill(0); r[deg - 1] = 1; let root = 1;
    for (let i = 0; i < deg; i++) { for (let j = 0; j < deg; j++) { r[j] = mul(r[j], root); if (j + 1 < deg) r[j] ^= r[j + 1]; } root = mul(root, 2); }
    return r;
  }
  function remainder(data, div) {
    const r = div.map(() => 0);
    for (const b of data) { const f = b ^ r.shift(); r.push(0); div.forEach((c, i) => { r[i] ^= mul(c, f); }); }
    return r;
  }
  const MASKS = [(x,y) => (x+y)%2 == 0, (x,y) => y%2 == 0, (x,y) => x%3 == 0, (x,y) => (x+y)%3 == 0,
    (x,y) => (Math.floor(x/3) + Math.floor(y/2))%2 == 0, (x,y) => x*y%2 + x*y%3 == 0,
    (x,y) => (x*y%2 + x*y%3)%2 == 0, (x,y) => ((x+y)%2 + x*y%3)%2 == 0];

  function encode(text) {
    const bytes = [...new TextEncoder().encode(text)];
    let ver = 1;
    while (ver <= 6 && bytes.length > EC[ver][0] - EC[ver][1] * EC[ver][2] - 2) ver++;
    if (ver > 6) throw new Error('Link too long for the QR code');
    const [total, ecLen, nb] = EC[ver], dataLen = total - ecLen * nb;
    const bits = [], put = (v, n) => { for (let i = n - 1; i >= 0; i--) bits.push((v >>> i) & 1); };
    put(4, 4); put(bytes.length, 8); bytes.forEach(b => put(b, 8));
    put(0, Math.min(4, dataLen * 8 - bits.length));
    while (bits.length % 8) bits.push(0);
    const data = [];
    for (let i = 0; i < bits.length; i += 8) data.push(parseInt(bits.slice(i, i + 8).join(''), 2));
    for (let p = 0xEC; data.length < dataLen; p ^= 0xEC ^ 0x11) data.push(p);
    const bl = dataLen / nb, div = divisor(ecLen), blocks = [];
    for (let i = 0; i < nb; i++) { const d = data.slice(i * bl, (i + 1) * bl); blocks.push([d, remainder(d, div)]); }
    const cw = [];
    for (let i = 0; i < bl; i++) blocks.forEach(b => cw.push(b[0][i]));
    for (let i = 0; i < ecLen; i++) blocks.forEach(b => cw.push(b[1][i]));

    const size = ver * 4 + 17;
    const m = [...Array(size)].map(() => Array(size).fill(false));
    const fn = [...Array(size)].map(() => Array(size).fill(false));
    const set = (x, y, d) => { m[y][x] = d; fn[y][x] = true; };
    for (let i = 0; i < size; i++) { set(6, i, i % 2 == 0); set(i, 6, i % 2 == 0); }
    for (const [cx, cy] of [[3, 3], [size - 4, 3], [3, size - 4]])
      for (let dy = -4; dy <= 4; dy++) for (let dx = -4; dx <= 4; dx++) {
        const x = cx + dx, y = cy + dy, d = Math.max(Math.abs(dx), Math.abs(dy));
        if (x >= 0 && x < size && y >= 0 && y < size) set(x, y, d != 2 && d != 4);
      }
    const al = ALIGN[ver], last = al.length - 1;
    for (let i = 0; i <= last; i++) for (let j = 0; j <= last; j++) {
      if ((i == 0 && j == 0) || (i == 0 && j == last) || (i == last && j == 0)) continue;
      for (let dy = -2; dy <= 2; dy++) for (let dx = -2; dx <= 2; dx++) set(al[i] + dx, al[j] + dy, Math.max(Math.abs(dx), Math.abs(dy)) != 1);
    }
    const format = mask => {
      let r = mask; for (let i = 0; i < 10; i++) r = (r << 1) ^ ((r >>> 9) * 0x537);
      const b = ((mask << 10) | r) ^ 0x5412, g = i => ((b >>> i) & 1) == 1;   // level M = 00
      for (let i = 0; i <= 5; i++) set(8, i, g(i));
      set(8, 7, g(6)); set(8, 8, g(7)); set(7, 8, g(8));
      for (let i = 9; i < 15; i++) set(14 - i, 8, g(i));
      for (let i = 0; i < 8; i++) set(size - 1 - i, 8, g(i));
      for (let i = 8; i < 15; i++) set(8, size - 15 + i, g(i));
      set(8, size - 8, true);
    };
    format(0);
    let k = 0;
    for (let right = size - 1; right >= 1; right -= 2) {
      if (right == 6) right = 5;
      for (let v = 0; v < size; v++) for (let j = 0; j < 2; j++) {
        const x = right - j, up = ((right + 1) & 2) == 0, y = up ? size - 1 - v : v;
        if (!fn[y][x] && k < cw.length * 8) { m[y][x] = ((cw[k >>> 3] >>> (7 - (k & 7))) & 1) == 1; k++; }
      }
    }
    const flip = n => { for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) if (!fn[y][x] && MASKS[n](x, y)) m[y][x] = !m[y][x]; };
    const penalty = () => {
      let p = 0, dark = 0;
      const line = get => { let s = ''; for (let i = 0; i < size; i++) s += get(i) ? '1' : '0'; return s; };
      for (let a = 0; a < size; a++) for (const s of [line(i => m[a][i]), line(i => m[i][a])]) {
        for (const run of s.match(/0+|1+/g)) if (run.length >= 5) p += run.length - 2;
        const t = '0000' + s + '0000';
        p += 40 * ((t.match(/(?=10111010000)/g) || []).length + (t.match(/(?=00001011101)/g) || []).length);
      }
      for (let y = 0; y < size - 1; y++) for (let x = 0; x < size - 1; x++) {
        const c = m[y][x]; if (c == m[y][x + 1] && c == m[y + 1][x] && c == m[y + 1][x + 1]) p += 3;
      }
      for (const r of m) for (const c of r) if (c) dark++;
      return p + 10 * (Math.ceil(Math.abs(dark * 20 - size * size * 10) / (size * size)) - 1);
    };
    let best = 0, bestP = Infinity;
    for (let n = 0; n < 8; n++) { flip(n); format(n); const p = penalty(); if (p < bestP) { bestP = p; best = n; } flip(n); }
    flip(best); format(best);
    return m;
  }
  function svg(text) {
    const m = encode(text), n = m.length, q = 4, s = n + 2 * q;
    let d = '';
    for (let y = 0; y < n; y++) for (let x = 0; x < n; x++) if (m[y][x]) d += `M${x + q},${y + q}h1v1h-1z`;
    return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${s} ${s}" shape-rendering="crispEdges" role="img" aria-label="QR code">` +
      `<rect width="${s}" height="${s}" fill="#fff"/><path d="${d}" fill="#000"/></svg>`;
  }
  return { encode, svg };
})();
'@

# ---------- The poster for the venue: name, logo, QR code, link ----------
$logo64 = ''
if ($utf8.GetString($pageBytes) -match 'src="data:image/png;base64,([A-Za-z0-9+/=]+)"') { $logo64 = $matches[1] }
$posterHtml = @'
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Request a song · __NAME__</title>
<style>
  @page { size:A4; margin:12mm }
  body { margin:0; font-family:"Segoe UI", system-ui, sans-serif; color:#111; background:#fff; text-align:center }
  .sheet { max-width:180mm; margin:0 auto; padding:8mm 16px }
  img.logo { width:42mm; max-width:40vw; height:auto }
  h1 { font-size:34pt; margin:3mm 0 0; line-height:1.1 }
  h2 { font-size:21pt; font-weight:600; margin:2mm 0 6mm; color:#444 }
  #qr svg { width:118mm; max-width:86vw; height:auto; display:block; margin:0 auto }
  ol { text-align:left; display:inline-block; font-size:16pt; line-height:1.6; margin:6mm 0 0; padding-left:1.4em }
  .link { font-weight:700; white-space:nowrap }
  img.logo { object-fit:contain }
  .pow { margin:8mm 0 0; font-size:10pt; color:#777 }
  .pow:empty { display:none }
  .print { position:fixed; top:12px; right:12px; font:inherit; font-size:15px; font-weight:600; padding:10px 18px; border-radius:8px; border:0; background:#E8B34A; color:#1A1508; cursor:pointer }
  @media print { .print { display:none } }
</style></head><body>
<button class="print" onclick="print()">Print</button>
<div class="sheet">
  <img class="logo" src="data:image/png;base64,__LOGO__" alt="">
  <h1>__NAME__</h1>
  <h2>Request a song from your phone</h2>
  <div id="qr"></div>
  <ol><li>Join the Wi-Fi here</li><li>Point your camera at the code</li><li>Or open <span class="link">__LINK__</span></li></ol>
  <p class="pow">__POWERED__</p>
</div>
<script>
__QRJS__
document.getElementById('qr').innerHTML = QR.svg('__LINK__');
</script>
</body></html>
'@

# ---------- Handling one connection ----------
function Handle($client) {
  $client.ReceiveTimeout = 4000; $client.SendTimeout = 15000
  $stream = $client.GetStream()
  $buf = New-Object byte[] 16384
  $acc = New-Object IO.MemoryStream
  $headEnd = -1
  while ($headEnd -lt 0) {
    $n = $stream.Read($buf, 0, $buf.Length); if ($n -le 0) { return }
    $acc.Write($buf, 0, $n)
    $headEnd = $latin1.GetString($acc.ToArray()).IndexOf("`r`n`r`n")
    if ($acc.Length -gt 65536) { return }
  }
  $all = $acc.ToArray()
  $head = $latin1.GetString($all, 0, $headEnd)
  $lines = $head -split "`r`n"
  $first = $lines[0] -split ' '
  if ($first.Count -lt 2) { return }
  $method = $first[0]; $target = $first[1]
  $hdr = @{}
  foreach ($l in ($lines | Select-Object -Skip 1)) { $i = $l.IndexOf(':'); if ($i -gt 0) { $hdr[$l.Substring(0, $i).Trim().ToLower()] = $l.Substring($i + 1).Trim() } }
  $len = 0; if ($hdr['content-length']) { $len = [int]$hdr['content-length'] }
  if ($len -gt 32768) { SendText $stream 413 'text/plain' 'Too large'; return }
  $bodyStart = $headEnd + 4
  while ($all.Length - $bodyStart -lt $len) {
    $n = $stream.Read($buf, 0, $buf.Length); if ($n -le 0) { break }
    $acc.Write($buf, 0, $n); $all = $acc.ToArray()
  }
  $body = if ($len -gt 0) { $utf8.GetString($all, $bodyStart, [Math]::Min($len, $all.Length - $bodyStart)) } else { '' }

  $path = $target; $query = @{}
  $q = $target.IndexOf('?'); if ($q -ge 0) { $path = $target.Substring(0, $q); $query = Parse-Form $target.Substring($q + 1) }
  $remote = $client.Client.RemoteEndPoint.Address
  $djOk = [Net.IPAddress]::IsLoopback($remote) -or $query['key'] -eq $key

  switch -Regex ("$method $path") {
    '^GET /(index\.html?)?$' {
      if ($hdr['accept-encoding'] -match 'gzip') { Send $stream 200 'text/html; charset=utf-8' $pageGz "Content-Encoding: gzip`r`n" }
      else { Send $stream 200 'text/html; charset=utf-8' $pageBytes }
      Write-Host ("  {0:HH:mm}  page opened by {1}" -f (Get-Date), $remote)
      return
    }
    '^GET /venue/active\.json$' {
      SendText $stream 200 'application/json' (Venue-Json)
      return
    }
    '^GET /venue/img/' {
      $rest = [Uri]::UnescapeDataString($path.Substring(11)); $k = $rest.IndexOf('/')
      $vid = if ($k -gt 0) { $rest.Substring(0, $k) } else { '' }; $file = if ($k -gt 0) { [IO.Path]::GetFileName($rest.Substring($k + 1)) } else { '' }
      $ext = [IO.Path]::GetExtension($file).ToLower(); $full = Join-Path (Join-Path $venuesDir $vid) $file
      if (-not $vid -or $vid -match '[\\/:*?"<>|]' -or $vid -match '^\.' -or -not $imgTypes[$ext] -or -not (Test-Path -LiteralPath $full -PathType Leaf)) { SendText $stream 404 'text/plain' 'Not found'; return }
      Send $stream 200 $imgTypes[$ext] ([IO.File]::ReadAllBytes($full))
      return
    }
    '^GET /status$' {
      SendText $stream 200 'application/json' ('{"open":' + $(if ($script:closed) { 'false' } else { 'true' }) + ',"message":' + (JStr $closedMsg) + '}')
      return
    }
    '^POST /dj/open$' {
      if (-not $djOk) { SendText $stream 403 'application/json' '{"ok":false}'; return }
      Set-Closed ($query['open'] -eq '0')
      SendText $stream 200 'application/json' '{"ok":true}'
      return
    }
    '^POST /request$' {
      if ($script:closed) { SendText $stream 200 'application/json' ('{"ok":false,"closed":true,"error":' + (JStr $closedMsg) + '}'); return }
      $f = Parse-Form $body
      $singer = Clean $f['singer'] 40; $title = Clean $f['title'] 120
      if (-not $singer -or -not $title) { SendText $stream 200 'application/json' '{"ok":false,"error":"Please put your name and choose a song."}'; return }
      # The same singer and song again within 2 minutes is a repeat tap: keep one.
      $cut = (Get-Date).AddMinutes(-2)
      $dup = $list | Where-Object { $_.Singer -eq $singer -and $_.Title -eq $title -and [datetime]$_.At -gt $cut } | Select-Object -First 1
      if (-not $dup) {
        $r = [pscustomobject]@{
          Id = [string]([DateTime]::Now.Ticks); At = (Get-Date).ToString('s'); Time = (Get-Date).ToString('HH:mm')
          Singer = $singer; Title = $title; Artist = Clean $f['artist'] 120
          Version = Clean $f['version'] 40; Disc = Clean $f['disc'] 60; Others = Clean $f['others'] 300
          Note = Clean $f['note'] 200; Status = 'new'; Pos = ''; Closed = ''
          Brand = Clean $f['brand'] 40; Code = Clean $f['code'] 60; File = ''; Path = ''; Sent = ''
        }
        $rel = $fileOf["$($r.Brand)|$($r.Code)"]
        if ($rel) { $r.File = $rel; if ($libRoot) { $r.Path = Join-Path $libRoot $rel } }
        $list.Add($r); Save-List
        Write-Host ("  {0}  REQUEST  {1}: {2} - {3}  [{4}]" -f $r.Time, $r.Singer, $r.Title, $r.Artist, $r.Version) -ForegroundColor Yellow
      }
      SendText $stream 200 'application/json' ('{"ok":true,"waiting":' + (Waiting) + '}')
      return
    }
    '^GET /dj/?$' {
      if (-not $djOk) { SendText $stream 403 'text/plain' 'The DJ list needs the DJ link.'; return }
      $html = $djHtml.Replace('__QRJS__', $qrJs).Replace('__NAME__', [Net.WebUtility]::HtmlEncode($showName)).Replace('__LINK__', $singerLink).Replace('__KEY__', $key)
      SendText $stream 200 'text/html' $html
      return
    }
    '^GET /poster$' {
      if (-not $djOk) { SendText $stream 403 'text/plain' 'The poster needs the DJ link.'; return }
      $v = Get-Venue
      $html = $posterHtml.Replace('__QRJS__', $qrJs).Replace('__LINK__', $singerLink)
      if ($v) {                                   # venue branding: the venue's name and logo, EZTiger as a small line
        $html = $html.Replace('__NAME__', [Net.WebUtility]::HtmlEncode($v.name)).Replace('__POWERED__', [Net.WebUtility]::HtmlEncode($v.poweredBy))
        if ($v.logoUrl) { $html = $html.Replace('data:image/png;base64,__LOGO__', $v.logoUrl) }
      }
      $html = $html.Replace('__NAME__', [Net.WebUtility]::HtmlEncode($showName)).Replace('__LOGO__', $logo64).Replace('__POWERED__', '')
      SendText $stream 200 'text/html' $html
      return
    }
    '^GET /dj/list$' {
      if (-not $djOk) { SendText $stream 403 'application/json' '[]'; return }
      SendText $stream 200 'application/json' (ListJson)
      return
    }
    '^POST /dj/act$' {
      if (-not $djOk) { SendText $stream 403 'application/json' '{"ok":false}'; return }
      $r = $list | Where-Object { $_.Id -eq $query['id'] } | Select-Object -First 1
      if ($r) {
        $now = (Get-Date).ToString('s')
        switch ($query['do']) {
          'approve' { if ($r.Status -eq 'new') { $r.Status = 'queue'; $r.Pos = Next-Pos } }
          'reject'  { $r.Status = 'rejected'; $r.Pos = ''; $r.Closed = $now }
          'done'    { $r.Status = 'done'; $r.Pos = ''; $r.Closed = $now }
          'back'    { $r.Status = 'new'; $r.Pos = ''; $r.Closed = '' }
          { $_ -eq 'up' -or $_ -eq 'down' } {
            $q = Queue; $i = -1; for ($k = 0; $k -lt $q.Count; $k++) { if ($q[$k].Id -eq $r.Id) { $i = $k } }; $j = if ($query['do'] -eq 'up') { $i - 1 } else { $i + 1 }
            if ($i -ge 0 -and $j -ge 0 -and $j -lt $q.Count) { $t = $q[$j].Pos; $q[$j].Pos = $r.Pos; $r.Pos = $t }
          }
        }
        Save-List
      }
      SendText $stream 200 'application/json' '{"ok":true}'
      return
    }
    # EZTiger asks for the songs in the singing queue it hasn't taken yet, in
    # queue order, and says when it has put each one in Tonight's playlist.
    '^GET /app/next$' {
      if (-not $djOk) { SendText $stream 403 'application/json' '[]'; return }
      $script:lastApp = Get-Date
      SendText $stream 200 'application/json' (RowsJson @(Queue | Where-Object { -not $_.Sent }) @('Id','Singer','Title','Artist','Version','Disc','File','Path'))
      return
    }
    '^POST /app/sent$' {
      if (-not $djOk) { SendText $stream 403 'application/json' '{"ok":false}'; return }
      $script:lastApp = Get-Date
      $r = $list | Where-Object { $_.Id -eq $query['id'] } | Select-Object -First 1
      if ($r) {
        $r.Sent = if ($query['found'] -eq '0') { 'missing' } else { 'yes' }; Save-List
        $what = if ($r.Sent -eq 'yes') { 'into EZTiger' } else { 'NOT FOUND in EZTiger - add it by hand' }
        Write-Host ("  {0:HH:mm}  {1}: {2} - {3}  {4}" -f (Get-Date), $r.Singer, $r.Title, $r.Artist, $what) -ForegroundColor Green
      }
      SendText $stream 200 'application/json' '{"ok":true}'
      return
    }
    # "Stop the request list" on the DJ screen (this PC only): the server
    # runs hidden, so this is how it is closed.
    '^POST /dj/quit$' {
      if (-not [Net.IPAddress]::IsLoopback($remote)) { SendText $stream 403 'application/json' '{"ok":false}'; return }
      $script:quit = $true
      Write-Host ("  {0:HH:mm}  STOPPED from the DJ screen" -f (Get-Date)) -ForegroundColor Cyan
      SendText $stream 200 'application/json' '{"ok":true}'
      return
    }
    '^POST /dj/clear$' {
      if (-not $djOk) { SendText $stream 403 'application/json' '{"ok":false}'; return }
      if ($list.Count) {
        $copy = Join-Path $Folder ('cleared ' + (Get-Date).ToString('yyyy-MM-dd HHmm') + '.csv')
        $list | Select-Object $fields | Export-Csv -NoTypeInformation -Encoding UTF8 $copy
        $list.Clear(); Save-List
        Write-Host ("  {0:HH:mm}  LIST CLEARED (a copy is in {1})" -f (Get-Date), $copy) -ForegroundColor Cyan
      }
      SendText $stream 200 'application/json' '{"ok":true}'
      return
    }
    default { SendText $stream 404 'text/plain' 'Not found' }
  }
}

# ---------- Start ----------
$ip = $null
try {
  # The address on the network the router gives out (the one with the default route).
  $route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction Stop | Sort-Object { $_.RouteMetric + $_.InterfaceMetric } | Select-Object -First 1
  $ip = Get-NetIPAddress -InterfaceIndex $route.InterfaceIndex -AddressFamily IPv4 -ErrorAction Stop | Select-Object -First 1 -ExpandProperty IPAddress
} catch {}
if (-not $ip) {
  $ip = [Net.Dns]::GetHostAddresses([Net.Dns]::GetHostName()) | Where-Object { $_.AddressFamily -eq 'InterNetwork' -and -not $_.ToString().StartsWith('169.254') } |
        Select-Object -First 1 | ForEach-Object { $_.ToString() }
}
if (-not $ip) { $ip = 'this-pc' }
$portPart = if ($Port -eq 80) { '' } else { ":$Port" }
$singerLink = "http://$ip$portPart"

$listener = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Any, $Port)
try { $listener.Start() } catch {
  # Already running (it runs hidden): just bring up the DJ list again.
  try {
    Invoke-WebRequest -UseBasicParsing "http://localhost$portPart/status" -TimeoutSec 3 | Out-Null
    if (-not $NoBrowser) { Start-Process "http://localhost$portPart/dj" }
    exit
  } catch { throw "Port $Port is already in use. Close the other copy, or start with -Port 8081." }
}
$script:quit = $false

Write-Host ''
Write-Host "  $showName - song requests on the Wi-Fi" -ForegroundColor Cyan
Write-Host "  Singers' link:  $singerLink" -ForegroundColor Green
Write-Host "  DJ list:        http://localhost$portPart/dj   (on a tablet: $singerLink/dj?key=$key)"
Write-Host "  Request list:   $listFile  ($(Waiting) waiting)"
Write-Host '  Leave this window open while taking requests. The list is kept when it closes;'
Write-Host '  clear it with "Clear whole list" on the DJ screen.'
Write-Host ''
if (-not $NoBrowser) { Start-Process "http://localhost$portPart/dj" }

try {
  while (-not $script:quit) {
    if (-not $listener.Pending()) { Start-Sleep -Milliseconds 40; continue }
    $client = $listener.AcceptTcpClient()
    try { Handle $client } catch { Write-Host "  (a connection dropped: $($_.Exception.Message))" -ForegroundColor DarkGray }
    finally { $client.Close() }
  }
} finally { $listener.Stop() }
