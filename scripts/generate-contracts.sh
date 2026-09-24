#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

echo "→ OpenAPI"
dotnet build api/src/Api/Api.csproj -v q

echo "→ TypeScript"
npm run generate --workspace @semi-otonom/api-client

echo "→ Dart"
openapi-generator-cli generate \
  -i contracts/Api.json \
  -g dart \
  -o mobile/packages/api_client \
  --skip-validate-spec \
  --additional-properties=pubName=api_client

# Üretilen pubspec eski SDK/test kısıtları taşır; düzelt.
# perl kullanıyoruz: macOS ve Linux'ta aynı çalışır (sed -i farklı davranır).
perl -pi -e "s|sdk: '>=2\.\d+\.\d+ <4\.0\.0'|sdk: '>=3.0.0 <4.0.0'|" mobile/packages/api_client/pubspec.yaml
perl -pi -e "s|test: '>=1\.21\.6 <1\.22\.0'|test: '^1.25.0'|" mobile/packages/api_client/pubspec.yaml

echo "✓ tamam"