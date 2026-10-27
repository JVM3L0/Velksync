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

## Versão

Ao trocar a versão, mudar junto: `agent/main.go`, `app/pubspec.yaml`,
`agent/winres/winres.json` (todas as ocorrências) e regenerar o
`agent/rsrc_windows_amd64.syso` (o usuário roda o go-winres:
`go run github.com/tc-hib/go-winres@v0.3.3 make --in winres/winres.json --arch amd64`
dentro de `agent/`). A release confere os três números contra a tag.
