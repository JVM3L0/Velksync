# Velksync

Liga, desliga e roda comandos no PC (Windows e Linux, dual boot) pelo celular, na rede local. O PC também manda ações para o celular.

```
celular (app Flutter)  ── Wake-on-LAN (UDP 9) ──────────▶  placa de rede do PC desligado
                       ── HTTPS com pin (TCP 41100) ────▶  velksync-agent (energia, comandos, mídia, terminal)
                       ◀─ ao vivo SSE (/api/live) ──────   desempenho e mídia, só quando muda
                       ◀─ eventos SSE (/api/events) ────   velksync-agent send ...
                       ── presença/descoberta (UDP 41101) ▶ velksync-agent presence (antes do login)
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

Compile (precisa de Go 1.26+; dá para compilar os dois no WSL/Linux):

```sh
cd agent && ./build.sh      # gera agent/dist/linux e agent/dist/windows
```

**Use o mesmo token mestre nos dois sistemas.** Instale primeiro em um, copie o token exibido e passe-o ao instalar no outro. Dele derivam o certificado HTTPS e as credenciais dos celulares, então os dois sistemas do dual boot são o mesmo PC para o app.

**Linux** (serviço systemd do usuário, mais o serviço de presença do sistema, que pede `sudo`):
```sh
cd agent/dist/linux && ./install-linux.sh            # ou: ./install-linux.sh <token-do-windows>
```

**Windows** (PowerShell como administrador; roda no logon, sem janela):
```powershell
cd agent\dist\windows
powershell -ExecutionPolicy Bypass -File install-windows.ps1 -Token <token-do-linux>
```
O instalador também cria a tarefa **Velksync Presence**, que sobe no boot como `LocalService` (antes de qualquer login). Para atualizar, rode o instalador de novo: ele para as tarefas, troca os binários e reinicia.

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

## 4. Ligado antes do login (sinal de presença)

O agente principal só roda depois do login. Para o app saber que o PC já ligou (por exemplo, parado na tela de login depois do Wake-on-LAN), um processo mínimo, `velksync-agent presence`, sobe no boot e responde só a um desafio na porta UDP 41101: o celular manda um número aleatório e o PC devolve um HMAC dele com um segredo derivado do token mestre, que o app aprende ao parear. Ninguém sem o segredo consegue fingir que o PC está ligado, e a resposta não revela nada além disso.

No app aparece **Aguardando login**. O processo roda sem privilégios (`LocalService` no Windows; usuário dinâmico e sandbox do systemd no Linux), lê só o arquivo do segredo e responde no máximo 10 vezes por segundo por IP.

## 5. Desempenho do PC

O painel do PC no app mostra CPU, GPU, memória e disco em tempo real, no estilo do dashboard do Caelestia. Com agentes v0.4+, o PC empurra as leituras pelo canal ao vivo a cada 2 s, e só enquanto a tela do PC está aberta no app. Tocar em CPU, GPU ou Memória abre o gráfico dos últimos 2 minutos (mínimo, média e máximo), que o app vai guardando na memória enquanto você está na tela do PC. Fontes:

- **Windows**: APIs nativas (as mesmas do Gerenciador de Tarefas). O Windows não expõe temperaturas sem driver de terceiros, então elas não aparecem.
- **Linux**: `/proc` e `/sys`; GPU AMD pelo driver `amdgpu` e temperatura da CPU pelo `k10temp`/`coretemp`.

## 6. Mídia

A aba **Mídia** mostra o que está tocando no PC (capa, título, artista, posição) e controla play/pause, anterior, próxima, posição e o volume do PC. Funciona com qualquer player que se integre ao sistema: Spotify, navegadores, VLC etc.

- O fundo e os controles seguem as cores da capa; capas de vídeo mantêm o formato 16:9.
- Arraste a capa para os lados para trocar de faixa (só pula depois de 40% da largura ou num gesto rápido e longo, com vibração no ponto).
- O volume fica num botão ao lado do título, que abre uma pílula vertical.
- Depois de um comando, o agente lê o player várias vezes seguidas: a faixa nova aparece em cerca de 0,2 s.

- **Windows**: controles de mídia do sistema (o painel de mídia do Windows) e Core Audio para o volume. Um auxiliar do PowerShell embutido no agente é iniciado sob demanda, oculto, e se encerra após 2 minutos sem uso.
- **Linux**: MPRIS via D-Bus; volume pelo `wpctl` (PipeWire) ou `pactl` (PulseAudio).

A capa só é entregue se o arquivo for de fato uma imagem, e só vem de `file://` ou `https://`: um player ou página maliciosa não consegue usar o endereço da capa para vazar arquivos do PC nem acessar a rede interna.

## 7. Agendar

Com o PC ligado, **Agendar** desliga ou suspende depois de um tempo (1 minuto a 24 horas) ou **quando a mídia parar**. O PC avisa o celular 1 minuto antes (com o app aberto, como os outros avisos do PC) e dá para cancelar pelo app. O agendamento fica só na memória do agente: reiniciar o PC ou o agente cancela.

## 8. Atalho e widget (Android)

- **Configurações rápidas**: bloco **Ligar PC**, que manda o Wake-on-LAN sem abrir o app.
- **Widget** (tela inicial → Widgets → Velksync): nome do PC, último estado visto pelo app ("visto às 16:40") e um botão que pede confirmação. Com o PC desligado, **Ligar** num diálogo do próprio Android; ligado, **Desligar** abre o app, que confere o estado real e pergunta antes.
- Os dois usam o PC escolhido em **Configurações → Bloco "Ligar PC"**. Nenhum deles guarda credenciais: só nome, MAC e estado.

## 9. Rodar o app

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

## Releases

Cada tag `vX.Y.Z` enviada ao GitHub dispara o workflow `.github/workflows/release.yml`, que testa tudo e publica na página de Releases: APK assinado, agente para Linux (`.tar.gz`) e Windows (`.zip`), `SHA256SUMS` e atestado de proveniência (repositórios públicos). A tag precisa bater com a versão em `agent/main.go` e `app/pubspec.yaml`.

Configuração única da chave de assinatura do app:

```sh
keytool -genkeypair -keystore velksync-release.jks -storetype PKCS12 -alias velksync \
  -keyalg RSA -keysize 4096 -validity 10000 -dname "CN=Velksync"
base64 -w0 velksync-release.jks   # conteúdo do secret ANDROID_KEYSTORE_BASE64
```

Em *Settings → Secrets and variables → Actions* do repositório, crie `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` (`velksync`) e `ANDROID_KEY_PASSWORD` (com PKCS12, a mesma senha da keystore). **Guarde o `.jks` e a senha num backup seguro**: sem eles não dá para publicar atualizações que o Android aceite por cima da versão instalada. Nunca coloque o `.jks` no repositório (o `.gitignore` bloqueia).

## Segurança

| Camada | Como |
|---|---|
| Canal | HTTPS (só TLS 1.3) com o certificado do PC fixado no app pelo hash da chave pública, que vem no QR. Sem o pin certo o app não conversa; um impostor na rede não consegue se passar pelo PC. |
| Credenciais | Cada celular recebe `id:token` próprio (HMAC do token mestre), revogável com `velksync-agent revoke`. O token mestre só é aceito vindo do próprio PC (localhost) e nunca sai dele. |
| Pareamento | Código de uso único, 128 bits, válido por 5 minutos, que nunca circula sem TLS. |
| Força bruta | 10 falhas de autenticação em 1 minuto bloqueiam o IP por 5 minutos. |
| Servidor | Limites de tempo de leitura e de cabeçalho; no máximo 3 canais ao vivo por celular. |
| Presença | Desafio-resposta com HMAC e segredo próprio (derivado do token mestre); processo sem privilégios, sandbox no Linux, limite de respostas por IP. |
| Widget e atalho | Só nome, MAC e estado; desligar sempre passa pelo app e pede confirmação. Componentes internos não exportados. |
| Rede | Firewall liberado só para a sub-rede local (Windows: rede privada; Linux: `ufw`). |
| Celular | Credenciais no Android Keystore (`flutter_secure_storage`), backup e transferência entre aparelhos desligados, sem HTTP em texto puro. |
| Padrões | Terminal livre desligado por padrão; comandos com tempo limite e saída limitada. |

Testes das regras de segurança: `cd agent && go test ./...` e `cd app && flutter test`.

Não exponha a porta 41100 na internet. Para acesso de fora de casa, use uma VPN (Tailscale/WireGuard).

### Atualizando da v0.3

Rode o instalador de novo nos dois sistemas: ele instala o sinal de presença e o agente com o canal ao vivo, o agendamento e o conserto do volume no Windows. Os celulares continuam pareados. O app aprende o segredo de presença sozinho na primeira vez que falar com o PC atualizado.

### Atualizando da v0.1

A v0.2 troca HTTP por HTTPS e o token único por credenciais por celular. Atualize o agente nos dois sistemas e o app; os PCs já cadastrados aparecem como "não pareados" (ligar continua funcionando) até você editar cada um e escanear o QR de novo.

## Próximos passos possíveis

- Ligar o PC fora de casa: dispositivo sempre ligado na LAN (Raspberry Pi/roteador) + Tailscale.
- Notificações reais (`flutter_local_notifications`) e recebimento em segundo plano.
- Controles de mídia na notificação e na tela de bloqueio (ver `ROADMAP.md`).
