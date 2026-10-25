#!/bin/sh
# Instala o agente como serviço systemd do usuário (roda na sua sessão,
# então comandos gráficos e o desligamento via logind funcionam).
set -e
cd "$(dirname "$0")"
mkdir -p ~/.local/bin ~/.config/systemd/user
install -m 755 velksync-agent ~/.local/bin/velksync-agent
install -m 644 velksync-agent.service ~/.config/systemd/user/
[ -f ~/.config/velksync/config.json ] || ~/.local/bin/velksync-agent init ${1:+-token "$1"}
systemctl --user daemon-reload
systemctl --user enable --now velksync-agent
command -v ufw >/dev/null && sudo ufw allow 41100/tcp && sudo ufw allow 41101/udp || true
echo "Token: $(~/.local/bin/velksync-agent token)"
