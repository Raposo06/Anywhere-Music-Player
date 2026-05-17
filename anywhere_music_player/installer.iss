[Setup]
AppName=Anywhere Music Player
AppVersion=1.1.0
AppPublisher=FoxDR
AppPublisherURL=https://github.com/FoxDR
DefaultDirName={autopf}\Anywhere Music Player
DefaultGroupName=Anywhere Music Player
OutputDir=installer_output
OutputBaseFilename=AnywhereMusicalPlayer_Setup
SetupIconFile=assets\icons\psx.ico
Compression=lzma
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional icons:"; Flags: unchecked

[Files]
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Anywhere Music Player"; Filename: "{app}\anywhere_music_player.exe"; IconFilename: "{app}\anywhere_music_player.exe"
Name: "{group}\Uninstall Anywhere Music Player"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Anywhere Music Player"; Filename: "{app}\anywhere_music_player.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\anywhere_music_player.exe"; Description: "Launch Anywhere Music Player"; Flags: nowait postinstall skipifsilent
