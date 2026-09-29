#!/usr/bin/env bash
# Anayasa İlke II — Her uç nokta adlandırılmış yanıt tipi döndürür.
#
# İki ihlali yakalar:
#   A) 'Results.<fabrika>(' — 'TypedResults.' olmalı
#   B) Uç nokta satırında anonim tip ('new {') — 'sealed record' olmalı
#
# Kapsam: yalnızca api/src/Api/ altındaki .cs dosyaları (uç noktalar orada yaşar).
# Kanıt: anonim tipe çevrilen /health'te OpenAPI 200 yanıtı {"description":"OK"}'e
# indi, components boşaldı, TS 'content?: never' üretti — ve üretim yine EXIT=0
# döndü. Kayıp sessizdir; bu yüzden kural kapıya değil koda bağlıdır.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

HOOK_JSON="$(cat)"
YOL="$(goreli_yol "$(alan '.tool_input.file_path')")"
[ -n "$YOL" ] || exit 0

[[ "$YOL" == api/src/Api/*.cs ]] || exit 0

ICERIK="$(degisen_icerik)"
[ -n "$ICERIK" ] || exit 0

FABRIKA='Ok|Created|CreatedAtRoute|Accepted|AcceptedAtRoute|NoContent|BadRequest|NotFound|Conflict|UnprocessableEntity|Problem|ValidationProblem|Json|Text|Content|File|Bytes|Stream|Redirect|LocalRedirect|Unauthorized|Forbid|Empty'

# A) Çıplak Results.<fabrika>( — TypedResults. değil
BULGU_A="$(grep -nE "(^|[^A-Za-z0-9_.])Results\.($FABRIKA)\(" <<<"$ICERIK" || true)"

# B) Uç nokta/sonuç satırında anonim tip
BULGU_B="$(grep -nE 'new[[:space:]]*\{' <<<"$ICERIK" |
  grep -E '(TypedResults\.|Results\.|Map(Get|Post|Put|Patch|Delete)\()' || true)"

if [ -n "$BULGU_A" ] || [ -n "$BULGU_B" ]; then
  NEDEN="$YOL içinde İlke II ihlali var."
  [ -n "$BULGU_A" ] && NEDEN="$NEDEN

  Çıplak 'Results.' kullanımı (TypedResults olmalı):
$(sed 's/^/    /' <<<"$BULGU_A")"
  [ -n "$BULGU_B" ] && NEDEN="$NEDEN

  Uç nokta yanıtında anonim tip (adlandırılmış record olmalı):
$(sed 's/^/    /' <<<"$BULGU_B")"
  NEDEN="$NEDEN

Anonim tip OpenAPI şemasına ÇIKMAZ: 200 yanıtı {\"description\":\"OK\"}'e iner,
components boşalır, üretilen TypeScript 'content?: never' olur. Üretim komutu buna
rağmen EXIT=0 döner — yani sözleşme kapısı bu kaybı yakalamaz."

  blokla "II" "Her uç nokta adlandırılmış yanıt tipi döndürür" \
    "$NEDEN" \
    "yanıt gövdesi gerçekten yoksa (204/302 gibi) — o durumda TypedResults.NoContent() kullan, anonim tip yine yazma." \
    "Yanıt için bir 'public sealed record <Ad>Response(...)' tanımla (aynı dosyada, uç noktanın üstünde)." \
    "'Results.X(...)' yerine 'TypedResults.X(new <Ad>Response(...))' yaz." \
    "Uç noktaya WithName(\"<OperationId>\") ver — OpenAPI operationId'si ve TS anahtarı odur." \
    "./scripts/generate-contracts.sh çalıştır ve packages/api-client-ts/src/index.ts'e takma adı ekle (İlke I)."
fi

exit 0
