#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

echo "→ OpenAPI"
dotnet build api/src/Api/Api.csproj -v q

echo "→ TypeScript"
npm run generate --workspace @semi-otonom/api-client

echo "✓ tamam"