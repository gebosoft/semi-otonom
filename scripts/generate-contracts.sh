#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

echo "→ OpenAPI"
# --no-incremental ZORUNLU: artımlı derleme OpenAPI belgesini yeniden yazmayabilir.
# O durumda aşağıdaki TypeScript adımı eski belgeyi okur, üretilenler kaynakla tutarlı
# GÖRÜNÜR ve check-contracts.sh fark bulamaz — kapı çalışır ama yanlış girdiye bakar.
dotnet build api/src/Api/Api.csproj -v q --no-incremental

echo "→ TypeScript"
npm run generate --workspace @semi-otonom/api-client

echo "✓ tamam"