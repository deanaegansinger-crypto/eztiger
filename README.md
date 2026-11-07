# EZtiger by Deano

A Windows app for searching and playing a karaoke and backing-track library:
MP3+CDG, video and backing tracks, with a singer queue, playlists and history.

| Folder | What it is |
|---|---|
| `packages/eztiger_core` | Library scanner, song database, search and CD+G decoder. Pure Dart, tested on Windows and Linux. |
| `app` | The Windows app (Flutter), built from the UI mockup. *Coming next.* |

Every push runs the core tests on Windows and Linux (see the Actions tab). Once the
app is in, the same build will produce `EZtiger-Setup.exe` to download.

## Getting the Windows app

Every push builds `EZtiger-Setup.exe` on a Windows machine at GitHub
(`.github/workflows/windows-app.yml`) and publishes it as a test download on the
[Releases page](../../releases). The installer isn't signed yet, so Windows may
show "Windows protected your PC": click **More info**, then **Run anyway**.

To build it yourself on Windows: install Flutter 3.47 and Inno Setup 6, then run
`flutter build windows --release` in `app/` and
`iscc installer\eztiger.iss`.
