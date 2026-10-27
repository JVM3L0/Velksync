# Velksync: convenções do projeto

## Git

- Branch por entrega, com a versão que ela vai gerar: `<tipo>/<versão>-<assunto>`,
  por exemplo `feat/0.5.0-instalador-windows` ou `fix/0.4.2-volume`. O tipo é o
  mesmo dos commits (`feat`, `fix`, `docs`, `chore`…). Sem o `v` na frente: a
  tag `v0.5.0` e uma branch `v0.5.0` teriam o mesmo nome.
- Commits pequenos, no padrão Conventional Commits em português
  (`feat(agent): …`, `fix(app): …`).
- Nada de push, tag ou merge sem pedido explícito.

## Código

- Dart: `dart format -l 120`. Go: `gofmt`.
- Antes de mudar uma tela do app, propor com esboço e esperar aprovação.
