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

## 3. Widget na tela inicial (Android)

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

## 5. Fechar a v0.4.0

- README: presença antes do login, agendamento, canal ao vivo, temas suaves,
  novo player, gráficos, atalho e widget; instalação no Windows e no Linux;
  modelo de segurança (TLS 1.3 fixado, credencial por celular, segredo de
  presença separado).
- CHANGELOG desde a 0.3.0 e versão 0.4.0 no agente e no `pubspec.yaml`.
- Verificação: testes (Go com `-race`, Flutter), `go vet`, `flutter analyze`,
  build de release do APK e dos agentes, revisão de segurança do que mudou.
- Nada é enviado nem publicado sem pedido explícito.

## Depois

- Publicação: keystore e segredos gerados pelo dono do projeto; push e tag
  só quando pedido.
- Repositório e CI.
- Assistente opcional (Gemini).

## Pendências manuais

- Reinstalar o agente no Windows (ativa o conserto do volume e, depois do
  item 1, a troca rápida).
- Instalar o agente no Linux.
