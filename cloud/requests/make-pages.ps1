# Copies the DJ list, QR code maker and poster from app\requests\request-server.ps1
# into dj.html, qr.txt and poster.html, so the online list matches the PC one.
# Run it after changing those parts of request-server.ps1, then deploy again.
$s = [IO.File]::ReadAllText((Join-Path $PSScriptRoot '..\..\app\requests\request-server.ps1'))
$utf8 = New-Object Text.UTF8Encoding $false
foreach ($p in @(@('djHtml', 'dj.html'), @('qrJs', 'qr.txt'), @('posterHtml', 'poster.html'))) {
  $m = [regex]::Match($s, '\$' + $p[0] + " = @'\r?\n(.*?)\r?\n'@", 'Singleline')
  if (-not $m.Success) { throw "Couldn't find `$$($p[0]) in request-server.ps1" }
  [IO.File]::WriteAllText((Join-Path $PSScriptRoot $p[1]), $m.Groups[1].Value, $utf8)
}
