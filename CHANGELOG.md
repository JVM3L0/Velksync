# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/);
versões seguem [SemVer](https://semver.org/lang/pt-BR/).

## [0.5.0] - 2026-10-27

### Adicionado
- Instalador do Windows (`velksync-setup-…-windows-amd64.exe`): confere e
  corrige o Wake-on-LAN, pede o token do Linux no dual boot, pareia o
  celular no fim e aparece em Aplicativos, com desinstalador. Compilado e
  testado (instalar, atualizar, desinstalar) pelo CI.
- `velksync-agent doctor`: confere o Wake-on-LAN no Windows; `-fix` corrige.
- `uninstall-windows.ps1` para quem instalou pelo `.zip`.
- Diagrama do README em SVG, nas versões clara e escura.
- Ícone na bandeja do Windows: parear (janela do QR que fecha sozinha),
  revogar celulares, conferir e corrigir o Wake-on-LAN, cancelar
  agendamento, log, configuração e sair.
- Contagem de 10 s antes de desligar, reiniciar ou suspender pelo celular
  quando alguém está usando o PC (sessão desbloqueada), com Cancelar; o
  celular é avisado se cancelarem (`power_grace_seconds`).
- Avisos do Windows quando um celular pareia, roda um comando ou agenda o
  desligamento (`tray_notices`).

### Alterado
- O instalador por script não mostra mais o token mestre; veja com
  `velksync-agent token`. `init -token-file` lê o token de um arquivo.
- `pair` espera o agente subir e, aberto sem terminal, avisa por janela
  quando o celular parear.
- "Como atualizar" no app indica o instalador no Windows.

## [0.4.1] - 2026-10-25

### Adicionado
- Aviso na aba Controle quando app e agente estão em versões diferentes, com
  o passo a passo de atualização do sistema daquele PC.
- CI a cada envio (testes, análise e formatação) e Dependabot semanal.
- Tema **Velksync** (gelo e marinho do ícone) e abertura do app com a marca.
- Licença GPL-3.0.

### Corrigido
- Play no app não tocava vídeos em abas do navegador paradas há muito tempo
  (a aba congelada aceita o play e diz "tocando", mas não toca). Mídia
  pausada há mais de 10 minutos agora some do player (`media_idle_minutes`).

### Alterado
- Release publica um APK por processador (~25 MB em vez de ~72 MB).
- O app de desenvolvimento é o "Velksync Dev" (`com.velksync.velksync.debug`)
  e convive com o da release.
- Cor reserva do app e do widget (sem Material You) passa de roxo para o gelo
  do ícone.

## [0.4.0] - 2026-10-25

### Adicionado
- **Sinal de presença**: o app mostra "Aguardando login" quando o PC já
  ligou mas ninguém entrou. Processo mínimo no boot, sem privilégios,
  respondendo a um desafio HMAC na porta UDP 41101.
- **Ligar com retorno**: o app reenvia o Wake-on-LAN (10 s e 30 s),
  acompanha até 2 minutos e, se não ligar, mostra o que conferir. Quando
  liga: vibração e "Velkhyro ligou em 38 s".
- **Canal ao vivo** (`/api/live`): desempenho e mídia empurrados pelo PC,
  só enquanto alguém olha e só quando algo muda.
- **Agendar** desligar/suspender depois de um tempo ou quando a mídia parar,
  com aviso 1 minuto antes e cancelamento pelo app.
- **Gráficos de desempenho**: tocar em CPU, GPU ou Memória mostra os últimos
  2 minutos, com mínimo, média e máximo.
- **Player redesenhado**: cores e formato da capa, título rolante, volume em
  pílula vertical, arrastar a capa para trocar de faixa (protegido contra
  toque acidental), cache das últimas 20 capas.
- **Android**: bloco "Ligar PC" nas Configurações rápidas e widget na tela
  inicial (ligar com confirmação; desligar pelo app, com confirmação).
- Temas suaves: Gruvbox Material e Catppuccin Frappé/Macchiato, todos com
  contraste AA garantido.
- Transições do Material (container transform, eixo compartilhado) e volta
  preditiva do Android.

### Alterado
- Só TLS 1.3 e limites de tempo no servidor do agente.
- A troca de faixa chega ao app em cerca de 0,2 s (o agente relê o player
  logo depois de um comando).
- Controle mostra só as ações que fazem sentido no estado do PC; números do
  desempenho com largura fixa; sem temperatura, o cartão da CPU mostra o
  tempo ligado.
- Dependências atualizadas (`golang.org/x/sys` v0.49.0, pacotes do app);
  `cupertino_icons` removido.

### Corrigido
- Volume no Windows não mudava (sobrecarga inteira de `Math.Min` e
  interfaces COM sem `PreserveSig`).
- Capa do álbum minúscula; painel de agendamento cortado em telas pequenas.
- "Nada tocando" piscando entre faixas; barra de progresso correndo durante
  a troca de faixa.

## [0.3.0] - 2026-10-25

### Adicionado
- Controle de mídia e volume do PC (SMTC + Core Audio no Windows, MPRIS no
  Linux) e aba Mídia no app; painel do PC em abas.
- Capa entregue só se for imagem e só de `file://` ou `https://`.

## [0.2.1] - 2026-10-25

### Adicionado
- Painel de desempenho no estilo do Caelestia (CPU, GPU, memória, disco).
- Temas Gruvbox e Catppuccin e escolha de modo claro/escuro.
- Assinatura de release e workflow de release a cada tag.

### Segurança
- O token mestre não aparece mais no log na primeira execução.

## [0.2.0]

- HTTPS com certificado fixado e credenciais por celular, revogáveis.
- Nome do celular sem a marca repetida ao parear.

## [0.1.0]

- Primeira versão: Wake-on-LAN, desligar e comandos pelo celular.

