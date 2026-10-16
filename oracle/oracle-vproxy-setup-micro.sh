#!/usr/bin/env bash
# Sets up Nokoding/vproxy as an always-on proxy on an Oracle Cloud Ubuntu VM.
# Micro (x86_64) version: installs a prebuilt binary instead of compiling.
# Run it on the VM as your normal login user (ubuntu), not root.
# Uses sudo where it needs to. Safe to run again: it rebuilds and restarts.
#
# What you get: the plain HTTP proxy on 8080 (with username and password)
# and your .pac file on 8090. No bore tunnel needed, the VM has a real
# public IP. Systemd restarts both on a crash and after a reboot.

set -euo pipefail

HTTP_PORT="${HTTP_PORT:-8080}"
PAC_PORT="${PAC_PORT:-8090}"

if [ "$(id -u)" -eq 0 ]; then
  echo "Run this as your normal user, not root. It calls sudo itself."
  exit 1
fi

# ---------- 1. Proxy login ----------
echo "Pick a username and password for the proxy. Devices will have to use them."
read -r -p "Proxy username: " PROXY_USERNAME
read -r -s -p "Proxy password: " PROXY_PASSWORD
echo
if [ -z "$PROXY_USERNAME" ] || [ -z "$PROXY_PASSWORD" ]; then
  echo "Both username and password are required."
  exit 1
fi
# Same characters your repo's configure-proxy rejects, plus whitespace and %.
case "$PROXY_USERNAME$PROXY_PASSWORD" in
  *[[:space:]\"\`\$\\{}%]*)
    echo 'Username and password can not contain spaces or any of: " ` $ \ { } %'
    exit 1
    ;;
esac

# ---------- 2. Packages ----------
echo "Installing packages..."
sudo apt-get update -y
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | sudo debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | sudo debconf-set-selections
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  curl ca-certificates python3 iptables-persistent

# ---------- 3. Get the prebuilt binary ----------
# The 1 GB Micro can not compile vproxy, so this uses a binary built elsewhere.
# Give it either a local file or a URL (a .gz of the vproxy executable):
#   VPROXY_BIN=./vproxy-linux-x86_64.gz bash oracle-vproxy-setup-micro.sh
#   VPROXY_BIN=https://github.com/.../vproxy-linux-x86_64.gz bash oracle-vproxy-setup-micro.sh
if [ "$(uname -m)" != "x86_64" ]; then
  echo "This script is for the x86_64 Micro. This machine is $(uname -m). Use oracle-vproxy-setup.sh instead."
  exit 1
fi
if [ -z "${VPROXY_BIN:-}" ]; then
  echo "Set VPROXY_BIN to the .gz file or URL. See the comment in this script."
  exit 1
fi
WORK="$(mktemp -d)"
case "$VPROXY_BIN" in
  http://*|https://*) curl -fL --retry 3 -o "$WORK/vproxy.gz" "$VPROXY_BIN" ;;
  *) cp "$VPROXY_BIN" "$WORK/vproxy.gz" ;;
esac
gunzip -c "$WORK/vproxy.gz" > "$WORK/vproxy"
chmod +x "$WORK/vproxy"
"$WORK/vproxy" --version >/dev/null || { echo "The binary does not run on this machine."; exit 1; }

# pac-server.py comes from your repo
curl -fsSL "https://raw.githubusercontent.com/Nokoding/vproxy/main/.devcontainer/pac-server.py" -o "$WORK/pac-server.py"

# ---------- 5. Install files ----------
sudo id vproxy >/dev/null 2>&1 || sudo useradd --system --no-create-home --shell /usr/sbin/nologin vproxy
sudo install -m 755 "$WORK/vproxy" /usr/local/bin/vproxy
sudo install -d -m 755 /usr/local/lib/vproxy /var/lib/vproxy
sudo install -m 755 "$WORK/pac-server.py" /usr/local/lib/vproxy/pac-server.py

sudo install -d -m 755 /etc/vproxy
printf 'PROXY_USERNAME=%s\nPROXY_PASSWORD=%s\n' "$PROXY_USERNAME" "$PROXY_PASSWORD" \
  | sudo tee /etc/vproxy/env >/dev/null
sudo chmod 600 /etc/vproxy/env
sudo chown root:root /etc/vproxy/env

# ---------- 6. PAC file ----------
if [ -z "${PUBLIC_IP:-}" ]; then
  PUBLIC_IP="$(curl -fsS -m 10 https://api.ipify.org || curl -fsS -m 10 https://ifconfig.me || true)"
fi
if [ -z "$PUBLIC_IP" ]; then
  echo "Could not detect the public IP. Re-run with: PUBLIC_IP=1.2.3.4 ./oracle-vproxy-setup.sh"
  exit 1
fi
printf 'function FindProxyForURL(url, host) {\n  return "PROXY %s:%s";\n}\n' "$PUBLIC_IP" "$HTTP_PORT" \
  | sudo tee /var/lib/vproxy/proxy.pac >/dev/null
sudo chmod 644 /var/lib/vproxy/proxy.pac

# ---------- 7. systemd services ----------
sudo tee /etc/systemd/system/vproxy.service >/dev/null <<EOF
[Unit]
Description=vproxy HTTP proxy
After=network-online.target
Wants=network-online.target

[Service]
User=vproxy
EnvironmentFile=/etc/vproxy/env
ExecStart=/usr/local/bin/vproxy run --bind 0.0.0.0:${HTTP_PORT} http --username \${PROXY_USERNAME} --password \${PROXY_PASSWORD}
Restart=always
RestartSec=3
LimitNOFILE=65535
NoNewPrivileges=yes

[Install]
WantedBy=multi-user.target
EOF

sudo tee /etc/systemd/system/vproxy-pac.service >/dev/null <<EOF
[Unit]
Description=vproxy PAC file server
After=network-online.target
Wants=network-online.target

[Service]
User=vproxy
ExecStart=/usr/bin/python3 /usr/local/lib/vproxy/pac-server.py ${PAC_PORT} /var/lib/vproxy/proxy.pac
Restart=always
RestartSec=3
NoNewPrivileges=yes

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable vproxy.service vproxy-pac.service
sudo systemctl restart vproxy.service vproxy-pac.service

# ---------- 8. VM firewall ----------
# Oracle's Ubuntu images block everything except SSH in iptables.
# This opens the two ports inside the VM. You still have to open them in the
# Oracle console too (VCN security list), see the notes printed below.
for p in "$HTTP_PORT" "$PAC_PORT"; do
  sudo iptables -C INPUT -p tcp --dport "$p" -j ACCEPT 2>/dev/null \
    || sudo iptables -I INPUT 1 -p tcp --dport "$p" -j ACCEPT
done
sudo netfilter-persistent save >/dev/null

# ---------- 9. Self-test from inside the VM ----------
sleep 3
echo
echo "Self-test (from inside the VM):"
code_noauth="$(curl -s -m 15 -o /dev/null -w '%{http_code}' -x "http://127.0.0.1:${HTTP_PORT}" https://example.com || true)"
code_auth="$(curl -s -m 20 -o /dev/null -w '%{http_code}' -x "http://127.0.0.1:${HTTP_PORT}" --proxy-user "${PROXY_USERNAME}:${PROXY_PASSWORD}" https://example.com || true)"
code_pac="$(curl -s -m 10 -o /dev/null -w '%{http_code}' "http://127.0.0.1:${PAC_PORT}/proxy.pac" || true)"
echo "  without login: ${code_noauth}   (407 means auth is working)"
echo "  with login:    ${code_auth}   (200 means the proxy works)"
echo "  PAC file:      ${code_pac}   (200 means it is served)"

cat <<EOF

Done. Proxy address for your devices:
  Regular proxy: ${PUBLIC_IP}  port ${HTTP_PORT}  (username and password you just set)
  Auto-config:   http://${PUBLIC_IP}:${PAC_PORT}/proxy.pac

Still to do in the Oracle console, or devices can not connect:
  Networking > Virtual cloud networks > your VCN > Security Lists > Default
  > Add ingress rules: source 0.0.0.0/0, TCP, destination ports ${HTTP_PORT} and ${PAC_PORT}.

Logs:   sudo journalctl -u vproxy -u vproxy-pac -f
Status: systemctl status vproxy vproxy-pac
EOF
