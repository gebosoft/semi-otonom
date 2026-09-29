#!/usr/bin/env bash
# Anayasa İlke VII — Belirlenimcilik: aynı girdi aynı çıktıyı üretir.
#
# 'npm install' kilit dosyasını değiştirebilir; 'npm ci' değiştiremez.
# CI her iki job'da da npm ci kullanıyor (.github/workflows/ci.yml:28,54).
# Yerelde install çalıştırmak, CI ile yerel arasında farklı ağaç demektir — ve
# sözleşme üretimi (openapi-typescript) o ağaçtan çıkar.
#
# MUAF: global kurulumlar (-g / --global). Depo kilidine dokunmazlar; AGENTS.md
# dil sunucusu kurulumunu zaten böyle tarif ediyor.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

HOOK_JSON="$(cat)"
KOMUT="$(alan '.tool_input.command')"
[ -n "$KOMUT" ] || exit 0

# Global kurulum → serbest
grep -qE '(^|[[:space:]])(-g|--global)([[:space:]]|$)' <<<"$KOMUT" && exit 0

YASAK='(^|[;&|][[:space:]]*|[[:space:]])(npm[[:space:]]+(install|i|add|update|upgrade)([[:space:]]|$)|(yarn|pnpm|bun)[[:space:]]+(install|add|up|update|upgrade)([[:space:]]|$))'

if grep -qE "$YASAK" <<<"$KOMUT"; then
  blokla "VII" "Belirlenimcilik: aynı girdi aynı çıktıyı üretir" \
    "Bu komut kilit dosyasını değiştirebilir:

    $KOMUT

CI iki job'da da 'npm ci' çalıştırıyor (.github/workflows/ci.yml:28,54). Yerelde
'npm install' koşmak yerel ağacı CI'dan ayırır; sözleşme üreteci
(openapi-typescript, spec'te caret'sız 7.13.0) o ağaçtan çıktığı için üretilen
schema.d.ts kayabilir ve 'contracts' kapısı yanlış yere kırmızı/yeşil olur." \
    "GERÇEKTEN yeni bir bağımlılık eklemek gerekiyorsa — bu kilit dosyasını değiştiren bilinçli bir işlemdir, AYRI bir commit'tir ve kullanıcı onayı ister." \
    "Var olan bağımlılıkları kurmak istiyorsan: npm ci  (kökten çalıştır)." \
    "Bir workspace script'i çalıştıracaksan: npm run <script> --workspace <ad>." \
    "Global araç kuruyorsan -g ekle; bu hook global kurulumu bloklamaz."
fi

exit 0
