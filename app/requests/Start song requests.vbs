' EZTiger: starts the song-request list in the background (no window), with
' the singers' page EZTiger last made (EZTiger: Menu > Start song requests).
' The DJ list opens in the browser; stop it there with "Stop the request list".
' If it's already running, this just opens the DJ list again.
' While EZTiger takes requests online (Menu > Song requests has the online DJ
' link), this opens the online DJ list instead and starts nothing on this PC.
Set sh = CreateObject("WScript.Shell")
Set fs = CreateObject("Scripting.FileSystemObject")
here = fs.GetParentFolderName(WScript.ScriptFullName)
data = sh.ExpandEnvironmentStrings("%LOCALAPPDATA%") & "\EZTiger\requests"
online = data & "\online-dj-link.txt"
If fs.FileExists(online) Then
  Set f = fs.OpenTextFile(online, 1)
  link = ""
  If Not f.AtEndOfStream Then link = Trim(f.ReadLine)
  f.Close
  If LCase(Left(link, 4)) = "http" Then
    sh.Run "rundll32 url.dll,FileProtocolHandler " & link, 1, False
    WScript.Quit
  End If
End If
page = data & "\request-songs.html"
If Not fs.FileExists(page) Then
  MsgBox "Open EZTiger and choose Menu > Start song requests the first time: it makes the singers' page from your songs.", 64, "EZTiger song requests"
  WScript.Quit
End If
sh.Run "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & here & "\request-server.ps1"" -Page """ & page & """ -Folder """ & data & "\list""", 0, False
