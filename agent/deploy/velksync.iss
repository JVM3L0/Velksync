; Instalador do Velksync para Windows (Inno Setup 6).
;
; Não duplica a instalação: roda o mesmo install-windows.ps1 do .zip, e o
; desinstalador roda o uninstall-windows.ps1. O que ele acrescenta são as
; telas: Wake-on-LAN (velksync-agent doctor), token do dual boot e pareamento.
;
; Compilar: agent/deploy/build-installer.ps1 -Version 0.5.0 -AgentExe <velksync-agent.exe>
; Silencioso (CI): velksync-setup.exe /VERYSILENT /SUPPRESSMSGBOXES [/FIX=magic,wake]

#ifndef AppVersion
  #define AppVersion "0.0.0-dev"
#endif
#ifndef AgentExe
  #define AgentExe "..\dist\windows\velksync-agent.exe"
#endif

[Setup]
; Nunca mude o AppId: é por ele que o Windows reconhece atualizações.
AppId={{141A2B8E-A02E-46C9-A895-40AD37BF0BD0}
AppName=Velksync
AppVersion={#AppVersion}
AppVerName=Velksync {#AppVersion}
AppPublisher=Velksync
AppPublisherURL=https://github.com/JVM3L0/Velksync
AppSupportURL=https://github.com/JVM3L0/Velksync/issues
AppUpdatesURL=https://github.com/JVM3L0/Velksync/releases
; O mesmo lugar onde o script põe o sinal de presença.
DefaultDirName={autopf}\Velksync
DisableDirPage=yes
DisableProgramGroupPage=yes
DisableWelcomePage=no
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
WizardStyle=modern
WizardImageFile=installer\side-1x.bmp,installer\side-2x.bmp
WizardSmallImageFile=installer\small-1x.bmp,installer\small-2x.bmp
SetupIconFile=installer\velksync.ico
UninstallDisplayIcon={app}\velksync.ico
UninstallDisplayName=Velksync
OutputBaseFilename=velksync-setup-{#AppVersion}-windows-amd64
Compression=lzma2/max
SolidCompression=yes
; O script para o agente sozinho antes de trocar o .exe.
CloseApplications=no
; Um instalador por vez: dois ao mesmo tempo brigam pelo mesmo .exe.
SetupMutex=VelksyncSetup,Global\VelksyncSetup
SetupLogging=yes

[Languages]
Name: "ptbr"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"

[Messages]
WelcomeLabel1=Velksync para Windows
FinishedHeadingLabel=Pronto!

[Files]
; dontcopy: vão para a pasta temporária e o install-windows.ps1 os coloca no lugar.
Source: "{#AgentExe}"; Flags: dontcopy
Source: "install-windows.ps1"; Flags: dontcopy
Source: "uninstall-windows.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "installer\velksync.ico"; DestDir: "{app}"; Flags: ignoreversion

[UninstallDelete]
; O install-windows.ps1 cria a pasta antes do Inno copiar os arquivos, então
; o Inno não a considera dele e não a apagaria.
Type: dirifempty; Name: "{app}"

[Run]
Filename: "{localappdata}\Velksync\velksync-agent.exe"; Parameters: "pair"; \
  Description: "Parear um celular agora (mostra o QR para o app)"; \
  Flags: postinstall nowait runasoriginaluser skipifsilent

[Code]
const
  ReadmeWol = 'https://github.com/JVM3L0/Velksync#1-preparar-o-pc-para-wake-on-lan';

var
  WolPage, TokenPage: TWizardPage;
  WolLoaded: Boolean;
  WolIds: array of String;
  WolBoxes: array of TNewCheckBox;
  FirstRadio, OtherRadio: TNewRadioButton;
  TokenEdit: TPasswordEdit;
  FixWarning: String;

function PowerShell: String;
begin
  // {sys} em modo 64 bits é o System32 de verdade: o PowerShell de 32 bits
  // apontaria $env:ProgramFiles para "Arquivos de Programas (x86)".
  Result := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
end;

function AgentTmp: String;
begin
  Result := ExpandConstant('{tmp}\velksync-agent.exe');
end;

function IsUpdate: Boolean;
begin
  Result := FileExists(ExpandConstant('{userappdata}\velksync\config.json'));
end;

function AddText(Parent: TWizardPage; Top: Integer; Caption: String): TNewStaticText;
begin
  Result := TNewStaticText.Create(Parent);
  Result.Parent := Parent.Surface;
  Result.Top := Top;
  Result.Width := Parent.SurfaceWidth;
  Result.WordWrap := True;
  Result.AutoSize := True;
  Result.Caption := Caption;
end;

procedure OpenReadme(Sender: TObject);
var
  RC: Integer;
begin
  ShellExecAsOriginalUser('open', ReadmeWol, '', '', SW_SHOWNORMAL, ewNoWait, RC);
end;

{ ---------- Tela 2: Wake-on-LAN ---------- }

function Symbol(Status: String): String;
begin
  if Status = 'ok' then Result := #$2714
  else if Status = 'fail' then Result := #$2716
  else if Status = 'warn' then Result := '!'
  else Result := '?';
end;

procedure LoadWol;
var
  Ini, Ids, Id, Status, Hint: String;
  I, N, Top, RC: Integer;
  Line: TNewStaticText;
  Box: TNewCheckBox;
  Bios: TNewStaticText;
begin
  WolLoaded := True;
  Ini := ExpandConstant('{tmp}\doctor.ini');
  ExtractTemporaryFile('velksync-agent.exe');
  if not Exec(AgentTmp, 'doctor -out "' + Ini + '"', '', SW_HIDE, ewWaitUntilTerminated, RC) or not FileExists(Ini) then
  begin
    AddText(WolPage, 0, 'Não deu para conferir a placa de rede daqui. A instalação continua normalmente; ' +
      'o passo a passo do Wake-on-LAN está no README.');
    Exit;
  end;

  Top := 0;
  N := 0;
  Ids := GetIniString('summary', 'checks', '', Ini) + ',';
  while Pos(',', Ids) > 0 do
  begin
    I := Pos(',', Ids);
    Id := Copy(Ids, 1, I - 1);
    Delete(Ids, 1, I);
    if Id = '' then Continue;
    Status := GetIniString(Id, 'status', '', Ini);
    Hint := GetIniString(Id, 'hint', '', Ini);

    Line := AddText(WolPage, Top, Symbol(Status) + '   ' + GetIniString(Id, 'label', Id, Ini));
    Line.Width := WolPage.SurfaceWidth - ScaleX(100);
    if Status = 'ok' then Line.Font.Color := clGreen
    else if Status = 'fail' then Line.Font.Color := clMaroon;

    if GetIniString(Id, 'fixable', '0', Ini) = '1' then
    begin
      Box := TNewCheckBox.Create(WolPage);
      Box.Parent := WolPage.Surface;
      Box.Caption := 'Corrigir';
      Box.Checked := True;
      Box.Left := WolPage.SurfaceWidth - ScaleX(90);
      Box.Top := Top;
      Box.Width := ScaleX(90);
      SetArrayLength(WolIds, N + 1);
      SetArrayLength(WolBoxes, N + 1);
      WolIds[N] := Id;
      WolBoxes[N] := Box;
      N := N + 1;
    end;
    Top := Top + Line.Height + ScaleY(2);
    if Hint <> '' then
    begin
      Line := AddText(WolPage, Top, '      ' + Hint);
      Line.Font.Color := clGray;
      Top := Top + Line.Height;
    end;
    Top := Top + ScaleY(8);
  end;

  Bios := AddText(WolPage, Top, '?   BIOS/UEFI: "Wake on LAN" ou "Power On By PCI-E" (não dá para ver daqui)');
  Top := Top + Bios.Height + ScaleY(2);
  Bios := AddText(WolPage, Top, '      Como ativar na BIOS e no roteador');
  Bios.Font.Color := clBlue;
  Bios.Font.Style := [fsUnderline];
  Bios.Cursor := crHand;
  Bios.OnClick := @OpenReadme;
  Top := Top + Bios.Height + ScaleY(16);

  if N > 0 then
    AddText(WolPage, Top, 'Nada é alterado sem a caixa marcada. As correções valem a partir do próximo desligamento.')
  else
    AddText(WolPage, Top, 'Nada a corrigir por aqui.');
end;

function SelectedFixes: String;
var
  I: Integer;
begin
  if WizardSilent then
  begin
    Result := ExpandConstant('{param:FIX|}');
    Exit;
  end;
  Result := '';
  for I := 0 to GetArrayLength(WolBoxes) - 1 do
    if WolBoxes[I].Checked then
    begin
      if Result <> '' then Result := Result + ',';
      Result := Result + WolIds[I];
    end;
end;

{ ---------- Tela 3: dual boot ---------- }

procedure TokenModeChanged(Sender: TObject);
begin
  TokenEdit.Enabled := OtherRadio.Checked;
  if OtherRadio.Checked then WizardForm.ActiveControl := TokenEdit;
end;

procedure CreateTokenPage;
var
  Top: Integer;
  Note: TNewStaticText;
begin
  TokenPage := CreateCustomPage(WolPage.ID, 'Dual boot',
    'Este PC também tem Linux com o Velksync instalado?');
  Note := AddText(TokenPage, 0, 'Com o mesmo token mestre, Windows e Linux viram um só PC no app, ' +
    'e os celulares pareados funcionam nos dois.');
  Top := Note.Height + ScaleY(16);

  FirstRadio := TNewRadioButton.Create(TokenPage);
  FirstRadio.Parent := TokenPage.Surface;
  FirstRadio.Top := Top;
  FirstRadio.Width := TokenPage.SurfaceWidth;
  FirstRadio.Caption := 'É a primeira instalação do Velksync neste PC';
  FirstRadio.Checked := True;
  FirstRadio.OnClick := @TokenModeChanged;
  Top := Top + ScaleY(28);

  OtherRadio := TNewRadioButton.Create(TokenPage);
  OtherRadio.Parent := TokenPage.Surface;
  OtherRadio.Top := Top;
  OtherRadio.Width := TokenPage.SurfaceWidth;
  OtherRadio.Caption := 'Já instalei no Linux deste PC: usar o mesmo token';
  OtherRadio.OnClick := @TokenModeChanged;
  Top := Top + ScaleY(28);

  TokenEdit := TPasswordEdit.Create(TokenPage);
  TokenEdit.Parent := TokenPage.Surface;
  TokenEdit.Top := Top;
  TokenEdit.Left := ScaleX(18);
  TokenEdit.Width := TokenPage.SurfaceWidth - ScaleX(18);
  TokenEdit.Enabled := False;
  Top := Top + TokenEdit.Height + ScaleY(6);

  Note := AddText(TokenPage, Top, 'No Linux, mostre o token com:  velksync-agent token');
  Note.Left := ScaleX(18);
  Note.Font.Color := clGray;
end;

{ ---------- Assistente ---------- }

procedure InitializeWizard;
var
  Intro: String;
begin
  Intro := 'Ligue, controle e acompanhe este PC pelo celular, na sua rede de casa.' + #13#10#13#10 +
    'Vai instalar:' + #13#10 +
    '  •  o agente, que abre quando você entra no Windows' + #13#10 +
    '  •  o sinal de presença, que avisa o app antes do login' + #13#10 +
    '  •  regras de firewall só para a rede local' + #13#10#13#10;
  if IsUpdate then
    Intro := Intro + 'O Velksync já está instalado: ele será atualizado, mantendo a configuração e os celulares pareados.' + #13#10#13#10;
  Intro := Intro + 'Se o Windows avisou "aplicativo não reconhecido", é porque este instalador não tem assinatura paga. ' +
    'Confira o código dele no arquivo SHA256SUMS da página de versões.';
  WizardForm.WelcomeLabel2.Caption := Intro;

  WolPage := CreateCustomPage(wpWelcome, 'Wake-on-LAN', 'O que o Windows precisa para o celular ligar este PC.');
  CreateTokenPage;
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if (CurPageID = WolPage.ID) and not WolLoaded then
  begin
    WizardForm.NextButton.Enabled := False;
    WizardForm.BackButton.Enabled := False;
    WolPage.Description := 'Conferindo a placa de rede…';
    WizardForm.Repaint;
    try
      LoadWol;
    finally
      WolPage.Description := 'O que o Windows precisa para o celular ligar este PC.';
      WizardForm.NextButton.Enabled := True;
      WizardForm.BackButton.Enabled := True;
    end;
  end;

  if CurPageID = wpFinished then
  begin
    WizardForm.FinishedLabel.Caption := 'O Velksync está instalado e rodando.' + #13#10#13#10 +
      'Para parear: no app do celular, toque em Adicionar PC e depois em Escanear QR do PC.' + #13#10#13#10 +
      'Para desinstalar: Configurações > Aplicativos > Velksync.';
    if FixWarning <> '' then
      WizardForm.FinishedLabel.Caption := WizardForm.FinishedLabel.Caption + #13#10#13#10 + FixWarning;
  end;
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  // Atualização: o token já está na configuração.
  Result := (PageID = TokenPage.ID) and IsUpdate;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if (CurPageID = TokenPage.ID) and OtherRadio.Checked and (Length(Trim(TokenEdit.Text)) < 32) then
  begin
    MsgBox('Cole o token mestre do Linux (pelo menos 32 caracteres).', mbError, MB_OK);
    Result := False;
  end;
end;

function UpdateReadyMemo(Space, NewLine, MemoUserInfoInfo, MemoDirInfo, MemoTypeInfo, MemoComponentsInfo,
  MemoGroupInfo, MemoTasksInfo: String): String;
var
  Fixes: String;
begin
  if IsUpdate then
    Result := 'Atualizar o Velksync para a versão {#AppVersion}' + NewLine + Space + 'mantendo a configuração e os celulares pareados'
  else
    Result := 'Instalar o Velksync {#AppVersion}';
  Fixes := SelectedFixes;
  Result := Result + NewLine + NewLine + 'Wake-on-LAN:' + NewLine + Space;
  if Fixes = '' then Result := Result + 'nada a alterar'
  else Result := Result + 'corrigir ' + Fixes;
  if not IsUpdate and OtherRadio.Checked then
    Result := Result + NewLine + NewLine + 'Token:' + NewLine + Space + 'o mesmo do Linux';
end;

{ ---------- Instalação ---------- }

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  Progress: TOutputProgressWizardPage;
  Fixes, Args, TokenFile, LogFile, SavedLog: String;
  RC: Integer;
begin
  Result := '';
  Progress := CreateOutputProgressPage('Instalando', 'Isso leva alguns segundos.');
  Progress.Show;
  try
    ExtractTemporaryFile('velksync-agent.exe');
    ExtractTemporaryFile('install-windows.ps1');

    Fixes := SelectedFixes;
    if Fixes <> '' then
    begin
      Progress.SetText('Ajustando o Wake-on-LAN…', Fixes);
      Progress.SetProgress(1, 4);
      if not Exec(AgentTmp, 'doctor -fix ' + Fixes, '', SW_HIDE, ewWaitUntilTerminated, RC) or (RC <> 0) then
        FixWarning := 'Algumas correções do Wake-on-LAN não foram aplicadas. Confira depois com: velksync-agent doctor';
    end;

    Progress.SetText('Instalando o agente e o sinal de presença…', '');
    Progress.SetProgress(2, 4);
    LogFile := ExpandConstant('{tmp}\install.log');
    Args := '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + ExpandConstant('{tmp}\install-windows.ps1') +
      '" -LogFile "' + LogFile + '"';
    TokenFile := ExpandConstant('{tmp}\token.txt');
    if not IsUpdate and not WizardSilent and OtherRadio.Checked then
    begin
      // Por arquivo na pasta temporária do instalador (só do administrador),
      // nunca pela linha de comando.
      SaveStringToFile(TokenFile, Trim(TokenEdit.Text), False);
      Args := Args + ' -TokenFile "' + TokenFile + '"';
    end;
    if not Exec(PowerShell, Args, '', SW_HIDE, ewWaitUntilTerminated, RC) or (RC <> 0) then
    begin
      SavedLog := ExpandConstant('{%TEMP}\velksync-install.log');
      CopyFile(LogFile, SavedLog, False);
      Result := 'A instalação do agente falhou (código ' + IntToStr(RC) + '). O registro está em ' + SavedLog;
    end;
    DeleteFile(TokenFile);
    Progress.SetProgress(4, 4);
  finally
    Progress.Hide;
  end;
end;

{ ---------- Desinstalação ---------- }

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Args: String;
  RC: Integer;
begin
  if CurUninstallStep <> usUninstall then Exit;
  Args := '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + ExpandConstant('{app}\uninstall-windows.ps1') + '"';
  if not UninstallSilent and (MsgBox('Manter os celulares pareados?' + #13#10#13#10 +
    'Se instalar de novo depois, não vai precisar parear. Escolha Não para apagar também a configuração e o token.',
    mbConfirmation, MB_YESNO) = IDNO) then
    Args := Args + ' -RemoveConfig';
  Exec(PowerShell, Args, '', SW_HIDE, ewWaitUntilTerminated, RC);
end;
