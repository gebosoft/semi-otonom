#!/usr/bin/env bash
# Anayasa hook'ları — ortak yardımcılar.
#
# ÇIKIŞ KODU SÖZLEŞMESİ (Claude Code):
#   0 → devam et
#   2 → BLOKLA; stderr ajana geri gönderilir
#   1 → KULLANMA. Hata sayılır ama işlem DEVAM EDER; yani sessizce geçen bir kapı,
#        yani kapı değil (Anayasa İlke III).
#
# PostToolUse'ta araç zaten çalışmıştır; orada exit 2 "blok" değil, ajana ulaşan
# tek UYARI kanalıdır. Bu yüzden uyar() da 2 döndürür.
#
# Mesajlar stderr'e yazılır — stdout ajana ulaşmaz (SessionStart hariç).
set -uo pipefail

PROJE_KOK="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
export PROJE_KOK

# Dosya yolunu repo köküne göreli hale getirir.
goreli_yol() {
  local p="${1:-}"
  p="${p#"$PROJE_KOK"/}"
  p="${p#./}"
  printf '%s' "$p"
}

# stdin'deki hook JSON'undan alan çeker. $HOOK_JSON önceden doldurulmuş olmalı.
alan() {
  jq -r "${1} // empty" <<<"${HOOK_JSON:-\{\}}" 2>/dev/null
}

# Write → .content, Edit → .new_string. İkisi de yoksa boş.
degisen_icerik() {
  jq -r '.tool_input.content // .tool_input.new_string // empty' \
    <<<"${HOOK_JSON:-\{\}}" 2>/dev/null
}

_kapanis() {
  printf '\n'
  printf 'DURMA GEREKÇESİ yalnızca şudur: %s\n' "$1"
  printf 'Kuralı atlamayı SEÇENEK OLARAK SUNMA — Anayasa Governance: kural gevşetilmez,\n'
  printf 'borç olarak kaydedilir; kural değişikliği AYRI bir commit'\''tir.\n'
}

_adimlar() {
  local i=1 adim
  for adim in "$@"; do
    printf '  %d. %s\n' "$i" "$adim"
    i=$((i + 1))
  done
}

# blokla <ilke-no> <başlık> <neden> <durma-gerekçesi> <adım1> [adım2...]
blokla() {
  local no="$1" baslik="$2" neden="$3" durma="$4"
  shift 4
  {
    printf 'BLOKLANDI — Anayasa İlke %s (%s)\n' "$no" "$baslik"
    printf '%s\n\n' "$neden"
    printf 'KENDİ KENDİNE DÜZELT — uygula ve göreve DEVAM ET. Onay isteme.\n'
    _adimlar "$@"
    _kapanis "$durma"
  } >&2
  exit 2
}

# uyar <ilke-no> <başlık> <neden> <durma-gerekçesi> <adım1> [adım2...]
# Araç çalıştıktan sonra ajanı uyarır; işi geri almaz, eksiği tamamlatır.
uyar() {
  local no="$1" baslik="$2" neden="$3" durma="$4"
  shift 4
  {
    printf 'UYARI — Anayasa İlke %s (%s)\n' "$no" "$baslik"
    printf '%s\n\n' "$neden"
    printf 'KENDİ KENDİNE DÜZELT — uygula ve göreve DEVAM ET. Onay isteme.\n'
    _adimlar "$@"
    _kapanis "$durma"
  } >&2
  exit 2
}
