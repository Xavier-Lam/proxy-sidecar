# proxy-sidecar
[![GitHub Repo](https://img.shields.io/badge/GitHub-Xavier--Lam%2Fproxy--sidecar-blue?logo=github)](https://github.com/Xavier-Lam/proxy-sidecar)
[![Docker](https://img.shields.io/docker/v/xavierlam/proxy-sidecar/latest?label=docker)](https://hub.docker.com/r/xavierlam/proxy-sidecar)

A minimal Docker sidecar container that transparently redirects all TCP traffic from companion containers through an upstream proxy (HTTP CONNECT / SOCKS4 / SOCKS5).

The sidecar shares the application container's network namespace. It uses iptables to intercept outbound TCP connections and redirects them through [gost](https://github.com/go-gost/gost).

## Usage

A quick example using *Docker Compose*:

```yaml
services:
  app:
    image: your-app

  proxy:
    image: xavierlam/proxy-sidecar:latest
    network_mode: "service:app"
    depends_on:
      - app
    restart: always  # Once the main container stops, the sidecar will exit too. `always` ensures it restarts with the app.
    cap_add:
      - NET_ADMIN
      - NET_RAW
    environment:
      PROXY_SERVER: "proxy.example.com"
      PROXY_PORT: "1080"
```

Run with docker cli:

```bash
# Start the app container first
docker run -d --name my-app your-app

# Start the proxy sidecar, joining the app's network namespace
docker run -d --rm \
  --cap-add NET_ADMIN --cap-add NET_RAW \
  --network=container:my-app \
  -e PROXY_SERVER=proxy.example.com \
  -e PROXY_PORT=1080 \
  xavierlam/proxy-sidecar:latest
```


### Environment Variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `PROXY_SERVER` | **Yes** | — | Upstream proxy IP address or hostname |
| `PROXY_PORT` | **Yes** | — | Upstream proxy port |
| `PROXY_TYPE` | No | `http` | Proxy protocol: `http`, `socks4`, or `socks5` |

### Required Capabilities

The sidecar needs `NET_ADMIN` and `NET_RAW` capabilities to configure iptables rules:

```yaml
cap_add:
  - NET_ADMIN
  - NET_RAW
```

## How It Works

1. The sidecar container shares the app container's network namespace (see [Network Setup](#network-setup) below).
2. iptables / ip6tables redirect all outbound TCP traffic (except private/loopback ranges) to a local gost transparent proxy listener.
3. gost establishes an upstream tunnel (HTTP CONNECT / SOCKS) to the configured proxy and forwards traffic bidirectionally.

### Network Setup

The sidecar's iptables rules apply only within its own network namespace. The application container must **share** the sidecar's network namespace — simply putting both containers on the same Docker network is not enough.

## Notes

- Private address ranges are always excluded from proxying (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`, etc. for IPv4; `fc00::/7`, `fe80::/10`, etc. for IPv6).
