' EZTiger: starts the song-request list in the background (no window), with
' the singers' page EZTiger last made (EZTiger: Menu > Start song requests).
' The DJ list opens in the browser; stop it there with "Stop the request list".
' If it's already running, this just opens the DJ list again.
Set sh = CreateObject("WScript.Shell")
Set fs = CreateObject("Scripting.FileSystemObject")
here = fs.GetParentFolderName(WScript.ScriptFullName)
data = sh.ExpandEnvironmentStrings("%LOCALAPPDATA%") & "\EZTiger\requests"
page = data & "\request-songs.html"
If Not fs.FileExists(page) Then
  MsgBox "Open EZTiger and choose Menu > Start song requests the first time: it makes the singers' page from your songs.", 64, "EZTiger song requests"
  WScript.Quit
End If
sh.Run "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & here & "\request-server.ps1"" -Page """ & page & """ -Folder """ & data & "\list""", 0, False
