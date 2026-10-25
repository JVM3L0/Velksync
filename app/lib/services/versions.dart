/// Versão do app, vinda do build (`version:` do pubspec). Vazia em testes.
const appVersion = String.fromEnvironment('FLUTTER_BUILD_NAME');

/// Página de versões publicadas (APK e agentes).
const releasesUrl = 'https://github.com/JVM3L0/Velksync/releases/latest';

/// Quem está atrás quando app e agente diferem em major ou minor.
enum VersionGap { none, agentOld, appOld }

/// "0.4.1" → (0, 4); aceita sufixos como "0.4.1+5" ou "v0.4.1". Inválida → null.
(int, int)? _majorMinor(String? v) {
  final m = RegExp(r'^v?(\d+)\.(\d+)').firstMatch(v?.trim() ?? '');
  return m == null ? null : (int.parse(m.group(1)!), int.parse(m.group(2)!));
}

/// Só major e minor contam: as duas pontas saem juntas a cada versão e uma
/// correção (patch) de um lado não exige atualizar o outro. Agente que não
/// informa versão é anterior à 0.2 e conta como desatualizado.
VersionGap versionGap({required String? agent, String app = appVersion}) {
  final a = _majorMinor(app);
  if (a == null) return VersionGap.none; // build sem versão (testes, dev sem pubspec)
  final g = _majorMinor(agent);
  if (g == null) return VersionGap.agentOld;
  final cmp = g.$1 != a.$1 ? g.$1.compareTo(a.$1) : g.$2.compareTo(a.$2);
  return cmp < 0
      ? VersionGap.agentOld
      : cmp > 0
      ? VersionGap.appOld
      : VersionGap.none;
}
