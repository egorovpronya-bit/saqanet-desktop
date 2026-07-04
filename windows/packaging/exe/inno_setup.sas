[Setup]
AppId={{APP_ID}}
AppVersion={{APP_VERSION}}
AppName={{DISPLAY_NAME}}
AppPublisher={{PUBLISHER_NAME}}
AppPublisherURL={{PUBLISHER_URL}}
AppSupportURL={{PUBLISHER_URL}}
AppUpdatesURL={{PUBLISHER_URL}}
DefaultDirName={{INSTALL_DIR_NAME}}
DisableProgramGroupPage=yes
OutputDir=.
OutputBaseFilename={{OUTPUT_BASE_FILENAME}}
Compression=lzma
SolidCompression=yes
SetupIconFile={{SETUP_ICON_FILE}}
WizardStyle=modern
PrivilegesRequired={{PRIVILEGES_REQUIRED}}
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
CloseApplications=force

[Languages]
{% for locale in LOCALES %}
{% if locale == 'en' %}Name: "english"; MessagesFile: "compiler:Default.isl"{% endif %}
{% if locale == 'hy' %}Name: "armenian"; MessagesFile: "compiler:Languages\\Armenian.isl"{% endif %}
{% if locale == 'bg' %}Name: "bulgarian"; MessagesFile: "compiler:Languages\\Bulgarian.isl"{% endif %}
{% if locale == 'ca' %}Name: "catalan"; MessagesFile: "compiler:Languages\\Catalan.isl"{% endif %}
{% if locale == 'zh' %}Name: "chinesesimplified"; MessagesFile: "compiler:Languages\\ChineseSimplified.isl"{% endif %}
{% if locale == 'co' %}Name: "corsican"; MessagesFile: "compiler:Languages\\Corsican.isl"{% endif %}
{% if locale == 'cs' %}Name: "czech"; MessagesFile: "compiler:Languages\\Czech.isl"{% endif %}
{% if locale == 'da' %}Name: "danish"; MessagesFile: "compiler:Languages\\Danish.isl"{% endif %}
{% if locale == 'nl' %}Name: "dutch"; MessagesFile: "compiler:Languages\\Dutch.isl"{% endif %}
{% if locale == 'fi' %}Name: "finnish"; MessagesFile: "compiler:Languages\\Finnish.isl"{% endif %}
{% if locale == 'fr' %}Name: "french"; MessagesFile: "compiler:Languages\\French.isl"{% endif %}
{% if locale == 'de' %}Name: "german"; MessagesFile: "compiler:Languages\\German.isl"{% endif %}
{% if locale == 'he' %}Name: "hebrew"; MessagesFile: "compiler:Languages\\Hebrew.isl"{% endif %}
{% if locale == 'is' %}Name: "icelandic"; MessagesFile: "compiler:Languages\\Icelandic.isl"{% endif %}
{% if locale == 'it' %}Name: "italian"; MessagesFile: "compiler:Languages\\Italian.isl"{% endif %}
{% if locale == 'ja' %}Name: "japanese"; MessagesFile: "compiler:Languages\\Japanese.isl"{% endif %}
{% if locale == 'no' %}Name: "norwegian"; MessagesFile: "compiler:Languages\\Norwegian.isl"{% endif %}
{% if locale == 'pl' %}Name: "polish"; MessagesFile: "compiler:Languages\\Polish.isl"{% endif %}
{% if locale == 'pt' %}Name: "portuguese"; MessagesFile: "compiler:Languages\\Portuguese.isl"{% endif %}
{% if locale == 'ru' %}Name: "russian"; MessagesFile: "compiler:Languages\\Russian.isl"{% endif %}
{% if locale == 'sk' %}Name: "slovak"; MessagesFile: "compiler:Languages\\Slovak.isl"{% endif %}
{% if locale == 'sl' %}Name: "slovenian"; MessagesFile: "compiler:Languages\\Slovenian.isl"{% endif %}
{% if locale == 'es' %}Name: "spanish"; MessagesFile: "compiler:Languages\\Spanish.isl"{% endif %}
{% if locale == 'tr' %}Name: "turkish"; MessagesFile: "compiler:Languages\\Turkish.isl"{% endif %}
{% if locale == 'uk' %}Name: "ukrainian"; MessagesFile: "compiler:Languages\\Ukrainian.isl"{% endif %}
{% endfor %}

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: {% if CREATE_DESKTOP_ICON != true %}unchecked{% else %}checkedonce{% endif %}
Name: "launchAtStartup"; Description: "{cm:AutoStartProgram,{{DISPLAY_NAME}}}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: {% if LAUNCH_AT_STARTUP != true %}unchecked{% else %}checkedonce{% endif %}

[Files]
Source: "{{SOURCE_DIR}}\\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; NOTE: Don't use "Flags: ignoreversion" on any shared system files

[Icons]
; Shortcuts point to wscript launcher — no UAC popup on every run
Name: "{autoprograms}\\{{DISPLAY_NAME}}"; Filename: "{sys}\\wscript.exe"; Parameters: """{app}\\launcher.vbs"""; WorkingDir: "{app}"; IconFilename: "{app}\\{{EXECUTABLE_NAME}}"
Name: "{autodesktop}\\{{DISPLAY_NAME}}"; Filename: "{sys}\\wscript.exe"; Parameters: """{app}\\launcher.vbs"""; WorkingDir: "{app}"; IconFilename: "{app}\\{{EXECUTABLE_NAME}}"; Tasks: desktopicon
Name: "{userstartup}\\{{DISPLAY_NAME}}"; Filename: "{sys}\\wscript.exe"; Parameters: """{app}\\launcher.vbs"""; WorkingDir: "{app}"; Tasks: launchAtStartup

[Run]
Filename: "{app}\\{{EXECUTABLE_NAME}}"; Description: "{cm:LaunchProgram,{{DISPLAY_NAME}}}"; Flags: {% if PRIVILEGES_REQUIRED == 'admin' %}runascurrentuser{% endif %} nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{userappdata}\Hiddify"
Type: files; Name: "{app}\launcher.vbs"

[Code]
function InitializeSetup(): Boolean;
var
  ResultCode: Integer;
begin
  Exec('taskkill', '/F /IM hiddify.exe', '', SW_HIDE, ewWaitUntilTerminated, ResultCode)
  Exec('net', 'stop "HiddifyTunnelService"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode)
  Exec('sc.exe', 'delete "HiddifyTunnelService"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode)
  Result := True;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
  ExePath, TempXml, LauncherVbs: string;
  Xml: string;
begin
  if CurStep = ssPostInstall then
  begin
    ExePath := ExpandConstant('{app}\{{EXECUTABLE_NAME}}');

    // Create launcher.vbs — runs schtasks silently, no window flash
    LauncherVbs := ExpandConstant('{app}\launcher.vbs');
    SaveStringToFile(LauncherVbs,
      'CreateObject("WScript.Shell").Run "schtasks /run /tn ""SAQANet""", 0, False',
      False);

    // Create Task Scheduler task via XML so it has no trigger (manual/on-demand only)
    Xml :=
      '<?xml version="1.0" encoding="UTF-16"?>' + #13#10 +
      '<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">' + #13#10 +
      '  <RegistrationInfo><Description>SAQANet VPN (no UAC)</Description></RegistrationInfo>' + #13#10 +
      '  <Triggers/>' + #13#10 +
      '  <Principals>' + #13#10 +
      '    <Principal id="Author">' + #13#10 +
      '      <LogonType>InteractiveToken</LogonType>' + #13#10 +
      '      <RunLevel>HighestAvailable</RunLevel>' + #13#10 +
      '    </Principal>' + #13#10 +
      '  </Principals>' + #13#10 +
      '  <Settings>' + #13#10 +
      '    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>' + #13#10 +
      '    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>' + #13#10 +
      '    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>' + #13#10 +
      '    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>' + #13#10 +
      '    <Priority>7</Priority>' + #13#10 +
      '  </Settings>' + #13#10 +
      '  <Actions Context="Author">' + #13#10 +
      '    <Exec>' + #13#10 +
      '      <Command>' + ExePath + '</Command>' + #13#10 +
      '    </Exec>' + #13#10 +
      '  </Actions>' + #13#10 +
      '</Task>';

    TempXml := ExpandConstant('{tmp}\saqanet_task.xml');
    SaveStringToFile(TempXml, Xml, False);
    Exec(ExpandConstant('{sys}\schtasks.exe'),
      '/create /tn "SAQANet" /xml "' + TempXml + '" /f',
      '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    DeleteFile(TempXml);
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  ResultCode: Integer;
begin
  if CurUninstallStep = usPostUninstall then
    Exec(ExpandConstant('{sys}\schtasks.exe'),
      '/delete /tn "SAQANet" /f',
      '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;
