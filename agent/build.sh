#!/bin/sh
# Compila o agente para os dois sistemas em dist/linux e dist/windows.
set -e
cd "$(dirname "$0")"
mkdir -p dist/linux dist/windows
GOOS=linux GOARCH=amd64 go build -trimpath -o dist/linux/velksync-agent .
GOOS=windows GOARCH=amd64 go build -trimpath -ldflags "-H=windowsgui" -o dist/windows/velksync-agent.exe .
cp deploy/install-linux.sh deploy/velksync-agent.service deploy/velksync-presence.service dist/linux/
cp deploy/install-windows.ps1 dist/windows/
echo "Pronto: agent/dist/"
