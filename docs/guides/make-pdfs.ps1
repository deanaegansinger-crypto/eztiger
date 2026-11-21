# Prints the online-requests guides to PDF with Chrome:
#   .\make-pdfs.ps1 -Build 185 [-Out "$env:USERPROFILE\Documents\EZTiger Guides"]
param(
  [Parameter(Mandatory)][string]$Build,
  [string]$Out = (Join-Path $env:USERPROFILE 'Documents\EZTiger Guides'),
  [string]$DeployUrl = 'https://deploy.workers.cloudflare.com/?url=https://github.com/deanaegansinger-crypto/eztiger/tree/main/cloud/requests'
)
$ErrorActionPreference = 'Stop'
$chrome = @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe", "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
  "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe", "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe") |
  Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $chrome) { throw 'Chrome or Edge is needed to print the PDFs.' }
New-Item -ItemType Directory -Force $Out | Out-Null
$utf8 = New-Object Text.UTF8Encoding $false
$guides = @{ 'online-requests-setup.html' = 'EZTiger online song requests - first-time setup.pdf'
             'online-requests-self-host.html' = 'EZTiger online song requests - host on your own Cloudflare.pdf' }
foreach ($g in $guides.Keys) {
  $src = Join-Path $PSScriptRoot $g
  $tmp = Join-Path $PSScriptRoot ('_print-' + $g)
  $html = [IO.File]::ReadAllText($src, $utf8).Replace('BUILD', $Build).Replace('DEPLOY_URL', [Net.WebUtility]::HtmlEncode($DeployUrl))
  [IO.File]::WriteAllText($tmp, $html, $utf8)
  $pdf = Join-Path $Out $guides[$g]
  $profile = Join-Path $env:TEMP 'ezt-pdf-profile'
  # Chrome writes harmless warnings to stderr: keep them out of the way.
  Start-Process $chrome -Wait -WindowStyle Hidden -RedirectStandardError (Join-Path $env:TEMP 'ezt-pdf-chrome.log') -ArgumentList @(
    '--headless=new', '--disable-gpu', '--no-pdf-header-footer', "--user-data-dir=`"$profile`"", '--virtual-time-budget=4000',
    "--print-to-pdf=`"$pdf`"", ([Uri]$tmp).AbsoluteUri)
  Remove-Item $tmp
  "{0}  {1:N0} KB" -f $pdf, ((Get-Item $pdf).Length / 1KB)
}
