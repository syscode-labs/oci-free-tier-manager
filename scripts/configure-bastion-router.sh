#!/usr/bin/env bash
# Source-managed, in-place bastion rollout; preserves SSH and VM identity.
# Optional second argument is an auth-key file; never log its contents.
set -euo pipefail
[ "$(id -u)" -eq 0 ]
route=${1:?subnet CIDR required}
key_file=${2:-}
activate=${3:-false}
case "$activate" in true|false) ;; *) exit 2 ;; esac
routes=""
if [ "$activate" = true ]; then routes=$route; fi
python3 -c 'import ipaddress,sys; ipaddress.IPv4Network(sys.argv[1])' "$route"

if ! command -v tailscale >/dev/null; then
  curl --retry 3 --retry-delay 2 -fsSL https://pkgs.tailscale.com/stable/ubuntu/noble.noarmor.gpg -o /usr/share/keyrings/tailscale-archive-keyring.gpg
  printf '%s\n' 'deb [signed-by=/usr/share/keyrings/tailscale-archive-keyring.gpg] https://pkgs.tailscale.com/stable/ubuntu noble main' > /etc/apt/sources.list.d/tailscale.list
  chmod 0644 /usr/share/keyrings/tailscale-archive-keyring.gpg /etc/apt/sources.list.d/tailscale.list
  apt-get update -qq
  apt-get install -y tailscale
fi
printf '%s\n' 'net.ipv4.ip_forward = 1' 'net.ipv6.conf.all.forwarding = 1' > /etc/sysctl.d/99-tailscale-router.conf
sysctl -p /etc/sysctl.d/99-tailscale-router.conf
ufw allow 41641/udp
systemctl enable --now tailscaled
if tailscale status --json | python3 -c 'import json,sys; sys.exit(json.load(sys.stdin).get("BackendState") != "Running")'; then
  tailscale set --advertise-routes="$routes" --accept-dns=false
else
  if [ -z "$key_file" ]; then
    key_file=$(mktemp)
    chmod 600 "$key_file"
    trap 'rm -f "$key_file"' EXIT
    curl --fail --silent --show-error -H 'Authorization: Bearer Oracle' http://169.254.169.254/opc/v2/instance/metadata/tailscale_auth_key > "$key_file"
  fi
  tailscale up --auth-key="file:$key_file" --hostname=oci-bastion-01 --advertise-routes="$routes" --accept-dns=false --accept-routes=false --timeout=60s
fi
# tailscaled persists its identity and preferences in /var/lib/tailscale.
