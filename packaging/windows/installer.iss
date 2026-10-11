; Inno Setup script for Simple-Golf.
; Built with: iscc packaging\windows\installer.iss
; Expects build\windows\Simple-Golf.exe (Godot export, game data embedded)
; to already exist, and the version passed in via /DAppVersion=x.y.z (the
; release workflow does this so the .iss file never has to be hand-edited
; per release).

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

#define AppName "Simple-Golf"
#define RepoRoot AddBackslash(SourcePath) + "..\.."

[Setup]
AppId={{B3E1F2A4-5C6D-4E7F-8A9B-0C1D2E3F4A5B}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=Mike Hellyer
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
UninstallDisplayIcon={app}\icon.ico
OutputDir={#RepoRoot}\dist
OutputBaseFilename=Simple-Golf-{#AppVersion}-Windows-Setup
Compression=lzma
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64compatible
SetupIconFile={#RepoRoot}\packaging\icons\icon.ico

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional shortcuts:"

[Files]
Source: "{#RepoRoot}\build\windows\Simple-Golf.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#RepoRoot}\packaging\icons\icon.ico"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\Simple-Golf.exe"; IconFilename: "{app}\icon.ico"
Name: "{group}\Uninstall {#AppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\Simple-Golf.exe"; IconFilename: "{app}\icon.ico"; Tasks: desktopicon

[Run]
Filename: "{app}\Simple-Golf.exe"; Description: "Launch {#AppName}"; Flags: nowait postinstall skipifsilent
