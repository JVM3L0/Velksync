#!/bin/sh
# Compila e testa o app num container podman. O projeto entra só para leitura e
# é copiado lá dentro; o APK de depuração sai em app/build/podman/.
#
#   tools/android/build.sh --accept-android-licenses   # na primeira vez
#   tools/android/build.sh
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
image=velksync-android

if [ "${1:-}" = --accept-android-licenses ] || ! podman image exists "$image"; then
  accept=no
  [ "${1:-}" = --accept-android-licenses ] && accept=yes
  podman build --build-arg ACCEPT_ANDROID_LICENSES="$accept" -t "$image" "$root/tools/android"
fi

out="$root/app/build/podman"
mkdir -p "$out"
podman run --rm \
  -v "$root/app:/src:ro" \
  -v "$out:/out" \
  -v velksync-gradle:/root/.gradle \
  -v velksync-pub:/root/.pub-cache \
  "$image" sh -euc '
    mkdir /work
    cd /src
    # Sem o que é da máquina (local.properties, chaves) nem saídas de build.
    tar -cf - --exclude=./build --exclude=./.dart_tool --exclude=./android/.gradle \
      --exclude=./android/local.properties --exclude=./android/key.properties --exclude="*.jks" . |
      tar -xf - -C /work
    cd /work
    # O gradle.properties do projeto é contido por causa do WSL; este, do
    # usuário do container, vale por cima: 14 workers (sobram 2 threads para o resto do PC) e mais memória.
    printf "org.gradle.workers.max=14\norg.gradle.jvmargs=-Xmx4G -XX:MaxMetaspaceSize=1G\n" > /root/.gradle/gradle.properties
    flutter pub get
    dart format -l 120 --set-exit-if-changed --output=none lib test
    flutter analyze
    flutter test
    flutter build apk --debug
    (cd android && ./gradlew --no-daemon :app:testDebugUnitTest)
    cp build/app/outputs/flutter-apk/app-debug.apk /out/
  '
echo "APK: $out/app-debug.apk"
