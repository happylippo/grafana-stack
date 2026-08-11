#!/usr/bin/env bash
set -Eeuo pipefail

cd "$(dirname "$0")"

if [[ -f .env ]]; then
  echo ".env already exists. Aborting to avoid overwriting it."
  exit 1
fi

cp .env.example .env

sed_escape() {
  printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'
}

read -rp "Grafana domain [grafana.example.com]: " GRAFANA_DOMAIN
GRAFANA_DOMAIN=${GRAFANA_DOMAIN:-grafana.example.com}

read -rp "Traefik Docker network [proxy]: " TRAEFIK_NETWORK
TRAEFIK_NETWORK=${TRAEFIK_NETWORK:-proxy}

read -rp "Traefik middleware chain [default@file]: " TRAEFIK_MIDDLEWARES
TRAEFIK_MIDDLEWARES=${TRAEFIK_MIDDLEWARES:-default@file}

read -rp "Traefik certificate resolver [cloudflare_resolver]: " TRAEFIK_CERTRESOLVER
TRAEFIK_CERTRESOLVER=${TRAEFIK_CERTRESOLVER:-cloudflare_resolver}

AUTHENTIK_ENABLED=false
AUTHENTIK_URL=https://auth.example.com
AUTHENTIK_APP_SLUG=grafana
AUTHENTIK_CLIENT_ID=""
AUTHENTIK_CLIENT_SECRET=""
AUTHENTIK_AUTO_LOGIN=false

read -rp "Enable Authentik SSO for Grafana? [y/N]: " ENABLE_SSO
if [[ "${ENABLE_SSO,,}" =~ ^(y|yes|j|ja)$ ]]; then
  AUTHENTIK_ENABLED=true

  read -rp "Authentik URL (e.g. https://auth.example.com): " AUTHENTIK_URL
  AUTHENTIK_URL=${AUTHENTIK_URL%/}

  read -rp "Authentik application slug [grafana]: " AUTHENTIK_APP_SLUG
  AUTHENTIK_APP_SLUG=${AUTHENTIK_APP_SLUG:-grafana}

  read -rp "Authentik OAuth Client ID: " AUTHENTIK_CLIENT_ID
  read -rsp "Authentik OAuth Client Secret: " AUTHENTIK_CLIENT_SECRET
  echo

  read -rp "Automatically redirect Grafana login to Authentik? [y/N]: " ENABLE_AUTO_LOGIN
  if [[ "${ENABLE_AUTO_LOGIN,,}" =~ ^(y|yes|j|ja)$ ]]; then
    AUTHENTIK_AUTO_LOGIN=true
  fi

  if [[ -z "${AUTHENTIK_URL}" || -z "${AUTHENTIK_CLIENT_ID}" || -z "${AUTHENTIK_CLIENT_SECRET}" ]]; then
    echo "Authentik URL, Client ID and Client Secret are required when SSO is enabled."
    rm -f .env
    exit 1
  fi
fi

GRAFANA_PASSWORD=$(openssl rand -base64 32 | tr -d '\n' | tr '/+' '_-')

GRAFANA_PASSWORD_ESC=$(sed_escape "${GRAFANA_PASSWORD}")
GRAFANA_DOMAIN_ESC=$(sed_escape "${GRAFANA_DOMAIN}")
TRAEFIK_NETWORK_ESC=$(sed_escape "${TRAEFIK_NETWORK}")
TRAEFIK_MIDDLEWARES_ESC=$(sed_escape "${TRAEFIK_MIDDLEWARES}")
TRAEFIK_CERTRESOLVER_ESC=$(sed_escape "${TRAEFIK_CERTRESOLVER}")
AUTHENTIK_URL_ESC=$(sed_escape "${AUTHENTIK_URL}")
AUTHENTIK_APP_SLUG_ESC=$(sed_escape "${AUTHENTIK_APP_SLUG}")
AUTHENTIK_CLIENT_ID_ESC=$(sed_escape "${AUTHENTIK_CLIENT_ID}")
AUTHENTIK_CLIENT_SECRET_ESC=$(sed_escape "${AUTHENTIK_CLIENT_SECRET}")

sed -i \
  -e "s|GRAFANA_ADMIN_PASSWORD=CHANGE_ME|GRAFANA_ADMIN_PASSWORD=${GRAFANA_PASSWORD_ESC}|" \
  -e "s|GRAFANA_ROOT_URL=https://grafana.example.com|GRAFANA_ROOT_URL=https://${GRAFANA_DOMAIN_ESC}|" \
  -e "s|TRAEFIK_DOCKER_NETWORK=proxy|TRAEFIK_DOCKER_NETWORK=${TRAEFIK_NETWORK_ESC}|" \
  -e "s|TRAEFIK_HOST_RULE=Host(\`grafana.example.com\`)|TRAEFIK_HOST_RULE=Host(\`${GRAFANA_DOMAIN_ESC}\`)|" \
  -e "s|TRAEFIK_MIDDLEWARES=default@file|TRAEFIK_MIDDLEWARES=${TRAEFIK_MIDDLEWARES_ESC}|" \
  -e "s|TRAEFIK_CERTRESOLVER=cloudflare_resolver|TRAEFIK_CERTRESOLVER=${TRAEFIK_CERTRESOLVER_ESC}|" \
  -e "s|AUTHENTIK_ENABLED=false|AUTHENTIK_ENABLED=${AUTHENTIK_ENABLED}|" \
  -e "s|AUTHENTIK_URL=https://auth.example.com|AUTHENTIK_URL=${AUTHENTIK_URL_ESC}|" \
  -e "s|AUTHENTIK_APP_SLUG=grafana|AUTHENTIK_APP_SLUG=${AUTHENTIK_APP_SLUG_ESC}|" \
  -e "s|AUTHENTIK_CLIENT_ID=|AUTHENTIK_CLIENT_ID=${AUTHENTIK_CLIENT_ID_ESC}|" \
  -e "s|AUTHENTIK_CLIENT_SECRET=|AUTHENTIK_CLIENT_SECRET=${AUTHENTIK_CLIENT_SECRET_ESC}|" \
  -e "s|AUTHENTIK_AUTO_LOGIN=false|AUTHENTIK_AUTO_LOGIN=${AUTHENTIK_AUTO_LOGIN}|" \
  .env

chmod 600 .env

if ! docker network inspect "${TRAEFIK_NETWORK}" >/dev/null 2>&1; then
  echo "Warning: external Docker network '${TRAEFIK_NETWORK}' does not exist."
  echo "Create it with: docker network create ${TRAEFIK_NETWORK}"
fi

echo
echo "Configuration created successfully."
echo "Grafana URL: https://${GRAFANA_DOMAIN}"
echo "Grafana user: admin"
echo "Grafana password: ${GRAFANA_PASSWORD}"

if [[ "${AUTHENTIK_ENABLED}" == "true" ]]; then
  echo "Authentik SSO: enabled"
  echo "OAuth callback URL: https://${GRAFANA_DOMAIN}/login/generic_oauth"
  echo "Authentik application slug: ${AUTHENTIK_APP_SLUG}"
else
  echo "Authentik SSO: disabled"
fi

echo
echo "Start with: docker compose up -d"
