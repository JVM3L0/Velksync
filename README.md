# Velksync

Liga, desliga e roda comandos no PC (Windows e Linux, dual boot) pelo celular, na rede local. O PC também manda ações para o celular.

```
celular (app Flutter)  ── Wake-on-LAN (UDP 9) ──────────▶  placa de rede do PC desligado
                       ── HTTP + token (TCP 41100) ─────▶  velksync-agent (desligar, comandos, terminal)
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

Compile (precisa de Go 1.22+; dá para compilar os dois no WSL/Linux):

```sh
cd agent && ./build.sh      # gera agent/dist/linux e agent/dist/windows
```

**Use o mesmo token nos dois sistemas.** Instale primeiro em um, copie o token exibido e passe-o ao instalar no outro.

**Linux** (serviço systemd do usuário):
```sh
cd agent/dist/linux && ./install-linux.sh            # ou: ./install-linux.sh <token-do-windows>
```

**Windows** (PowerShell como administrador; roda no logon, sem janela):
```powershell
cd agent\dist\windows
powershell -ExecutionPolicy Bypass -File install-windows.ps1 -Token <token-do-linux>
```
A rede do Windows precisa estar como **Privada** (as regras de firewall valem só para ela).

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
- `allow_shell: true`: libera o **terminal livre** no app. Quem tiver o token roda qualquer coisa como seu usuário. No Windows os comandos rodam via `cmd.exe`; no Linux, via `/bin/sh`.
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

No app, em **Adicionar PC**:
- **Escanear QR do PC** (mais fácil): com o agente rodando, execute `velksync-agent pair` no PC e aponte a câmera. No Linux o QR aparece no terminal; no Windows abre como imagem. O QR não leva o token, e sim um código de uso único que vale 5 minutos: o app troca esse código pelo token, e o `pair` percebe a leitura e apaga a imagem sozinho (também apaga se expirar ou com Ctrl+C).
- Ou toque num PC encontrado na busca e cole o token (`velksync-agent token`).

Use um **celular de verdade no mesmo Wi-Fi**. O emulador Android fica atrás de NAT, então broadcast (WoL e descoberta) não chega na sua rede.

**iOS**: HTTP para o agente funciona. Já broadcast UDP (WoL e descoberta) exige o entitlement `com.apple.developer.networking.multicast`, que a Apple precisa aprovar. Até lá, cadastre o IP manualmente; o botão Ligar não vai funcionar.

## Segurança

- Tudo é HTTP sem TLS dentro da LAN. O token (256 bits) protege as chamadas, mas alguém na mesma rede capturando tráfego consegue lê-lo. Não exponha a porta 41100 na internet. Para acesso remoto, use Tailscale/WireGuard.
- No celular, o token fica no `shared_preferences`. Um próximo passo seria trocar por `flutter_secure_storage`.

## Próximos passos possíveis

- Ligar o PC fora de casa: dispositivo sempre ligado na LAN (Raspberry Pi/roteador) + Tailscale.
- Notificações reais (`flutter_local_notifications`) e recebimento em segundo plano.
- Widget/atalho na tela inicial para ligar com um toque.
