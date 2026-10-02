#ifndef AppVersion
  #error AppVersion must be passed to ISCC
#endif

#define AppName "Codex Account Switcher"
#define AppExe "CodexAccountSwitcher.Windows.exe"

[Setup]
AppId={{B683E327-2A6D-4C70-978B-9E46A3E1F618}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion} Windows Preview
AppPublisher=hsjx945
AppPublisherURL=https://github.com/hsjx945/codex-account-switcher
AppSupportURL=https://github.com/hsjx945/codex-account-switcher/issues
DefaultDirName={localappdata}\Programs\Codex Account Switcher
DefaultGroupName={#AppName}
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\{#AppExe}
OutputDir=artifacts
OutputBaseFilename=Codex-Account-Switcher-Setup-win-x64
SetupIconFile=app.ico
LicenseFile=..\LICENSE
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
DisableProgramGroupPage=yes
CloseApplications=yes

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Files]
Source: "artifacts\app\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "Launch {#AppName}"; Flags: nowait postinstall skipifsilent
