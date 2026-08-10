#!/usr/bin/env bash
set -Eeuo pipefail

cd "$(dirname "$0")"

if [[ -f .env ]]; then
  echo ".env already exists. Aborting to avoid overwriting it."
  exit 1
fi

cp .env.example .env

read -rp "Grafana domain [grafana.example.com]: " GRAFANA_DOMAIN
GRAFANA_DOMAIN=${GRAFANA_DOMAIN:-grafana.example.com}

read -rp "Traefik Docker network [proxy]: " TRAEFIK_NETWORK
TRAEFIK_NETWORK=${TRAEFIK_NETWORK:-proxy}

read -rp "Traefik middleware chain [default@file,authentik@file]: " TRAEFIK_MIDDLEWARES
TRAEFIK_MIDDLEWARES=${TRAEFIK_MIDDLEWARES:-default@file,authentik@file}

read -rp "Traefik certificate resolver [cloudflare_resolver]: " TRAEFIK_CERTRESOLVER
TRAEFIK_CERTRESOLVER=${TRAEFIK_CERTRESOLVER:-cloudflare_resolver}

GRAFANA_PASSWORD=$(openssl rand -base64 32 | tr -d '\n' | tr '/+' '_-')

sed -i \
  -e "s|GRAFANA_ADMIN_PASSWORD=CHANGE_ME|GRAFANA_ADMIN_PASSWORD=${GRAFANA_PASSWORD}|" \
  -e "s|GRAFANA_ROOT_URL=https://grafana.example.com|GRAFANA_ROOT_URL=https://${GRAFANA_DOMAIN}|" \
  -e "s|TRAEFIK_DOCKER_NETWORK=proxy|TRAEFIK_DOCKER_NETWORK=${TRAEFIK_NETWORK}|" \
  -e "s|TRAEFIK_HOST_RULE=Host(\`grafana.example.com\`)|TRAEFIK_HOST_RULE=Host(\`${GRAFANA_DOMAIN}\`)|" \
  -e "s|TRAEFIK_MIDDLEWARES=default@file,authentik@file|TRAEFIK_MIDDLEWARES=${TRAEFIK_MIDDLEWARES}|" \
  -e "s|TRAEFIK_CERTRESOLVER=cloudflare_resolver|TRAEFIK_CERTRESOLVER=${TRAEFIK_CERTRESOLVER}|" \
  .env

if ! docker network inspect "${TRAEFIK_NETWORK}" >/dev/null 2>&1; then
  echo "Warning: external Docker network '${TRAEFIK_NETWORK}' does not exist."
  echo "Create it with: docker network create ${TRAEFIK_NETWORK}"
fi

echo
echo "Configuration created successfully."
echo "Grafana URL: https://${GRAFANA_DOMAIN}"
echo "Grafana user: admin"
echo "Grafana password: ${GRAFANA_PASSWORD}"
echo
echo "Start with: docker compose up -d"
