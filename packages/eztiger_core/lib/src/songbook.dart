import 'dart:convert';

import 'data/models.dart';

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec'
];

/// The audience songbook: one self-contained web page (no other files, no
/// internet needed once loaded) that lists [songs] and lets people search
/// them on their phone. It is read-only; nothing is sent anywhere.
String songbookHtml(
    {required String title,
    required List<SongbookEntry> songs,
    DateTime? updated}) {
  final when = updated ?? DateTime.now();
  final date = '${when.day} ${_months[when.month - 1]} ${when.year}';
  final pageTitle = title.trim().isEmpty ? 'Song list' : title.trim();
  // [artist, title] pairs. Escaped so a song name can't end the <script>.
  final data = jsonEncode([
    for (final s in songs) [s.artist, s.title],
  ]).replaceAll('</', r'<\/').replaceAll(' ', r' ').replaceAll(' ', r' ');
  return _template
      .replaceAll('{{TITLE}}', const HtmlEscape().convert(pageTitle))
      .replaceAll('{{COUNT}}', '${songs.length}')
      .replaceAll('{{DATE}}', date)
      .replaceFirst('{{DATA}}', data);
}

const _template = r'''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="theme-color" content="#111317">
<title>{{TITLE}}</title>
<style>
  :root { --bg:#111317; --panel:#1b1e24; --line:#2c3038; --text:#f2f2f2; --dim:#9aa1ab; --brass:#e8b04b; --cyan:#3fd6d0; }
  * { box-sizing: border-box; }
  html { -webkit-text-size-adjust: 100%; }
  body { margin:0; background:var(--bg); color:var(--text);
         font: 17px/1.35 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Arial, sans-serif; }
  header { position:sticky; top:0; z-index:2; background:var(--bg); padding:14px 16px 8px;
           border-bottom:1px solid var(--line); }
  h1 { margin:0; font-size:24px; color:var(--brass); letter-spacing:.3px; }
  .sub { color:var(--dim); font-size:14px; margin-top:2px; }
  .search { position:relative; margin-top:12px; }
  input { width:100%; font-size:18px; padding:12px 44px 12px 14px; border-radius:12px;
          border:1px solid var(--line); background:var(--panel); color:var(--text); outline:none; }
  input:focus { border-color:var(--cyan); }
  .clear { position:absolute; right:6px; top:50%; transform:translateY(-50%); border:0; background:none;
           color:var(--dim); font-size:24px; width:36px; height:36px; display:none; }
  .row { display:flex; gap:8px; align-items:center; margin-top:10px; }
  .sort button { font-size:15px; padding:8px 14px; border-radius:20px; border:1px solid var(--line);
                 background:var(--panel); color:var(--dim); }
  .sort button.on { background:var(--cyan); border-color:var(--cyan); color:#0b1414; font-weight:700; }
  .count { margin-left:auto; color:var(--dim); font-size:14px; }
  .letters { display:flex; gap:4px; overflow-x:auto; padding:10px 0 2px; scrollbar-width:none; }
  .letters::-webkit-scrollbar { display:none; }
  .letters a { flex:0 0 auto; min-width:34px; text-align:center; padding:6px 0; border-radius:8px;
               background:var(--panel); color:var(--brass); text-decoration:none; font-weight:700; font-size:15px; }
  main { padding:0 16px 40px; }
  h2 { margin:18px 0 4px; font-size:15px; color:var(--brass); border-bottom:1px solid var(--line); padding-bottom:4px; }
  .song { padding:9px 0; border-bottom:1px solid #1f2229; }
  .song b { display:block; font-weight:600; }
  .song span { color:var(--dim); font-size:15px; }
  .note { color:var(--dim); text-align:center; padding:24px 8px; }
  mark { background:none; color:var(--cyan); }
  footer { color:var(--dim); text-align:center; font-size:13px; padding:8px 16px 32px; }
</style>
</head>
<body>
<header>
  <h1>{{TITLE}}</h1>
  <div class="sub">{{COUNT}} songs · updated {{DATE}}</div>
  <div class="search">
    <input id="q" type="text" enterkeyhint="search" placeholder="Search for a song or an artist" autocomplete="off" aria-label="Search">
    <button class="clear" id="clear" aria-label="Clear the search">×</button>
  </div>
  <div class="row">
    <div class="sort"><button id="byArtist" class="on">By artist</button> <button id="byTitle">By title</button></div>
    <div class="count" id="count"></div>
  </div>
  <nav class="letters" id="letters"></nav>
</header>
<main id="list"></main>
<footer>Like one? Ask at the stage. · Made with EZtiger</footer>
<script>
const SONGS = {{DATA}};
const fold = s => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();
const plain = s => s.replace(/^the\s+/i, '');
const items = SONGS.map(([artist, title]) => ({ artist, title, key: fold(artist + ' ' + title) }));
let sortBy = 'artist';
const $ = id => document.getElementById(id);
const esc = s => s.replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const letterOf = s => { const c = fold(plain(s)).charAt(0).toUpperCase(); return c >= 'A' && c <= 'Z' ? c : '#'; };
const cmp = (a, b) => fold(plain(a)).localeCompare(fold(plain(b)));
function sorted() {
  return items.slice().sort(sortBy === 'artist'
    ? (a, b) => cmp(a.artist, b.artist) || cmp(a.title, b.title)
    : (a, b) => cmp(a.title, b.title) || cmp(a.artist, b.artist));
}
let all = sorted();
function songHtml(s) {
  return '<div class="song"><b>' + esc(s.title) + '</b><span>' + esc(s.artist || '') + '</span></div>';
}
function render() {
  const words = fold($('q').value).split(' ').filter(Boolean);
  $('clear').style.display = words.length ? 'block' : 'none';
  const list = $('list');
  if (words.length) {
    const hits = all.filter(s => words.every(w => s.key.includes(w)));
    $('count').textContent = hits.length === 1 ? '1 match' : hits.length + ' matches';
    $('letters').style.display = 'none';
    const shown = hits.slice(0, 300);
    list.innerHTML = shown.length
      ? shown.map(songHtml).join('') + (hits.length > 300 ? '<p class="note">Showing the first 300. Type a little more to narrow it down.</p>' : '')
      : '<p class="note">Nothing found. Try fewer letters, or just the artist.</p>';
    return;
  }
  $('count').textContent = all.length + ' songs';
  $('letters').style.display = 'flex';
  let html = '', last = null; const letters = [];
  for (const s of all) {
    const l = letterOf(sortBy === 'artist' ? s.artist : s.title);
    if (l !== last) { html += '<h2 id="L' + l + '">' + l + '</h2>'; letters.push(l); last = l; }
    html += songHtml(s);
  }
  list.innerHTML = html || '<p class="note">No songs yet.</p>';
  $('letters').innerHTML = letters.map(l => '<a href="#L' + l + '">' + l + '</a>').join('');
}
function setSort(by) {
  sortBy = by;
  $('byArtist').classList.toggle('on', by === 'artist');
  $('byTitle').classList.toggle('on', by === 'title');
  all = sorted();
  render();
  window.scrollTo(0, 0);
}
$('q').addEventListener('input', render);
$('clear').addEventListener('click', () => { $('q').value = ''; render(); $('q').focus(); });
$('byArtist').addEventListener('click', () => setSort('artist'));
$('byTitle').addEventListener('click', () => setSort('title'));
$('letters').addEventListener('click', e => {
  const a = e.target.closest('a'); if (!a) return;
  e.preventDefault();
  const h = document.querySelector(a.getAttribute('href'));
  if (h) window.scrollTo(0, h.getBoundingClientRect().top + window.scrollY - document.querySelector('header').offsetHeight - 4);
});
render();
</script>
</body>
</html>
''';
