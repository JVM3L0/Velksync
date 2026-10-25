# Velksync

Liga, desliga e roda comandos no PC (Windows e Linux, dual boot) pelo celular, na rede local. O PC também manda ações para o celular.

```
celular (app Flutter)  ── Wake-on-LAN (UDP 9) ──────────▶  placa de rede do PC desligado
                       ── HTTPS com pin (TCP 41100) ────▶  velksync-agent (desligar, comandos, terminal)
                       ◀─ eventos SSE (/api/events) ────   velksync-agent send ...
                       ── descoberta (UDP 41101) ───────▶
```

- `agent/`: agente em Go. Um binário para Linux e um `.exe` para Windows.
- `app/`: app Flutter (Android; iOS com ressalvas, ver abaixo).

## 1. Preparar o PC para Wake-on-LAN

1. **BIOS/UEFI**: ative "Wake on LAN" / "Power On By PCI-E". Ligue o PC **por cabo**: WoL por Wi-Fi quase nunca funciona.
2. **Windows**:
   - Gerenciador de Dispositivos → placa de rede → *Avançado*: "Wake on Magic Packet" = Ativado.
   - Na aba *Gerenciamento de Energia*, marque "Permitir que este dispositivo ative o computador".
   - Desative a **Inicialização Rápida** (Painel de Controle → Opções de Energia → Escolher a função dos botões). Com ela ativa, o desligamento é uma hibernação e a placa costuma não acordar.
3. **Linux**: `sudo ethtool -s <interface> wol g`. Para persistir, use NetworkManager: `nmcli c modify <conexão> 802-3-ethernet.wake-on-lan magic`.
4. **Dual boot**: o WoL liga o PC no sistema padrão do GRUB/boot manager. O MAC é o mesmo nos dois sistemas, então no app é um único PC, que mostra qual SO está rodando.
5. Reserve um IP fixo para o PC no DHCP do roteador.

## 2. Instalar o agente

Compile (precisa de Go 1.25+; dá para compilar os dois no WSL/Linux):

```sh
cd agent && ./build.sh      # gera agent/dist/linux e agent/dist/windows
```

**Use o mesmo token mestre nos dois sistemas.** Instale primeiro em um, copie o token exibido e passe-o ao instalar no outro. Dele derivam o certificado HTTPS e as credenciais dos celulares, então os dois sistemas do dual boot são o mesmo PC para o app.

**Linux** (serviço systemd do usuário):
```sh
cd agent/dist/linux && ./install-linux.sh            # ou: ./install-linux.sh <token-do-windows>
```

**Windows** (PowerShell como administrador; roda no logon, sem janela):
```powershell
cd agent\dist\windows
powershell -ExecutionPolicy Bypass -File install-windows.ps1 -Token <token-do-linux>
```
A rede do Windows precisa estar como **Privada**: as regras de firewall valem só para ela e só para a sub-rede local. No Linux, o instalador libera as portas no `ufw` também só para a sub-rede local.

> **WSL com `networkingMode=mirrored`**: o WSL reserva no Windows a faixa de portas efêmeras do Linux (`cat /proc/sys/net/ipv4/ip_local_port_range`, ex.: 44620–48715). Se o agente do Windows falhar com "Only one usage of each socket address", a porta caiu nessa faixa: troque `port` na config.

Configuração:
- Linux: `~/.config/velksync/config.json`
- Windows: `%APPDATA%\velksync\config.json`

Reinicie o agente depois de editar a config.

```json
{
  "name": "PC do quarto",
  "port": 41100,
  "token": "…",
  "allow_shell": false,
  "command_timeout_seconds": 30,
  "commands": [
    { "id": "steam", "name": "Abrir Steam", "linux": "steam", "windows": "start \"\" \"C:\\Program Files (x86)\\Steam\\steam.exe\"" },
    { "id": "lock",  "name": "Bloquear tela", "linux": "loginctl lock-session", "windows": "rundll32.exe user32.dll,LockWorkStation" }
  ]
}
```

- `commands`: aparecem como botões no app. Um comando sem variante para o SO atual fica escondido.
- `allow_shell: true`: libera o **terminal livre** no app. Qualquer celular pareado roda qualquer coisa como seu usuário; deixe desligado se não usar. No Windows os comandos rodam via `cmd.exe`; no Linux, via `/bin/sh`.
- `devices` / `revoked`: mantidos pelo agente (celulares pareados e revogados). Não edite à mão.
- Logs: `journalctl --user -u velksync-agent -f` no Linux; `agent.log` ao lado da config no Windows.

## 3. PC → celular

Com o app aberto, o PC pode mandar:

```sh
velksync-agent send notify "Render terminou"
velksync-agent send clipboard "texto que vai para o celular"
velksync-agent send open_url https://example.com
velksync-agent send vibrate
```

Dá para usar no fim de scripts, por exemplo `make && velksync-agent send notify ok`. **Limitação**: só chega enquanto o app estiver aberto ou em primeiro plano. Receber com o app fechado exige push (FCM) ou um serviço em segundo plano no Android.

## 4. Rodar o app

```sh
cd app
flutter pub get
flutter run          # com o celular conectado (depuração USB ou sem fio)
flutter build apk    # APK de release em build/app/outputs/flutter-apk/
```

No app, em **Adicionar PC → Escanear QR do PC**: com o agente rodando, execute `velksync-agent pair` no PC e aponte a câmera. No Linux o QR aparece no terminal; no Windows abre como imagem. O QR leva o pin do certificado do PC e um código de uso único (5 minutos), trocado por uma credencial só deste celular. O `pair` percebe a leitura e apaga a imagem sozinho (também apaga se expirar ou com Ctrl+C).

Sem o QR dá para cadastrar um PC só com IP e MAC: ele fica "não pareado" e serve apenas para ligar. Para controlar, edite o PC e escaneie o QR.

Celulares pareados:
```sh
velksync-agent devices                 # lista os celulares pareados e revogados
velksync-agent revoke "motorola edge"  # revoga por nome ou id (no dual boot, nos dois sistemas)
velksync-agent fingerprint             # pin do certificado; confira com o mostrado no app
```

Use um **celular de verdade no mesmo Wi-Fi**. O emulador Android fica atrás de NAT, então broadcast (WoL e descoberta) não chega na sua rede.

**iOS**: a conexão com o agente funciona. Já broadcast UDP (WoL e descoberta) exige o entitlement `com.apple.developer.networking.multicast`, que a Apple precisa aprovar. Até lá, cadastre o IP manualmente; o botão Ligar não vai funcionar.

## Segurança

| Camada | Como |
|---|---|
| Canal | HTTPS (TLS 1.2+) com o certificado do PC fixado no app pelo hash da chave pública, que vem no QR. Sem o pin certo o app não conversa; um impostor na rede não consegue se passar pelo PC. |
| Credenciais | Cada celular recebe `id:token` próprio (HMAC do token mestre), revogável com `velksync-agent revoke`. O token mestre só é aceito vindo do próprio PC (localhost) e nunca sai dele. |
| Pareamento | Código de uso único, 128 bits, válido por 5 minutos, que nunca circula sem TLS. |
| Força bruta | 10 falhas de autenticação em 1 minuto bloqueiam o IP por 5 minutos. |
| Rede | Firewall liberado só para a sub-rede local (Windows: rede privada; Linux: `ufw`). |
| Celular | Credenciais no Android Keystore (`flutter_secure_storage`), backup e transferência entre aparelhos desligados, sem HTTP em texto puro. |
| Padrões | Terminal livre desligado por padrão; comandos com tempo limite e saída limitada. |

Testes das regras de segurança: `cd agent && go test ./...` e `cd app && flutter test`.

Não exponha a porta 41100 na internet. Para acesso de fora de casa, use uma VPN (Tailscale/WireGuard).

### Atualizando da v0.1

A v0.2 troca HTTP por HTTPS e o token único por credenciais por celular. Atualize o agente nos dois sistemas e o app; os PCs já cadastrados aparecem como "não pareados" (ligar continua funcionando) até você editar cada um e escanear o QR de novo.

## Próximos passos possíveis

- Ligar o PC fora de casa: dispositivo sempre ligado na LAN (Raspberry Pi/roteador) + Tailscale.
- Notificações reais (`flutter_local_notifications`) e recebimento em segundo plano.
- Widget/atalho na tela inicial para ligar com um toque.
