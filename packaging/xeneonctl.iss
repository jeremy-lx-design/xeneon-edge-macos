; Inno Setup script for the xeneonctl Windows installer.
;
; Built by `make dist` on Windows, which stages the payload first and then
; invokes ISCC with just the version:
;
;   iscc //DAppVersion=1.0.0 packaging/xeneonctl.iss
;
; Every path below is relative to this file, so none of them have to
; survive MSYS2's POSIX/Windows path rewriting.
;
; Per-user install (PrivilegesRequired=lowest), so it never triggers UAC
; and lands in %LOCALAPPDATA%\Programs\xeneonctl - the same place
; `make install` uses.

#define AppName "Xeneon Edge"
#define AppExeName "XeneonUI.exe"
#define AppPublisher "jeremy-lx-design"
#define AppUrl "https://github.com/jeremy-lx-design/xeneon-edge-macos"

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

#ifndef PayloadDir
  #define PayloadDir "..\dist\xeneonctl-windows-x64"
#endif

[Setup]
; Never change AppId - it is how Windows recognises upgrades of this app.
AppId={{0E6EF85C-24A4-4F8C-BC56-6D29C25A0551}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppUrl}
AppSupportURL={#AppUrl}/issues
DefaultDirName={autopf}\xeneonctl
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\dist
OutputBaseFilename=xeneonctl-setup-x64
SetupIconFile=..\gui-windows\XeneonUI.ico
UninstallDisplayIcon={app}\{#AppExeName}
UninstallDisplayName={#AppName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
LicenseFile=..\LICENSE

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#PayloadDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(AppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
