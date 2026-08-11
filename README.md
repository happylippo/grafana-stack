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
- Docker Socket Proxy – restricted Docker API access for Alloy
- Optional Authentik SSO via OAuth2/OpenID Connect

> Promtail is intentionally not used. Promtail reached end-of-life in March 2026; Grafana Alloy is its supported successor for this use case.

## Requirements

- Docker Engine with Docker Compose plugin
- Existing external Traefik Docker network (default: `proxy`)
- Traefik if Grafana should be exposed through HTTPS
- `openssl` for `first_install.sh`
- Optional: an Authentik instance for SSO

## Installation

```bash
git clone https://github.com/happylippo/grafana-stack.git
cd grafana-stack
chmod +x first_install.sh
./first_install.sh
docker compose config
docker compose up -d
```

The installer creates `.env` from `.env.example`, asks for the Grafana domain and Traefik settings, generates a random Grafana administrator password, and can optionally configure Authentik SSO.

The resulting `.env` is set to mode `600` because it can contain the Grafana password and Authentik client secret.

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

## Authentik SSO

Grafana supports Authentik through Grafana's Generic OAuth / OpenID Connect integration.

### 1. Create the Authentik application

In the Authentik admin interface create a new application with an **OAuth2/OpenID Connect** provider.

Use a strict redirect URI matching your Grafana URL exactly:

```text
https://grafana.example.com/login/generic_oauth
```

Select the normal OpenID scopes:

```text
openid
profile
email
```

Note the following values from Authentik:

- Client ID
- Client Secret
- Application slug (default used by this stack: `grafana`)

### 2. Optional role groups

Create these Authentik groups if you want automatic Grafana role mapping:

```text
Grafana Admins
Grafana Editors
Grafana Viewers
```

The stack maps roles as follows:

- `Grafana Admins` → Grafana `Admin`
- `Grafana Editors` → Grafana `Editor`
- all other successfully authenticated users → Grafana `Viewer`

`Admin` here is the Grafana organization administrator role, not the global Grafana server administrator role.

### 3. Configure `.env`

```env
AUTHENTIK_ENABLED=true
AUTHENTIK_URL=https://auth.example.com
AUTHENTIK_APP_SLUG=grafana
AUTHENTIK_OAUTH_NAME=Authentik
AUTHENTIK_CLIENT_ID=YOUR_CLIENT_ID
AUTHENTIK_CLIENT_SECRET=YOUR_CLIENT_SECRET
AUTHENTIK_ALLOW_SIGN_UP=true
AUTHENTIK_AUTO_LOGIN=false
```

Do not add a trailing slash to `AUTHENTIK_URL`.

`AUTHENTIK_ALLOW_SIGN_UP=true` allows Grafana to create a local Grafana user automatically after successful authentication through Authentik. Normal Grafana self-registration remains disabled through `GF_USERS_ALLOW_SIGN_UP=false`.

Keep `AUTHENTIK_AUTO_LOGIN=false` while initially testing. Grafana then shows a **Sign in with Authentik** button and the local Grafana login remains available as a fallback.

After SSO works reliably, you can set:

```env
AUTHENTIK_AUTO_LOGIN=true
```

This redirects users directly from Grafana to Authentik.

### 4. Traefik and ForwardAuth

When Grafana itself authenticates users through OIDC, a separate Authentik ForwardAuth middleware in front of Grafana is normally unnecessary.

The recommended middleware setting for a fresh SSO installation is therefore for example:

```env
TRAEFIK_MIDDLEWARES=default@file
```

Do not use `authentik@file` for Grafana unless you intentionally want both ForwardAuth and Grafana OIDC.

Other security/header middlewares can of course remain configured.

### 5. Apply SSO changes

After changing `.env`, recreate Grafana so the new environment variables are applied:

```bash
docker compose config
docker compose up -d --force-recreate grafana
```

Then open Grafana. With auto-login disabled, the login page should show an Authentik login button.

For troubleshooting:

```bash
docker compose logs --tail=100 grafana
```

### Authentik endpoints used by the stack

The stack builds the following endpoints automatically from `AUTHENTIK_URL`:

```text
/application/o/authorize/
/application/o/token/
/application/o/userinfo/
/application/o/<application-slug>/end-session/
```

Grafana's callback remains:

```text
https://<grafana-domain>/login/generic_oauth
```

## Traefik

Only Grafana is attached to the external Traefik network. Prometheus, Loki and the exporters remain on the internal `monitoring` network and are not published on host ports.

Traefik settings are controlled through `.env`:

```env
TRAEFIK_DOCKER_NETWORK=proxy
TRAEFIK_ENTRYPOINTS=websecure
TRAEFIK_HOST_RULE=Host(`grafana.example.com`)
TRAEFIK_MIDDLEWARES=default@file
TRAEFIK_TLS=true
TRAEFIK_CERTRESOLVER=cloudflare_resolver
```

Change `TRAEFIK_MIDDLEWARES` to match the middleware names configured in your Traefik installation. A middleware defined through Traefik's file provider uses `@file`; one created through Docker labels normally uses `@docker`.

## Grafana provisioning

Prometheus and Loki are provisioned automatically as Grafana data sources:

- Prometheus: `http://prometheus:9090`
- Loki: `http://loki:3100`

The included dashboards are automatically provisioned from `grafana/dashboards/`.

Current dashboards include:

- Host / System Overview
- Docker / Containers
- Uptime / Blackbox
- Docker / Loki Logs

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

Alloy does not get the Docker socket directly. It connects to the included Docker Socket Proxy, which only exposes the read-only API areas required for discovery:

```yaml
CONTAINERS: "1"
INFO: "1"
NETWORKS: "1"
POST: "0"
```

`NETWORKS=1` is required because Alloy's Docker discovery also computes Docker network labels. `POST=0` keeps write operations through the proxy disabled.

To query all collected Docker logs in Grafana Explore using Loki:

```logql
{job="docker"}
```

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
- Grafana normal self-registration is disabled by default.
- `.env` is excluded from Git and the installer sets it to mode `600`.
- Keep the generated Grafana password and Authentik Client Secret private.
- Alloy uses the restricted Docker Socket Proxy instead of direct Docker socket access.
- Docker API write requests through the socket proxy remain disabled with `POST=0`.
- If Grafana uses Authentik OIDC, avoid stacking an additional ForwardAuth layer unless you specifically need it.

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
    ├── dashboards/
    │   ├── docker-containers.json
    │   ├── docker-logs.json
    │   ├── host-system.json
    │   └── uptime-blackbox.json
    └── provisioning/
        ├── dashboards/
        │   └── dashboards.yml
        └── datasources/
            └── datasources.yml
```
