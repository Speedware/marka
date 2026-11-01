; Inno Setup script for Marka. Built by build.ps1, which passes StageDir, IconFile, OutDir and AppVersion.
; The installer UI is in Russian through the bundled Russian.isl; this file stays ASCII.
#define AppName "Marka"
#ifndef StageDir
  #define StageDir "build\stage"
#endif
#ifndef IconFile
  #define IconFile "marka.ico"
#endif
#ifndef OutDir
  #define OutDir "dist"
#endif
#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#define AppId "Marka.App"
#define PyW "{app}\python\pythonw.exe"
#define MainPy "{app}\app\server.py"
#define AppIcon "{app}\marka.ico"

[Setup]
AppId={{3B7E9C41-6D2A-4F85-A1C3-8E5D0F2B6A97}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppName}
DefaultDirName={localappdata}\Programs\{#AppName}
UsePreviousAppDir=no
DisableProgramGroupPage=yes
DisableDirPage=yes
PrivilegesRequired=lowest
OutputDir={#OutDir}
OutputBaseFilename=Marka-Setup
SetupIconFile={#IconFile}
UninstallDisplayIcon={#AppIcon}
UninstallDisplayName={#AppName}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0

[Languages]
Name: "ru"; MessagesFile: "compiler:Languages\Russian.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[InstallDelete]
; a fresh copy of the bundled Python and libraries on every update
Type: filesandordirs; Name: "{app}\python"
Type: filesandordirs; Name: "{app}\app"

[Files]
Source: "{#StageDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{#PyW}"; Parameters: """{#MainPy}"""; WorkingDir: "{app}"; IconFilename: "{#AppIcon}"; AppUserModelID: "{#AppId}"
Name: "{autodesktop}\{#AppName}"; Filename: "{#PyW}"; Parameters: """{#MainPy}"""; WorkingDir: "{app}"; IconFilename: "{#AppIcon}"; AppUserModelID: "{#AppId}"; Tasks: desktopicon

[Run]
Filename: "{#PyW}"; Parameters: """{#MainPy}"""; WorkingDir: "{app}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: files; Name: "{app}\marka.log"
