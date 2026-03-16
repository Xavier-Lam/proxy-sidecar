# proxy-sidecar
[![Docker](https://img.shields.io/docker/v/xavierlam/proxy-sidecar/latest?label=docker)](https://hub.docker.com/r/xavierlam/proxy-sidecar)

A minimal Docker sidecar container that transparently redirects all TCP traffic from companion containers through an upstream proxy (HTTP CONNECT / SOCKS4 / SOCKS5).

The sidecar shares the application container's network namespace. It uses iptables to intercept outbound TCP connections and redirects them through [gost](https://github.com/go-gost/gost).

## Environment Variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `PROXY_SERVER` | **Yes** | — | Upstream proxy IP address or hostname |
| `PROXY_PORT` | **Yes** | — | Upstream proxy port |
| `PROXY_TYPE` | No | `http` | Proxy protocol: `http`, `socks4`, or `socks5` |

## How It Works

1. The sidecar container shares the app container's network namespace (see [Network Setup](#network-setup) below).
2. iptables / ip6tables redirect all outbound TCP traffic (except private/loopback ranges) to a local gost transparent proxy listener.
3. gost establishes an upstream tunnel (HTTP CONNECT / SOCKS) to the configured proxy and forwards traffic bidirectionally.

## Network Setup

The sidecar's iptables rules apply only within its own network namespace. The application container must **share** the sidecar's network namespace — simply putting both containers on the same Docker network is not enough.

**Docker Compose** (recommended):

```yaml
services:
  app:
    image: alpine/curl
    command: ["sleep", "infinity"]

  proxy:
    image: xavierlam/proxy-sidecar:latest
    network_mode: "service:app"  # Share app's network namespace
    depends_on:
      - app
    cap_add:
      - NET_ADMIN
      - NET_RAW
    environment:
      PROXY_SERVER: "proxy.example.com"
      PROXY_PORT: "1080"
```

**Docker CLI**:

```bash
# Start the sidecar first
docker run -d --name my-proxy \
  --cap-add NET_ADMIN --cap-add NET_RAW \
  -e PROXY_SERVER=proxy.example.com \
  -e PROXY_PORT=1080 \
  xavierlam/proxy-sidecar:latest

# Join the sidecar's network namespace
docker run --rm \
  --network=container:my-proxy \
  alpine/curl -I https://www.google.com
```

## Required Capabilities

The sidecar needs `NET_ADMIN` and `NET_RAW` capabilities to configure iptables rules:

```yaml
cap_add:
  - NET_ADMIN
  - NET_RAW
```

## Building Locally

```bash
docker build -t proxy-sidecar .
```

## Notes

- Private address ranges are always excluded from proxying (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`, etc. for IPv4; `fc00::/7`, `fe80::/10`, etc. for IPv6).
