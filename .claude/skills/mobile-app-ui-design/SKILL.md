---
name: mobile-app-ui-design
description: Desenhar, revisar ou melhorar telas, fluxos e componentes do app Flutter do Velksync (Material 3 Expressive). Use ao criar ou mudar uma tela, propor um layout, revisar a UI/UX do app ou quando o usuário pedir para deixar uma tela melhor. Não use para o agente Go, para scripts ou para páginas web.
---

# UI/UX do app Velksync

Adaptada de [ceorkm/mobile-app-ui-design](https://github.com/ceorkm/mobile-app-ui-design)
(MIT, commit 4c67a0e) para este projeto: Flutter + Material 3 Expressive, no
lugar de React/Tailwind. Mantém os princípios gerais; troca as regras que
brigam com o M3 pelas do próprio app.

## Como trabalhar aqui

1. **Proponha antes de mudar a tela.** Esboço em ASCII (ou opções com
   prévia no AskUserQuestion), com o que muda e por quê. Só implemente
   depois da aprovação. Correções de bug sem mudança visual não precisam.
2. **Veja a tela real.** Print no celular (`adb exec-out screencap -p`) antes
   e depois; nunca toque às cegas: print antes de cada toque.
3. **Teste o que mudou** (ver "Testes" abaixo) e confira no aparelho.

## Antes de desenhar

- Qual é a ação principal desta tela? Ela deve ser a primeira coisa vista e
  ficar ao alcance do polegar (terço de baixo), salvo ações destrutivas.
- Em que estado o PC está? (desligado, ligando, aguardando login, ligado,
  falhou) Mostre só as ações que fazem sentido nesse estado; não deixe
  botões desativados ocupando espaço nobre.
- Qual o momento marcante do fluxo e qual a última impressão? (regra do
  pico e do fim, abaixo)

## Princípios mantidos da skill original

**Estrutura (UX)**
- Exponha o conteúdo em vez de escondê-lo atrás de toques extras, mas sem
  custo escondido (mais consultas ao PC, bateria); pese os dois.
- Estados vazios, de erro, de carregamento e de sucesso sempre desenhados,
  com orientação e uma ação ("Nada tocando · Dê play em algo no PC").
- Seleção em vez de digitação para opções comuns; campo livre como reserva.
- Sliders para ajustes contínuos (volume, posição); campos para valores exatos.

**Hierarquia (UI)**
- O valor é maior que o rótulo ("23%" maior que "CPU").
- Números que mudam ao vivo com algarismos de largura fixa
  (`FontFeature.tabularFigures()`), para não tremer.
- Hierarquia por tamanho, peso e cor de apoio (`onSurfaceVariant`), não
  por negrito em tudo.
- Espaços relacionados mais próximos; grupos diferentes com o dobro.
- Cores fortes (erro) só para o que importa: desligar, falha.

**Emoção (pico e fim)**
- O pico do app é **o PC ligar**; outros: pular de faixa, agendamento feito.
- Reforce o pico com vibração (`HapticFeedback`), animação curta e texto
  humano ("Velkhyro ligou em 38 s"). Proporcional: nada de confete.
- Falhas com tom gentil e ajuda prática (ver `showWakeHelp`).
- Espera vira informação: tempo decorrido, próximo passo.

**Acabamento**
- Áreas de toque de no mínimo 48 dp (M3).
- Contraste AA em todos os temas.
- Movimento comunica mudança de estado; respeite "remover animações"
  (`MediaQuery.disableAnimationsOf`).

## O que NÃO usar (da original, brigam com o projeto)

- Vidro fosco / `backdrop-blur`, emojis na interface, brilhos e sombras
  decorativas (o M3 usa cor tonal e elevação, não sombra).
- Limite de "4 tamanhos de fonte": use a escala do `TextTheme` do M3.
- Espaços de seção de 80–96 px e larguras de site.
- React, Tailwind, Lucide, Recharts.

## Implementação no Flutter

- **Pacotes:** `material_ui` (Material), `material_symbols_icons`
  (`Symbols.*_rounded`, com `fill: 1` para o estado ativo), sem bibliotecas
  de gráfico (gráficos com `CustomPainter`, ver `lib/ui/stats_chart.dart`).
- **Tokens (`lib/ui/theme.dart`):** cantos em `Radii` (xs 4 … xxl 48);
  movimento em `Motion` (`spatial`/`spatialFast` com mola para posição e
  tamanho, `effects` para cor e opacidade; durações 500/350/200 ms).
- **Espaçamento:** múltiplos de 4 (4, 8, 12, 16, 24, 32); cartões com 16 de
  padding, laterais de tela 16–24.
- **Cores:** sempre do `ColorScheme` (nunca hex na tela). Paletas em
  `lib/ui/palettes.dart`; `readable()` garante AA. Containers tonais
  (`primaryContainer`, `secondaryContainer`, `surfaceContainer*`) em vez de
  sombra.
- **Componentes do app (`lib/ui/widgets.dart`):** `StatusPill`, `IconBadge`,
  `SectionLabel`, `ExpressiveGroup`/`GroupTile`, `MorphTile`. Reaproveite
  antes de criar outro.
- **Transições (`lib/ui/transitions.dart`):** `ContainerTransformRoute`
  (cartão → tela), `SharedAxisSwitcher` (abas e troca de conteúdo).
- **Folhas:** `showModalBottomSheet` com `showDragHandle: true`,
  `isScrollControlled: true` e conteúdo rolável (não estoura em fonte grande).
- **Callbacks de animação** (`onEnd` etc.) que chamam `setState`: adie para
  depois do quadro (`addPostFrameCallback`).

## Testes

- Widget test no tamanho do celular (1220×2712, dpr 3) e em tela pequena
  com fonte 2×: sem overflow (`tester.takeException()` nulo).
- `ListView` monta sob demanda: use `scrollUntilVisible` ou tela grande.
- Contraste AA das paletas (`test/palettes_test.dart`) quando mexer em cor.
- Interações: o efeito chega ao PC (cliente falso, como `FakePc` em
  `test/media_panel_test.dart`).

## Referência

`references/industry-conventions.md` (da original). Para o Velksync valem
as seções **Productivity** (limpo, denso e organizado, ações rápidas),
**AI/Tech** só no tom de movimento suave, **Peak-End Rule** e **Emotional
Feedback Loops**. As demais indústrias servem só de contraste.
