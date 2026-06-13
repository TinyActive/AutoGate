# AutoGate

AutoGate is a Docker-based **rotating proxy gateway** that aggregates multiple outbound paths—VPN (OpenVPN via VPNGate), Cloudflare WARP, Psiphon, and public HTTP/HTTPS proxies—and exposes them through a single HAProxy entry point with automatic rotation.

It is intended for **authorized security research, penetration testing, security product evaluation, SEO tooling validation, deployment testing, and controlled system access** in environments where you have explicit permission to test.

> **Important:** Use AutoGate only on systems and networks you own or are explicitly authorized to test. Unauthorized access is illegal.

---

## Features

- **Rotating proxy pool** — HAProxy round-robin across 20+ OpenVPN-backed tinyproxy instances, WARP, Psiphon, and ProxyBroker2
- **Psiphon egress** — Censorship-circumvention tunnel exposing a local HTTP/SOCKS proxy as an additional egress path
- **Automatic VPN config refresh** — Downloads OpenVPN profiles from [VPNGate](http://www.vpngate.net/) on a schedule
- **Connection rotation** — Watchdog reconnects VPN and proxy per container on a configurable interval (`ROTATING_DELAY`)
- **Multiple egress paths** — Combine VPN, WARP, and scraped public proxies for diverse IP/geo testing
- **Stats dashboard** — HAProxy stats UI for backend health monitoring
- **Containerized** — Single `docker-compose` stack, reproducible deployments

---

## Use Cases

| Area | How AutoGate helps |
|------|-------------------|
| **Penetration testing** | Route traffic through varied egress IPs to test geo/IP-based controls, rate limits, and WAF rules |
| **Security solution testing** | Validate SIEM, firewall, proxy, and DLP behavior against rotating outbound sources |
| **SEO & web tooling** | Test crawlers, rank checkers, and geo-targeted content from different network perspectives (with permission) |
| **Deployments & access** | Smoke-test applications behind proxies, verify remote access paths, and validate multi-region behavior |

---

## Architecture

```
                    ┌─────────────────────────────────────┐
                    │           HAProxy (haproxy)          │
                    │  :9999  rotating HTTP proxy (frontend)│
                    │  :10000 stats UI                     │
                    └──────────────┬──────────────────────┘
                                   │ round-robin
    ┌────────────────────┬────────────┼────────────┬─────────────────────┐
    ▼                    ▼            ▼            ▼                     ▼
┌───────────┐    ┌────────────┐ ┌───────────┐ ┌────────────┐    ┌──────────────┐
│   WARP    │    │ ProxyBroker│ │  Psiphon  │ │  (future)  │    │ ovpn_proxy   │
│  :1080    │    │  proxy001  │ │ psiphon001│ │            │    │ 00 … 19      │
└───────────┘    │  :8888     │ │  :8080    │ └────────────┘    │ OpenVPN +    │
                 └────────────┘ └───────────┘                   │ tinyproxy    │
                                                                │ :8080 each   │
                                                                └──────┬───────┘
                                                                       │
                                vpngate.py (master) ──► /ovpn/*.ovpn ◄─┘
                                (refreshes configs every 30 min)
```

### Components

| Service | Role |
|---------|------|
| `haproxy` | Front door; balances traffic across all backends |
| `warp` | Cloudflare WARP SOCKS proxy |
| `proxy001` | ProxyBroker2 — discovers and serves high-anonymity HTTP/HTTPS proxies |
| `psiphon001` | Psiphon ConsoleClient — circumvention tunnel exposing a local HTTP proxy (`:8080`) / SOCKS proxy (`:1080`) |
| `ovpn_proxy_00` … `ovpn_proxy_19` | OpenVPN client + tinyproxy; rotates VPN endpoint on watchdog schedule |
| `restarter` | Periodically restarts `proxy001` to refresh the proxy pool |

---

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) and [Docker Compose](https://docs.docker.com/compose/install/)
- Linux host with `/dev/net/tun` available (required for OpenVPN)
- Sufficient RAM/CPU for ~25 containers (adjust replica count in `docker-compose.yml` if needed)
- **Legal authorization** for all testing activities

---

## Quick Start

1. Clone the repository:

   ```bash
   git clone https://github.com/TinyActive/AutoGate
   cd AutoGate
   ```

2. Create the shared OpenVPN config directory:

   ```bash
   mkdir -p ovpn data psiphon_data
   ```

3. Build and start the stack:

   ```bash
   docker-compose up --build --force-recreate -d
   ```

4. Wait for VPN configs to download (first run may take ~30 seconds before `ovpn/` is populated).

5. Use the rotating proxy:

   ```bash
   curl -x http://127.0.0.1:56789 http://ifconfig.me
   ```

---

## Ports (default host mapping)

| Host port | Container | Description |
|-----------|-----------|-------------|
| `56789` | `haproxy:9999` | Rotating HTTP proxy (use with `-x http://host:56789`) |
| `2086` | `haproxy:10000` | HAProxy stats UI (`http://host:2086/`) |

Internal services use the `172.21.0.0/24` custom network defined in `docker-compose.yml`.

---

## Configuration

### VPN rotation interval

Set `ROTATING_DELAY` (seconds) on ovpn slave containers via `Dockerfile` / compose `environment`:

```dockerfile
ENV ROTATING_DELAY=60
```

The watchdog kills and reconnects OpenVPN + tinyproxy on this interval.

### VPN config refresh

`proxy/vpngate.py` fetches VPNGate CSV data and writes `.ovpn` files to `./ovpn`. It runs every **30 minutes** from `proxy/run.sh`.

### Scale VPN workers

Duplicate or remove `ovpn_proxy_XX` service blocks in `docker-compose.yml` and add matching `server vpnXX` entries in `proxy/haproxy.cfg`.

### Cloudflare WARP

Optional `WARP_LICENSE_KEY` can be set on the `warp` service. See [caomingjun/warp](https://hub.docker.com/r/caomingjun/warp) for details.

### Psiphon

The `psiphon001` service builds the [Psiphon ConsoleClient](https://github.com/Psiphon-Labs/psiphon-tunnel-core) from source (`PsiphonDockerfile`) and runs it with the public Psiphon network config in `psiphon/psiphon.config`. It establishes a tunnel and exposes a local HTTP proxy on `:8080` (and SOCKS on `:1080`) that HAProxy chains to like any other backend.

Tunable via `environment` on the service (all optional):

| Variable | Description | Default |
|----------|-------------|---------|
| `EGRESS_REGION` | Pin egress country (e.g. `SG`, `JP`, `US`); empty = fastest/any | empty |
| `DEVICE_REGION` | Client device region hint | empty |
| `HTTP_PORT` | Local HTTP proxy port | `8080` |
| `SOCKS_PORT` | Local SOCKS proxy port | `1080` |
| `CONFIG_URL` | Auto-fetch a fresh config from this URL; empty = always use bundled standard config | empty |
| `CONFIG_REFRESH_INTERVAL` | Seconds between config re-checks when `CONFIG_URL` is set (`0` = off) | `21600` |
| `HEALTHCHECK_URL` | URL the healthcheck fetches *through* the proxy to prove egress | `https://www.google.com/generate_204` |

Build a specific Psiphon version by overriding the `PSIPHON_VERSION` build arg in `PsiphonDockerfile`. Tunnel state persists in `./psiphon_data`.

#### Self-healing / auto-updating config

`psiphon/psiphon.config` is the bundled, read-only **standard** config. The runtime config the client actually uses is **rebuilt from a validated source on every start**, so:

- **Auto-revert to standard** — if the runtime config in `./psiphon_data` is manually edited or corrupted, it is regenerated from the bundled standard config on the next (re)start. No manual cleanup needed.
- **Auto-fetch newer config** — set `CONFIG_URL` to a JSON config endpoint. On start (and every `CONFIG_REFRESH_INTERVAL` seconds) the client downloads it, validates it's well-formed JSON with the required keys (`PropagationChannelId`, `SponsorId`, `RemoteServerListSignaturePublicKey`), and uses it. Any failure (unreachable, bad JSON, missing keys) **falls back to the bundled standard config**. When a newer config is detected, Psiphon is restarted (`restart: always`) to apply it.
- **Note:** Psiphon already refreshes its *server list* automatically at runtime via the remote/obfuscated server-list URLs embedded in the config — so day-to-day server changes need no config update. `CONFIG_URL` is only needed for the rare case where the bootstrap parameters (channel/sponsor IDs, signature key) change.

#### Healthcheck

The container ships a Docker `HEALTHCHECK` that issues a request **through the local HTTP proxy** (not just a port check), so it only reports healthy once the tunnel can actually carry traffic. Inspect with `docker ps` (STATUS column) or `docker inspect --format '{{.State.Health.Status}}' psiphon001`.

---

## Project Layout

```
AutoGate/
├── docker-compose.yml      # Full stack definition
├── Dockerfile              # OpenVPN + tinyproxy slave image
├── HaproxyDockerfile       # HAProxy + vpngate fetcher
├── PsiphonDockerfile       # Psiphon ConsoleClient build + runtime image
├── proxy/
│   ├── haproxy.cfg         # Load balancer config
│   ├── vpngate.py          # VPNGate OpenVPN config downloader
│   └── run.sh              # HAProxy + periodic vpngate refresh
├── psiphon/
│   ├── psiphon.config      # Bundled standard Psiphon config (ports, server list)
│   ├── run.sh              # Entrypoint: build/validate config + auto-update + launch
│   └── healthcheck.sh      # Tunnel healthcheck (request through the proxy)
├── slave/
│   ├── run.sh              # Slave entrypoint
│   ├── ovpn.sh             # Random OpenVPN connect
│   ├── tinyproxy.sh        # HTTP proxy bound to tun0
│   ├── watchdog.sh         # Periodic VPN/proxy rotation
│   └── tinyproxy.conf      # Tinyproxy settings
├── ovpn/                   # Shared OpenVPN configs (created at runtime)
├── psiphon_data/           # Psiphon tunnel state (created at runtime)
└── data/                   # WARP persistent data
```

---

## Troubleshooting

- **Empty `ovpn/` folder** — Ensure the `haproxy` container can reach `www.vpngate.net`. Check logs: `docker logs haproxy`.
- **Proxy returns errors** — Inspect HAProxy stats at `http://localhost:2086/` for backend `DOWN` states.
- **OpenVPN fails** — VPNGate endpoints are public and ephemeral; rotation will try another config on the next watchdog cycle.
- **High resource usage** — Reduce the number of `ovpn_proxy_*` services in compose.

---

## Third-Party Services & Dependencies

AutoGate integrates with external and third-party components, including:

- [VPNGate](http://www.vpngate.net/) — public VPN relay list (subject to their terms)
- [Cloudflare WARP](https://www.cloudflare.com/warp/) — optional egress path
- [Psiphon](https://github.com/Psiphon-Labs/psiphon-tunnel-core) — open-source censorship-circumvention tunnel (subject to their terms)
- [ProxyBroker2](https://github.com/bluet/proxybroker2) — public proxy discovery
- OpenVPN, HAProxy, tinyproxy — open-source software

You are responsible for complying with the terms of all upstream services and applicable laws.

---

## Disclaimer

AutoGate is provided **as-is** for legitimate, authorized testing and education. The authors and contributors **do not** endorse or accept responsibility for misuse, including but not limited to unauthorized access, fraud, spam, evasion of lawful controls, or any activity that violates **Vietnamese law** or **applicable international law**.

Always obtain written permission before testing systems you do not own.

---

## License

This project is released under a **Non-Commercial Educational License**. See [LICENSE](LICENSE) for full terms.

Commercial use, monetization, or integration into paid products/services **requires prior written authorization** from the copyright holder.
