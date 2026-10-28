# Roadmap

O que falta até a v0.4.0 e o que fica para depois. Cada item tem o problema,
a mudança, os casos de uso e os testes. Mudanças de tela passam por uma
proposta antes de implementar.

Feito:
- Gráficos do desempenho (histórico de 2 min guardado na tela do PC, aberto
  ao tocar nos cartões de CPU, GPU e memória).
- Revisão de UI: energia conforme o estado do PC, comemoração ao ligar,
  números de largura fixa, cartão da CPU sem espaço vazio.
- Itens 1 (troca de faixa rápida no agente, limite de 3 canais) e 2 (cache
  de capas). O agente precisa ser reinstalado para o item 1 valer.

## 1. ~~Troca de faixa quase instantânea (agente)~~ feito

**Problema.** O canal ao vivo lê o player uma vez por segundo; depois de um
"próxima", a faixa nova pode levar até ~1 s para chegar ao app.

**Mudança.** `Live.Kick()` em `agent/live.go`, chamado pelos comandos de mídia
em `agent/media.go`: leituras extras em 150, 400, 800 e 1500 ms, enviando assim
que a faixa mudar, e depois volta ao ritmo normal. No máximo 4 leituras por
comando e só com alguém inscrito. Trocar a leitura periódica do ajudante do
Windows pelos eventos do SMTC fica para depois, se ainda faltar velocidade.

**Casos de uso.**
- Pular pelo app: faixa nova em ~0,2–0,5 s (hoje até ~1,2 s).
- Pular no teclado do PC ou fim da faixa: igual a hoje (até 1 s).
- Ninguém com a aba de mídia aberta: nenhuma leitura a mais.

**Testes.** Go (`-race`): `Kick` com inscrito publica antes do próximo tique;
sem inscrito não lê o player; vários `Kick` seguidos não abrem leituras em
paralelo. Manual: pular 10 vezes e cronometrar no Windows e no Linux.

**Junto:** subir `maxLivePerClient` de 2 para 3. O app agora mantém o canal
de desempenho aberto em todas as abas; com a mídia são dois, e trocar de aba
rápido pode esbarrar no limite enquanto o agente ainda fecha o canal antigo
(o app cai para consulta e volta em 15 s, sem quebrar).

## 2. ~~Cache de capas (app)~~ feito

**Mudança.** `app/lib/services/art_cache.dart`: as últimas 20 capas com
formato e cores já calculados, por `art_id`, só na memória. Usado em
`media_panel.dart` antes de pedir a capa ao PC.

**Casos de uso.** Próxima e depois anterior sem baixar de novo; playlist em
repetição instantânea a partir da segunda volta; muitas faixas descartam as
mais antigas (poucos MB no total).

**Testes.** Descarta a menos usada ao passar de 20; voltar a uma faixa não
pede a capa ao PC (o PC falso conta os pedidos); capa vazia ou inválida não
entra. Manual: próxima/anterior repetidos sem piscar a capa padrão.

## 3. ~~Widget na tela inicial (Android)~~ feito (com confirmação; desligar passa pelo app)

**Mudança.** `WakeWidgetProvider.kt` + layout, lendo as mesmas preferências do
atalho da Central de Controle (`flutter.devices`, `flutter.tile_device`).
Nome do PC, último estado que o app viu (ligado, desligado, aguardando
login), botão de ligar (Wake-on-LAN) e toque para abrir o app. O app grava o
último estado ao verificar o PC.

**Limite.** O widget não verifica o PC sozinho (bateria; a chave de presença
fica no armazenamento seguro).

**Casos de uso.** Ligar o PC sem abrir o app; mesmo PC escolhido para o
atalho; sem PC cadastrado mostra "Adicionar PC".

**Testes.** O formato gravado pelo app é o que o Kotlin lê (os dois lados);
widget sem dados não quebra. Manual: adicionar, ligar o PC por ele,
reiniciar o celular, trocar de PC.

**Segurança.** Só nome, MAC e estado. Nenhum token ou chave.

## 4. Controles na notificação e na tela de bloqueio (após a v0.4.0)

Sessão de mídia do Android com capa, título, pausar e pular. Decidir antes:

- **A (recomendada):** só com o app aberto ou minimizado há pouco; some após 5 min.
- **B:** sempre, com serviço em primeiro plano e conexão aberta (mais bateria).

## 5. ~~Fechar a v0.4.0~~ feito (falta só a tag, junto com a publicação)

- README: presença antes do login, agendamento, canal ao vivo, temas suaves,
  novo player, gráficos, atalho e widget; instalação no Windows e no Linux;
  modelo de segurança (TLS 1.3 fixado, credencial por celular, segredo de
  presença separado).
- CHANGELOG desde a 0.3.0 e versão 0.4.0 no agente e no `pubspec.yaml`.
- Verificação: testes (Go com `-race`, Flutter), `go vet`, `flutter analyze`,
  build de release do APK e dos agentes, revisão de segurança do que mudou.
- Nada é enviado nem publicado sem pedido explícito.

## 6. Plano 0.7.0 e 0.8.0

### v0.7.0: troca entre PC e celular
1. **Histórico de ações.** O agente guarda as últimas 200 em `history.json`
   (quando, quem, o quê, resultado): energia (pedida, cancelada no PC,
   agendada), comandos, terminal (só o comando, nunca a saída),
   pareamento, revogação, atualização e textos enviados. `GET /api/history`;
   o terminal só aparece com o terminal livre ligado. Ícone: "Histórico…"
   com as 15 últimas. App: cartão "Atividade recente" na aba Controle com
   as 3 últimas e "Ver tudo".
2. **Enviar para o celular pelo ícone.** Lê o texto copiado no PC e envia
   como link (`http(s)://`) ou texto, para um celular escolhido entre os
   conectados. Sem nenhum, o item fica desativado. Limite de 64 KB.
3. **Mandar texto do celular para o PC.** Menu Compartilhar do Android, só
   texto: link `http(s)` abre no navegador do PC, outro texto vai para a
   área de transferência. Aviso no ícone e registro no histórico. Nada de
   arquivos.
4. **Procurar atualização manualmente.** "Procurar atualizações agora" no
   menu do ícone e "Procurar agora" em Configurações do app, sem o limite
   diário.
5. Uma atualização por vez (já feito).

### v0.8.0: começo e visão do PC
1. **Primeira vez guiada** (só sem PC cadastrado, dá para pular): o que é,
   instalar o agente (copiar ou compartilhar o link), parear (QR ou busca)
   e "Teste: ligar" com dicas se não funcionar.
2. **Processos, só visualização.** Os 10 que mais usam CPU e memória, na
   aba Desempenho, lidos só com a seção aberta. Sem encerrar.

## Ideias guardadas

Levantadas em 25/10/2026, ainda sem decisão. Cada uma ganha plano, casos de
uso, testes e esboço antes de implementar.

| # | Ideia | Tamanho | Nota |
|---|---|---|---|
| 1 | Reiniciar direto no outro sistema ("Reiniciar no Windows/Linux") | médio | `grub-reboot` / `bcdedit /bootsequence`; só na próxima inicialização |
| 2 | ~~Mandar do celular para o PC~~ | | na v0.7.0, só texto (ver item 6); arquivos ficam para depois |
| 3 | Controles de mídia na notificação e na tela de bloqueio | grande | ver item 4 acima |
| 4 | Ligar o PC num horário (dias da semana ou uma vez) | pequeno/médio | Wake-on-LAN agendado no celular (AlarmManager); adiado na decisão de 28/10/2026 |
| 5 | Atalhos no ícone do app, condicionais: "Ligar" com o PC desligado, "Desligar"/"Reiniciar" ligado (último estado visto pelo app, como o widget) | pequeno | um por PC (até ~4); desatualizado só mostra a opção errada: ligar é inofensivo e desligar confere o estado real e confirma; assistentes costumam abrir atalhos, ponte até o 12 |
| 6 | Exportar/importar os PCs em backup criptografado | médio | evita parear de novo ao trocar de celular |
| 7 | Touchpad e teclado remotos | grande | |
| 8 | Instalar e testar o agente no Linux do dual boot | pequeno | com o dono do projeto |
| 9 | Acesso fora de casa com Tailscale | médio | mais configuração e docs que código |
| 10 | Avisos do PC com o app fechado | grande | custo de bateria ou privacidade |
| 11 | ~~Primeira vez guiada~~ | | na v0.8.0 (ver item 6) |
| 12 | Ligar e desligar pelo Gemini ("liga o Velkhyro"), via AppFunctions | pequeno | depende do Google liberar a integração (em teste fechado em maio/2026); ligar sem confirmação, desligar pede confirmação no app |
| 13 | Assinar o instalador do Windows pela SignPath Foundation (grátis para código aberto) | pequeno | tira o aviso do SmartScreen; exige inscrição e revisão do projeto por eles |
| 14 | Pacote `.deb`/`.rpm` e `velksync-agent setup` guiado no Linux | médio | o `doctor` ganha a parte do Linux (`ethtool`, NetworkManager) |


## Feito fora do plano

- Publicação da v0.4.0, CI a cada envio, Dependabot, APK por processador,
  app de desenvolvimento separado e aviso de versão.
- Instalador do Windows com `doctor` do Wake-on-LAN (a caminho da 0.5.0).

## Pendências manuais

- Reinstalar o agente no Windows (ativa o conserto do volume e, depois do
  item 1, a troca rápida).
- Instalar o agente no Linux.
