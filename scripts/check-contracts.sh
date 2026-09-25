#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Üretimden önceki hali sakla
mkdir -p "$TMP/before"
cp -R contracts                      "$TMP/before/contracts"
cp -R packages/api-client-ts/src     "$TMP/before/ts"

./scripts/generate-contracts.sh > /dev/null

FAIL=0
diff -rq "$TMP/before/contracts" contracts                   || FAIL=1
diff -rq "$TMP/before/ts"        packages/api-client-ts/src  || FAIL=1

if [[ $FAIL -ne 0 ]]; then
  echo ""
  echo "--- FARK ---"
  diff -ru "$TMP/before/contracts" contracts || true
  diff -ru "$TMP/before/ts" packages/api-client-ts/src || true
  echo "--- /FARK ---"
  echo "HATA: Üretilmiş sözleşme dosyaları kaynak koddan geride."
fi

echo "✓ Sözleşmeler güncel"