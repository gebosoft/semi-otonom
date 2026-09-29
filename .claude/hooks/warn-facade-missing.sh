#!/usr/bin/env bash
# Anayasa İlke I — cephe zorunludur (PostToolUse, UYARI).
#
# Uç nokta dosyası yazıldıktan SONRA iki şeyi kontrol eder:
#   A) Dosyadaki her rota yolu ("/health" gibi) packages/api-client-ts/src/index.ts
#      cephesinde geçiyor mu?
#   B) Üretilmiş sözleşme, kaynaktan eski mi? (mtime karşılaştırması — derleme yapmaz)
#
# Neden UYARI, neden BLOK değil: dosya zaten yazıldı. Araç çalıştıktan sonra ajana
# ulaşan tek kanal stderr + exit 2'dir; burada 2 "geri al" değil "eksiği tamamla"
# demektir.
#
# Neden bu kontrol var: /health anonim tipe çevrildiğinde şema kayboldu ama hiçbir
# kapı kırmızı olmadı — kaybı fark eden TEK şey index.ts:8'deki dereference'tı
# (TS2339). Cephede takma adı olmayan bir uç noktanın şeması sessizce yok olur.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

HOOK_JSON="$(cat)"
YOL="$(goreli_yol "$(alan '.tool_input.file_path')")"
[ -n "$YOL" ] || exit 0

[[ "$YOL" == api/src/Api/*.cs ]] || exit 0

TAM_YOL="$PROJE_KOK/$YOL"
CEPHE="$PROJE_KOK/packages/api-client-ts/src/index.ts"
SOZLESME="$PROJE_KOK/contracts/Api.json"

[ -f "$TAM_YOL" ] || exit 0
[ -f "$CEPHE" ] || exit 0

# ── A) Cephede karşılığı olmayan rotalar ──────────────────────────────────────
ROTALAR="$(grep -oE 'Map(Get|Post|Put|Patch|Delete)\([[:space:]]*"[^"]+"' "$TAM_YOL" |
  grep -oE '"[^"]+"' | tr -d '"' | sort -u || true)"

EKSIK=""
while IFS= read -r rota; do
  [ -n "$rota" ] || continue
  grep -qF "\"$rota\"" "$CEPHE" || EKSIK="$EKSIK  - $rota"$'\n'
done <<<"$ROTALAR"

# ── B) Sözleşme kaynaktan eski mi ─────────────────────────────────────────────
BAYAT=0
if [ -f "$SOZLESME" ] && [ "$TAM_YOL" -nt "$SOZLESME" ]; then
  BAYAT=1
fi

[ -n "$EKSIK" ] || [ "$BAYAT" -eq 1 ] || exit 0

NEDEN="$YOL yazıldı, ama sözleşme zinciri henüz tamamlanmadı."
if [ -n "$EKSIK" ]; then
  NEDEN="$NEDEN

  Cephede (packages/api-client-ts/src/index.ts) takma adı olmayan rotalar:
$EKSIK
  Cephede dereference edilmeyen bir uç noktanın şeması kaybolursa hiçbir yerde
  hata çıkmaz: 'web' job'ı yeşil kalır, istemci tipi sessizce 'never' olur."
fi
if [ "$BAYAT" -eq 1 ]; then
  NEDEN="$NEDEN

  contracts/Api.json kaynaktan eski — üretim henüz çalıştırılmadı."
fi

uyar "I" "Sözleşme zinciri tek yönlüdür — cephe zorunludur" \
  "$NEDEN" \
  "üretim komutu kaynak doğruyken bile hata veriyorsa — yani zincirin kendisi bozuksa." \
  "./scripts/generate-contracts.sh çalıştır (üretim dotnet derlemesi yapar)." \
  "packages/api-client-ts/src/index.ts'e her yeni rota için takma ad ekle; var olanın biçimi: export type HealthResponse = paths[\"/health\"][\"get\"][\"responses\"][\"200\"][\"content\"][\"application/json\"];" \
  "Cepheyi derle: npm run typecheck --workspace @semi-otonom/api-client → EXIT=0 bekleniyor." \
  "./scripts/check-contracts.sh ile doğrula ve üretilenleri aynı commit'e ekle."
