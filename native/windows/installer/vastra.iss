#ifndef AppVersion
  #define AppVersion "0.2.0"
#endif
#define Release "..\..\build\windows\x64\runner\Release"
[Setup]
AppId={{801368EB-2DD0-456A-A5B3-BD25FF0D8141}
AppName=Vastra
AppVersion={#AppVersion}
AppPublisher=sudharamachandranrajeev
DefaultDirName={localappdata}\Programs\Vastra
DefaultGroupName=Vastra
DisableProgramGroupPage=yes
OutputDir=..\..\build\installer
OutputBaseFilename=Vastra-{#AppVersion}-windows-x64-setup
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\vastra.exe
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
CloseApplications=yes
MinVersion=10.0.17763
[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
[Files]
Source: "{#Release}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
[Icons]
Name: "{autoprograms}\Vastra"; Filename: "{app}\vastra.exe"; Comment: "Fashion and personal-care discovery"
Name: "{autodesktop}\Vastra"; Filename: "{app}\vastra.exe"; Tasks: desktopicon
[Run]
Filename: "{app}\vastra.exe"; Description: "{cm:LaunchProgram,Vastra}"; Flags: nowait postinstall skipifsilent
