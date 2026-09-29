#!/usr/bin/env bash
# Oturum başı durum kontrolü (SessionStart, UYARI).
#
# SessionStart'ta exit 0 ile yazılan STDOUT ajanın bağlamına eklenir — diğer
# hook'ların aksine burada kanal stdout'tur. Bu yüzden asla 2 döndürmez: oturumu
# bloklamak istemeyiz, yalnızca ajanın yanlış varsayımla başlamasını engelleriz.
#
# Hiçbir şey derlemez, ağa çıkmaz; yalnızca dosya sistemine ve git'e bakar.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

cd "$PROJE_KOK" 2>/dev/null || exit 0

SATIR=()

# ── Dal ───────────────────────────────────────────────────────────────────────
DAL="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || printf '?')"
if [[ "$DAL" =~ ^(main|master)$ ]]; then
  SATIR+=("UYARI: '$DAL' dalındasın. Anayasa İlke V: main'e doğrudan commit/push yasak.")
  SATIR+=("       Kod değiştirmeden ÖNCE dal aç: git switch -c feat/<konu>")
else
  SATIR+=("Dal: $DAL")
fi

# ── Sözleşme tazeliği (derleme yapmadan, mtime ile) ───────────────────────────
if [ -f contracts/Api.json ]; then
  YENI="$(find api/src -name '*.cs' -newer contracts/Api.json \
    -not -path '*/obj/*' -not -path '*/bin/*' 2>/dev/null | head -5)"
  if [ -n "$YENI" ]; then
    SATIR+=("UYARI: contracts/Api.json kaynaktan eski görünüyor. Değişen:")
    while IFS= read -r f; do [ -n "$f" ] && SATIR+=("       $f"); done <<<"$YENI"
    SATIR+=("       Doğrula: ./scripts/check-contracts.sh  (EXIT=0 bekleniyor)")
  fi
else
  SATIR+=("UYARI: contracts/Api.json yok — ./scripts/generate-contracts.sh çalıştırılmamış.")
fi

# ── Araç önkoşulları ──────────────────────────────────────────────────────────
command -v jq >/dev/null 2>&1 ||
  SATIR+=("UYARI: jq kurulu değil — anayasa hook'ları girdiyi ayrıştıramaz, SESSİZCE geçer.")
command -v dotnet >/dev/null 2>&1 ||
  SATIR+=("UYARI: dotnet yok — npm run contracts içeride derleme yapar, çalışmaz.")

# ── Açık borçlar (anayasa borç tablosu) ───────────────────────────────────────
BORC=()
if [ -f api/tests/Api.Tests/UnitTest1.cs ] &&
  ! grep -rqlE 'Assert\.' api/tests 2>/dev/null; then
  BORC+=("B1 (İlke III): Api.Tests hiçbir davranışı doğrulamıyor; web'de test script'i/config'i yok.")
fi
if ! [ -f web/.env.example ] && grep -qE 'https?://(localhost|127\.0\.0\.1)' web/src/App.tsx 2>/dev/null; then
  BORC+=("B2 (İlke VI): web/src/App.tsx API adresini literal taşıyor; .env.example yok.")
fi
if [ ${#BORC[@]} -gt 0 ]; then
  SATIR+=("Açık anayasa borçları — kapatmadan Faz 1'e geçilmez:")
  for b in "${BORC[@]}"; do SATIR+=("       $b"); done
fi

# ── Çıktı ─────────────────────────────────────────────────────────────────────
printf 'Anayasa oturum kontrolü (.specify/memory/constitution.md)\n'
for s in "${SATIR[@]}"; do printf '%s\n' "$s"; done
printf 'Aktif guardrail: İlke I, II, IV, V, VI, VII hook ile korunuyor (.claude/hooks/).\n'
printf 'İlke III (kapı testi) hook DEĞİLDİR — yargı gerektirir, PR incelemesinde denetlenir.\n'

exit 0
