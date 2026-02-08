# ikesocks

SOCKS5 proxy over IKEv2/IPsec. Runs as a Docker container using strongSwan and Dante — all proxied traffic exits through the VPN tunnel while the host network stays unaffected.

## Quick start

1. Place your VPN provider's CA certificate at `./certs/ca.crt`.

2. Create a `.env` file:

```
VPN_SERVER_IP=203.0.113.1
VPN_REMOTE_ID=vpn.example.com
VPN_USERNAME=alice
VPN_PASSWORD=secret
SOCKS_USERNAME=proxy
SOCKS_PASSWORD=changeme
```

3. Run:

```bash
docker compose up -d
```

4. Use the proxy:

```bash
curl -x socks5://proxy:changeme@127.0.0.1:1080 https://ifconfig.me
```

## Environment variables

| Variable | Required | Description |
|---|---|---|
| `VPN_SERVER_IP` | yes | IKEv2 server IP address |
| `VPN_REMOTE_ID` | yes | Server identity (typically FQDN) |
| `VPN_USERNAME` | yes | EAP username |
| `VPN_PASSWORD` | yes | EAP password |
| `SOCKS_USERNAME` | yes | SOCKS5 proxy username |
| `SOCKS_PASSWORD` | yes | SOCKS5 proxy password |
| `SOCKS_PORT` | no | SOCKS5 listen port (default: `1080`) |
| `VPN_CRT_FILE` | no | CA certificate path inside container (default: `/certs/ca.crt`) |

## How it works

- **strongSwan** establishes an IKEv2 tunnel with EAP-MSCHAPv2 authentication
- **Dante** runs an authenticated SOCKS5 proxy (configurable port, default 1080), binding its external interface to the VPN virtual IP
- Only SOCKS proxy traffic goes through the tunnel — host routing is not modified (`install_routes = no`, `start_action = none`)
- Auto-reconnects on VPN disconnect (`dpd_action = restart`, `close_action = restart`)
- Graceful shutdown sends IKE DELETE and cleans up kernel XFRM state

## Requirements

The container needs `NET_ADMIN` capability and `/dev/net/tun`. It uses `network_mode: host`. It does **not** need `--privileged`.
