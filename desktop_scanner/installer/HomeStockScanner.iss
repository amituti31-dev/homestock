; Inno Setup script for the HomeStock desktop barcode scanner.
;
; Build the app first, then compile this script:
;   flutter build windows --release
;   "%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe" installer\HomeStockScanner.iss
;
; Output: installer\Output\HomeStockScanner-Setup.exe

#define AppName "HomeStock Scanner"
#define AppVersion "1.0.0"
#define AppPublisher "HomeStock"
#define AppExeName "HomeStockScanner.exe"
#define BuildDir "..\build\windows\x64\runner\Release"

[Setup]
AppId={{8B5F2C41-9D3E-4A7B-B6E2-5C1A9F0D3E77}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={autopf}\HomeStock Scanner
DefaultGroupName=HomeStock
UninstallDisplayIcon={app}\{#AppExeName}
UninstallDisplayName={#AppName}
OutputDir=Output
OutputBaseFilename=HomeStockScanner-Setup
SetupIconFile=..\windows\runner\resources\app_icon.ico
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; The app is 64-bit only, so install into the real Program Files and refuse
; to run on anything else.
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Per-user install needs no admin rights; "lowest" avoids a UAC prompt when
; DefaultDirName resolves to the user's local app data.
PrivilegesRequiredOverridesAllowed=dialog

[Languages]
Name: "hebrew"; MessagesFile: "compiler:Languages\Hebrew.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
; The Flutter runner plus its DLLs and the whole data\ tree (assets and ICU).
Source: "{#BuildDir}\desktop_scanner.exe"; DestDir: "{app}"; DestName: "{#AppExeName}"; Flags: ignoreversion
Source: "{#BuildDir}\*.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#BuildDir}\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{group}\הסרת {#AppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

; No [UninstallDelete]: shared_preferences keeps the household link and the
; anonymous credentials in %APPDATA%\HomeStock\, and leaving them means a
; reinstall doesn't ask for the household code again. Use the app's "ניתוק
; מהבית" button to clear the link instead.
