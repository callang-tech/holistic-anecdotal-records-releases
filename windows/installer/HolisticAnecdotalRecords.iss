; Compile through build-installer.ps1, which supplies the pubspec version.
; Explicit runtime allowlist: never replace with a recursive Release\* rule.
#ifndef AppVersion
  #error Run build-installer.ps1 to supply the validated project version.
#endif
#define ReleaseDir SourcePath + "..\..\build\windows\x64\runner\Release"

[Setup]
AppId={{AF542A53-28C4-469D-9554-31A9FC590C8A}
AppName=Holistic Anecdotal Records
AppVersion={#AppVersion}
DefaultDirName={autopf}\Holistic Anecdotal Records
DisableDirPage=yes
UsePreviousAppDir=no
DefaultGroupName=Holistic Anecdotal Records
DisableProgramGroupPage=yes
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\..\build\installer
OutputBaseFilename=HolisticAnecdotalRecords-Setup-{#AppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\holistic_anecdotal_records.exe
CloseApplications=no
RestartApplications=no
SetupLogging=yes

[Tasks]
Name: "desktopicon"; Description: "Create a &Desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Files]
Source: "{#ReleaseDir}\holistic_anecdotal_records.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#ReleaseDir}\flutter_windows.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#ReleaseDir}\file_selector_windows_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#ReleaseDir}\pdfium.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#ReleaseDir}\printing_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#ReleaseDir}\sqlite3.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#ReleaseDir}\url_launcher_windows_plugin.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#ReleaseDir}\data\app.so"; DestDir: "{app}\data"; Flags: ignoreversion
Source: "{#ReleaseDir}\data\icudtl.dat"; DestDir: "{app}\data"; Flags: ignoreversion
Source: "{#ReleaseDir}\data\flutter_assets\AssetManifest.bin"; DestDir: "{app}\data\flutter_assets"; Flags: ignoreversion
Source: "{#ReleaseDir}\data\flutter_assets\FontManifest.json"; DestDir: "{app}\data\flutter_assets"; Flags: ignoreversion
Source: "{#ReleaseDir}\data\flutter_assets\NativeAssetsManifest.json"; DestDir: "{app}\data\flutter_assets"; Flags: ignoreversion
Source: "{#ReleaseDir}\data\flutter_assets\NOTICES.Z"; DestDir: "{app}\data\flutter_assets"; Flags: ignoreversion
Source: "{#ReleaseDir}\data\flutter_assets\pubspec.yaml"; DestDir: "{app}\data\flutter_assets"; Flags: ignoreversion
; Required, checked-in geographic reference data, NOT a counselor database.
Source: "{#ReleaseDir}\data\flutter_assets\assets\database\locations.db"; DestDir: "{app}\data\flutter_assets\assets\database"; Flags: ignoreversion
Source: "{#ReleaseDir}\data\flutter_assets\assets\images\home_background.jpg"; DestDir: "{app}\data\flutter_assets\assets\images"; Flags: ignoreversion
Source: "{#ReleaseDir}\data\flutter_assets\assets\images\SchoolHeader.PNG"; DestDir: "{app}\data\flutter_assets\assets\images"; Flags: ignoreversion
Source: "{#ReleaseDir}\data\flutter_assets\assets\images\SchoolFooter.PNG"; DestDir: "{app}\data\flutter_assets\assets\images"; Flags: ignoreversion
Source: "{#ReleaseDir}\data\flutter_assets\assets\images\about\app_logo.png"; DestDir: "{app}\data\flutter_assets\assets\images\about"; Flags: ignoreversion
Source: "{#ReleaseDir}\data\flutter_assets\assets\images\about\school.jpg"; DestDir: "{app}\data\flutter_assets\assets\images\about"; Flags: ignoreversion
Source: "{#ReleaseDir}\data\flutter_assets\assets\images\about\project_leader.jpg"; DestDir: "{app}\data\flutter_assets\assets\images\about"; Flags: ignoreversion
Source: "{#ReleaseDir}\data\flutter_assets\fonts\MaterialIcons-Regular.otf"; DestDir: "{app}\data\flutter_assets\fonts"; Flags: ignoreversion
Source: "{#ReleaseDir}\data\flutter_assets\packages\google_sign_in_all_platforms_desktop\assets\post_auth_page.html"; DestDir: "{app}\data\flutter_assets\packages\google_sign_in_all_platforms_desktop\assets"; Flags: ignoreversion
Source: "{#ReleaseDir}\data\flutter_assets\shaders\ink_sparkle.frag"; DestDir: "{app}\data\flutter_assets\shaders"; Flags: ignoreversion
Source: "{#ReleaseDir}\data\flutter_assets\shaders\stretch_effect.frag"; DestDir: "{app}\data\flutter_assets\shaders"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\Holistic Anecdotal Records"; Filename: "{app}\holistic_anecdotal_records.exe"; WorkingDir: "{app}"
Name: "{autodesktop}\Holistic Anecdotal Records"; Filename: "{app}\holistic_anecdotal_records.exe"; WorkingDir: "{app}"; Tasks: desktopicon

; No Run, UninstallRun, InstallDelete, UninstallDelete, user-folder writes,
; permission relaxation, or application launch. Normal uninstall tracking only.
