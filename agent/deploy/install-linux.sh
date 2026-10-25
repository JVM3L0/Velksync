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
# Sinal de presença: serviço de sistema que sobe no boot para o app saber que
# o PC ligou mesmo antes do login. Só recebe o segredo de presença.
sudo install -m 755 velksync-agent /usr/local/bin/velksync-agent
sudo install -d -m 700 /etc/velksync
tmp=$(mktemp)
~/.local/bin/velksync-agent presence-export -out "$tmp"
sudo install -m 600 -o root -g root "$tmp" /etc/velksync/presence.json
rm -f "$tmp"
sudo install -m 644 velksync-presence.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable velksync-presence
sudo systemctl restart velksync-presence
# Firewall: libera as portas só para a sub-rede local (ex.: 192.168.3.0/24).
LAN=$(ip -4 route show proto kernel scope link | awk '!/docker|br-|virbr/ {print $1; exit}')
if command -v ufw >/dev/null && [ -n "$LAN" ]; then
  sudo ufw allow from "$LAN" to any port 41100 proto tcp
  sudo ufw allow from "$LAN" to any port 41101 proto udp
fi
echo "Token mestre (use só para instalar no outro sistema do dual boot; não compartilhe):"
echo "  $(~/.local/bin/velksync-agent token)"
echo "Para parear um celular: velksync-agent pair"
