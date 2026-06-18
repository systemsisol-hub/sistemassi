#!/bin/bash
# Uso: ./deploy.sh [staging|production]
# Por defecto despliega a staging si no se especifica entorno.
set -e

ENV=${1:-staging}

echo ""
echo "Compilando Flutter web (release)..."
flutter build web --release

if [ "$ENV" = "production" ]; then
  echo ""
  echo "Desplegando a PRODUCCION..."
  npx wrangler deploy
  echo ""
  echo "Produccion actualizada."
else
  echo ""
  echo "Desplegando a STAGING..."
  npx wrangler deploy --env staging
  echo ""
  echo "Staging disponible. Revisa el URL en el dashboard de Cloudflare (sistemassi-staging)."
fi
