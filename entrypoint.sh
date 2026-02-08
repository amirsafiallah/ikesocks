#!/bin/bash
set -euo pipefail

# ---------------------------------------------------------------------------
# Validate required environment variables
# ---------------------------------------------------------------------------
required_vars=(VPN_SERVER_IP VPN_REMOTE_ID VPN_USERNAME VPN_PASSWORD SOCKS_USERNAME SOCKS_PASSWORD)
for var in "${required_vars[@]}"; do
    if [ -z "${!var:-}" ]; then
        echo "[ERROR] Required environment variable $var is not set." >&2
        exit 1
    fi
done

VPN_CRT_FILE="${VPN_CRT_FILE:-}"
SOCKS_PORT="${SOCKS_PORT:-1080}"

# ---------------------------------------------------------------------------
# Create system user for SOCKS5 authentication
# ---------------------------------------------------------------------------
adduser -D -H -s /sbin/nologin "$SOCKS_USERNAME" 2>/dev/null || true
echo "$SOCKS_USERNAME:$SOCKS_PASSWORD" | chpasswd 2>/dev/null

# ---------------------------------------------------------------------------
# Write strongSwan configuration
# ---------------------------------------------------------------------------
cat > /etc/swanctl/conf.d/ikesocks.conf <<EOF
connections {
    ikesocks {
        version = 2
        remote_addrs = ${VPN_SERVER_IP}
        vips = 0.0.0.0
        encap = yes
        fragmentation = yes
        proposals = aes256-sha256-modp2048,aes256-sha1-modp1024,aes128-sha256-modp2048,default

        local {
            auth = eap-mschapv2
            id = ${VPN_USERNAME}
            eap_id = ${VPN_USERNAME}
        }
        remote {
            auth = pubkey
            id = ${VPN_REMOTE_ID}
        }

        children {
            ikesocks-child {
                remote_ts = 0.0.0.0/0
                start_action = none
                dpd_action = restart
                close_action = restart
                esp_proposals = aes256-sha256,aes128-sha256,default
            }
        }
    }
}

secrets {
    eap-ikesocks {
        id = ${VPN_USERNAME}
        secret = "${VPN_PASSWORD}"
    }
}
EOF

# ---------------------------------------------------------------------------
# Install CA certificate if provided
# ---------------------------------------------------------------------------
if [ -n "$VPN_CRT_FILE" ]; then
    if [ ! -f "$VPN_CRT_FILE" ]; then
        echo "[ERROR] VPN_CRT_FILE set to '$VPN_CRT_FILE' but file not found." >&2
        exit 1
    fi
    cp "$VPN_CRT_FILE" /etc/swanctl/x509ca/
    echo "[INFO] Installed CA certificate from $VPN_CRT_FILE"
fi

# ---------------------------------------------------------------------------
# Prevent strongSwan from installing a default route via the tunnel
# ---------------------------------------------------------------------------
cat > /etc/strongswan.d/no-routes.conf <<EOF
charon {
    install_routes = no
}
EOF

# ---------------------------------------------------------------------------
# Start strongSwan (charon-systemd not available; use charon directly)
# ---------------------------------------------------------------------------
echo "[INFO] Starting strongSwan IKEv2 daemon..."
ipsec start
sleep 2

echo "[INFO] Loading connection profile..."
swanctl --load-all 2>&1 | while IFS= read -r line; do echo "[SWAN] $line"; done

echo "[INFO] Initiating IKEv2 connection to ${VPN_SERVER_IP} (remote-id: ${VPN_REMOTE_ID})..."
swanctl --initiate --child ikesocks-child --timeout 30 2>&1 | while IFS= read -r line; do echo "[SWAN] $line"; done
rc=${PIPESTATUS[0]}

if [ "$rc" -ne 0 ]; then
    echo "[ERROR] IKEv2 connection failed (exit code $rc). Check credentials and server." >&2
    swanctl --list-sas 2>&1 | while IFS= read -r line; do echo "[SWAN] $line"; done
    exit 1
fi

echo "[INFO] IKEv2 tunnel established."
swanctl --list-sas 2>&1 | while IFS= read -r line; do echo "[SWAN] $line"; done

# ---------------------------------------------------------------------------
# Detect the VPN virtual IP for Dante's external address
# ---------------------------------------------------------------------------
VPN_IP=$(swanctl --list-sas 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+' | head -1 | cut -d/ -f1 || true)
if [ -z "$VPN_IP" ]; then
    # Fallback: find the default interface IP
    VPN_IP=$(ip -4 route get 1.1.1.1 2>/dev/null | grep -oE 'src [0-9.]+' | cut -d' ' -f2 || true)
fi
if [ -z "$VPN_IP" ]; then
    echo "[ERROR] Could not determine VPN IP for SOCKS external address." >&2
    exit 1
fi
echo "[INFO] Virtual IP: $VPN_IP"

# ---------------------------------------------------------------------------
# Write Dante SOCKS5 configuration (after VPN is up so we know the external IP)
# ---------------------------------------------------------------------------
cat > /etc/sockd.conf <<EOF
logoutput: stderr

internal: 0.0.0.0 port = ${SOCKS_PORT}
external: ${VPN_IP}

socksmethod: username
clientmethod: none

user.privileged: root
user.unprivileged: nobody

client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect disconnect error
}

socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect disconnect error
}
EOF

# ---------------------------------------------------------------------------
# Graceful shutdown handler
# ---------------------------------------------------------------------------
cleanup() {
    echo "[INFO] Shutting down..."
    kill "$SOCKD_PID" 2>/dev/null || true
    wait "$SOCKD_PID" 2>/dev/null || true
    echo "[INFO] Stopping strongSwan (sending IKE DELETE)..."
    ipsec stop
    echo "[INFO] Shutdown complete."
    exit 0
}
trap cleanup SIGTERM SIGINT

# ---------------------------------------------------------------------------
# Start Dante SOCKS5 proxy
# ---------------------------------------------------------------------------
echo "[INFO] Starting SOCKS5 proxy on 0.0.0.0:${SOCKS_PORT} (external: ${VPN_IP})..."
sockd -f /etc/sockd.conf &
SOCKD_PID=$!
wait "$SOCKD_PID"
