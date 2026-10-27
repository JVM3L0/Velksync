# Velksync: convenções do projeto

## Git

- Trabalho direto na `main`, sem branch por entrega (só os PRs do Dependabot
  usam branch).
- Commits pequenos, no padrão Conventional Commits em português
  (`feat(agent): …`, `fix(app): …`).
- Nada de push, tag ou merge sem pedido explícito.

## Código

- Dart: `dart format -l 120`. Go: `gofmt`.
- Antes de mudar uma tela do app, propor com esboço e esperar aprovação.
