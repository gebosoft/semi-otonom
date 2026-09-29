#!/usr/bin/env bash
# Anayasa İlke I — Sözleşme zinciri tek yönlüdür.
# Üretilmiş dosyaların elle düzenlenmesini bloklar.
#
# Korunan yollar (varlıkları doğrulandı):
#   contracts/*.json                          → Api.csproj:13-15 derleme zamanında üretir
#   packages/api-client-ts/src/schema.d.ts    → openapi-typescript üretir
#
# packages/api-client-ts/src/index.ts KORUNMAZ: o elle yazılmış cephedir.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

HOOK_JSON="$(cat)"
YOL="$(goreli_yol "$(alan '.tool_input.file_path')")"
[ -n "$YOL" ] || exit 0

if [[ "$YOL" == contracts/*.json ]] ||
  [[ "$YOL" == "packages/api-client-ts/src/schema.d.ts" ]]; then
  blokla "I" "Sözleşme zinciri tek yönlüdür" \
    "$YOL üretilmiş bir dosyadır; kaynak değil. Zincir tek yönlüdür:
C# kaynağı → contracts/Api.json → schema.d.ts → web. Buraya yazılan her şey bir
sonraki './scripts/generate-contracts.sh' çalışmasında sessizce silinir; ayrıca
CI'ın 'contracts' job'ı ('scripts/check-contracts.sh', exit 1) farkı yakalayıp
PR'ı kırmızıya düşürür." \
    "üretim komutu kaynak DOĞRUYKEN bile hata veriyorsa — yani zincirin kendisi bozuksa." \
    "Değişikliği C# kaynağında yap: uç nokta için api/src/Api/Endpoints/*.cs, yanıt şeması için ilgili 'sealed record'." \
    "Üretimi çalıştır: ./scripts/generate-contracts.sh  (veya: npm run contracts)" \
    "Doğrula: ./scripts/check-contracts.sh → EXIT=0 bekleniyor." \
    "Üretilen dosyaları kaynak değişikliğiyle AYNI commit'e ekle (git add -A)."
fi

exit 0
