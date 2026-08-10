# Grafana Monitoring Stack

Docker-based monitoring and logging stack for self-hosted infrastructure.

## Components

- Grafana – dashboards and visualization
- Prometheus – metrics storage and querying
- Loki – centralized log storage
- Grafana Alloy – Docker log collection and forwarding to Loki
- Node Exporter – host metrics
- cAdvisor – Docker container metrics
- Blackbox Exporter – HTTP and ICMP availability checks

> Promtail is intentionally not used. Promtail reached end-of-life in March 2026; Grafana Alloy is its supported successor for this use case.

## Requirements

- Docker Engine with Docker Compose plugin
- Existing external Traefik Docker network (default: `proxy`)
- Traefik if Grafana should be exposed through HTTPS
- `openssl` for `first_install.sh`

## Installation

```bash
git clone https://github.com/happylippo/grafana-stack.git
cd grafana-stack
chmod +x first_install.sh
./first_install.sh
docker compose config
docker compose up -d
```

The installer creates `.env` from `.env.example`, asks for the Grafana domain and Traefik settings, and generates a random Grafana administrator password.

## Manual configuration

```bash
cp .env.example .env
nano .env
```

At minimum change:

```env
GRAFANA_ADMIN_PASSWORD=CHANGE_ME
GRAFANA_ROOT_URL=https://grafana.example.com
TRAEFIK_HOST_RULE=Host(`grafana.example.com`)
```

Then validate and start:

```bash
docker compose config
docker compose up -d
```

## Traefik

Only Grafana is attached to the external Traefik network. Prometheus, Loki and the exporters remain on the internal `monitoring` network and are not published on host ports.

Traefik settings are controlled through `.env`:

```env
TRAEFIK_DOCKER_NETWORK=proxy
TRAEFIK_ENTRYPOINTS=websecure
TRAEFIK_HOST_RULE=Host(`grafana.example.com`)
TRAEFIK_MIDDLEWARES=default@file,authentik@file
TRAEFIK_TLS=true
TRAEFIK_CERTRESOLVER=cloudflare_resolver
```

Change `TRAEFIK_MIDDLEWARES` to match the middleware names configured in your Traefik installation. `authentik@file` specifically refers to a middleware defined by Traefik's file provider; a middleware created through Docker labels would normally use `@docker` instead.

## Grafana provisioning

Prometheus and Loki are provisioned automatically as Grafana data sources:

- Prometheus: `http://prometheus:9090`
- Loki: `http://loki:3100`

Dashboard provisioning is prepared under `grafana/provisioning/dashboards/`.

## Prometheus targets

The default configuration collects:

- Prometheus itself
- host metrics through Node Exporter
- Docker metrics through cAdvisor
- HTTP probes for Google and Heise
- ICMP probes for Cloudflare, Google and Quad9

Edit `prometheus/prometheus.yml` to add additional exporters or services such as Traefik, CrowdSec, Authentik, PostgreSQL or Nextcloud.

After changing Prometheus configuration:

```bash
docker compose restart prometheus
```

## Logs with Loki and Alloy

Grafana Alloy discovers local Docker containers and forwards their logs to Loki. Loki stores data persistently in the `loki-data` Docker volume.

The Docker socket is currently mounted read-only into Alloy for Docker discovery. For more restrictive environments this can later be replaced with a Docker Socket Proxy.

## Persistent data

The following named Docker volumes are used:

- `grafana-data`
- `prometheus-data`
- `loki-data`
- `alloy-data`

Configuration remains version-controlled in the repository; runtime data does not.

## Useful commands

```bash
# Validate configuration
docker compose config

# Start
docker compose up -d

# Status
docker compose ps

# Logs
docker compose logs -f

# Update images
docker compose pull
docker compose up -d

# Stop
docker compose down
```

Do not use `docker compose down -v` unless you intentionally want to delete the persistent monitoring data.

## Security notes

- No Prometheus, Loki or exporter ports are published to the host.
- Grafana signup is disabled by default.
- `.env` is excluded from Git.
- Keep the generated Grafana password private.
- Restrict access to Grafana with your Traefik authentication/security middlewares where appropriate.
- Consider replacing Alloy's direct Docker socket access with a socket proxy as a hardening step.

## Directory structure

```text
.
├── .env.example
├── .gitignore
├── docker-compose.yml
├── first_install.sh
├── README.md
├── alloy/
│   └── config.alloy
├── blackbox/
│   └── config.yml
├── loki/
│   └── config.yml
├── prometheus/
│   └── prometheus.yml
└── grafana/
    └── provisioning/
        ├── dashboards/
        │   └── dashboards.yml
        └── datasources/
            └── datasources.yml
```
