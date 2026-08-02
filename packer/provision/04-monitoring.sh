#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# Layer 4: Monitoring (Optional)
# Installs Grafana Alloy for lightweight metrics/logs collection
# Disabled by default; enable via ENABLE_MONITORING=1

if [[ "${ENABLE_MONITORING:-0}" != "1" ]]; then
  echo "Monitoring layer disabled (set ENABLE_MONITORING=1 to enable)"
  exit 0
fi

# Detect architecture
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64)  ALLOY_ARCH="amd64" ;;
  aarch64) ALLOY_ARCH="arm64" ;;
  *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

# Install Grafana Alloy (lightweight, single binary)
ALLOY_VERSION="1.6.0"
ALLOY_URL="https://github.com/grafana/alloy/releases/download/v${ALLOY_VERSION}/alloy-${ALLOY_VERSION}-linux-${ALLOY_ARCH}.tar.gz"

echo "Installing Grafana Alloy ${ALLOY_VERSION} for ${ALLOY_ARCH}..."
curl -fsSL "${ALLOY_URL}" -o /tmp/alloy.tar.gz
tar -xzf /tmp/alloy.tar.gz -C /tmp
install -m 0755 /tmp/alloy-${ALLOY_VERSION}-linux-${ALLOY_ARCH}/alloy /usr/local/bin/alloy
rm -rf /tmp/alloy.tar.gz /tmp/alloy-${ALLOY_VERSION}-linux-${ALLOY_ARCH}

# Create Alloy config directory
mkdir -p /etc/alloy

# Alloy config (remote write to Grafana Prometheus + Loki)
cat > /etc/alloy/config.alloy <<'EOF'
// Grafana Alloy configuration for OCI Micro instance
// Sends metrics to Grafana Prometheus and logs to Loki

// Remote write to Grafana Prometheus
prometheus.remote_write "grafana" {
  endpoint {
    url = "https://" + env("GRAFANA_HOST") + "/api/prom/push"
    basic_auth {
      username = "alloy"
      password = env("ALLOY_PASSWORD")
    }
  }
}

// Self-scraping for node metrics
prometheus.scrape "self" {
  targets = [{__address__ = "localhost:9090"}]
  forward_to = [prometheus.remote_write.grafana.receiver]
}

// Node exporter metrics (if running)
prometheus.scrape "node_exporter" {
  targets = [{__address__ = "localhost:9100"}]
  forward_to = [prometheus.remote_write.grafana.receiver]
}

// Loki log forwarding
loki.source.file "system_logs" {
  targets = [{
    __path__ = "/var/log/**/*.log",
    job = "oci-micro",
    host = env("HOSTNAME"),
  }]
  forward_to = [loki.write.grafana.receiver]
}

loki.write "grafana" {
  endpoint {
    url = "https://" + env("GRAFANA_HOST") + "/loki/api/v1/push"
    basic_auth {
      username = "alloy"
      password = env("ALLOY_PASSWORD")
    }
  }
}
EOF

# Create systemd service for Alloy
# Secrets (GRAFANA_HOST, ALLOY_PASSWORD) are provided per-instance via
# /etc/alloy/alloy.env (EnvironmentFile) — never baked into the image.
cat > /etc/systemd/system/alloy.service <<'EOF'
[Unit]
Description=Grafana Alloy
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
EnvironmentFile=/etc/alloy/alloy.env
ExecStart=/usr/local/bin/alloy run --config.file=/etc/alloy/config.alloy --storage.path=/var/lib/alloy
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Create directory for Alloy storage
mkdir -p /var/lib/alloy

# Enable but don't start (requires GRAFANA_HOST and ALLOY_PASSWORD env vars)
systemctl enable alloy.service

echo "Alloy installed and enabled. Create /etc/alloy/alloy.env with GRAFANA_HOST and ALLOY_PASSWORD to start."
