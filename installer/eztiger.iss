; Builds EZtiger-Setup.exe from the Flutter Windows release build.
; iscc /DAppVersion=0.1.0 /DSourceDir=..\app\build\windows\x64\runner\Release installer\eztiger.iss

#ifndef AppVersion
  #define AppVersion "0.1.0"
#endif
; /DEdition=Pro builds EZTiger-Pro-Setup.exe. It has the same AppId and folder
; as Basic, so it installs over Basic as an upgrade, keeping the library,
; playlists and settings.
#ifndef Edition
  #define Edition "Basic"
#endif
#if Edition == "Pro"
  #define OutputName "EZTiger-Pro-Setup"
  #define IconFile "..\app\windows\runner\resources\app_icon_pro.ico"
#else
  #define OutputName "EZtiger-Setup"
  #define IconFile "..\app\windows\runner\resources\app_icon.ico"
#endif
#ifndef SourceDir
  #define SourceDir "..\app\build\windows\x64\runner\Release"
#endif

[Setup]
AppId={{6B0E7A52-3F1C-4C7E-9A1D-B2C4D6E8F001}
AppName=EZTiger {#Edition}
AppVersion={#AppVersion}
AppPublisher=Deano
DefaultDirName={autopf}\EZtiger
DefaultGroupName=EZTiger {#Edition}
UsePreviousGroup=no
DisableProgramGroupPage=yes
OutputDir=Output
OutputBaseFilename={#OutputName}
Compression=lzma2/ultra64
LZMAUseSeparateProcess=yes
LZMADictionarySize=262144
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequiredOverridesAllowed=dialog
UninstallDisplayIcon={app}\eztiger.exe
SetupIconFile={#IconFile}
WizardStyle=modern

[Tasks]
Name: "desktopicon"; Description: "Put an EZtiger icon on the desktop"; GroupDescription: "Shortcuts:"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

#if Edition == "Pro"
[InstallDelete]
; Upgrading from Basic: its Start menu folder goes, Pro's takes its place.
Type: filesandordirs; Name: "{autoprograms}\EZTiger Basic"

#endif
[Icons]
Name: "{group}\EZtiger"; Filename: "{app}\eztiger.exe"
Name: "{autodesktop}\EZtiger"; Filename: "{app}\eztiger.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\eztiger.exe"; Description: "Start EZtiger now"; Flags: nowait postinstall skipifsilent
