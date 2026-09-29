#!/usr/bin/env bash
# Anayasa İlke VI — Sır ve ortama bağlı adres depoya girmez.
#
# Üç kalıp:
#   A) Ortama bağlı adres: http(s)://localhost|127.0.0.1|0.0.0.0|<IP>
#   B) Kimlik bilgisi ataması: password/secret/api_key/token = "<en az 8 karakter>"
#   C) Bağlantı dizesi: Server=...;Password=... veya proto://kullanıcı:parola@host
#
# MUAF YOLLAR — burada localhost adresi bulunması normaldir:
#   *.md                              → AGENTS.md, BACKLOG.md ve anayasa localhost:5027 anıyor
#   **/Properties/launchSettings.json → yerel geliştirme bağlaması buranın işidir
#   *.http                            → istek dosyası
#   *.example / *.template / *.sample → şablon; gerçek değer taşımaz
#   .claude/hooks/**                  → bu hook'lar ve testleri kalıpları örnek olarak içerir
#
# Bugünkü repoda bu kural TEK bir yere düşüyor: web/src/App.tsx:8 — yani B2 borcu.
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

HOOK_JSON="$(cat)"
YOL="$(goreli_yol "$(alan '.tool_input.file_path')")"
[ -n "$YOL" ] || exit 0

ICERIK="$(degisen_icerik)"
[ -n "$ICERIK" ] || exit 0

# ── Muafiyetler ───────────────────────────────────────────────────────────────
case "$YOL" in
*.example | *.template | *.sample | *.md | *.http) exit 0 ;;
*/Properties/launchSettings.json) exit 0 ;;
.claude/hooks/*) exit 0 ;;
esac

ADRES='https?://(localhost|127\.0\.0\.1|0\.0\.0\.0|\[::1\]|[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})'
ANAHTAR='(password|passwd|pwd|secret|api[_-]?key|apikey|access[_-]?token|refresh[_-]?token|client[_-]?secret|private[_-]?key|connection[_-]?string)'
# Anahtarın hemen ardından : veya = gelmeli. Bu çapa sayesinde
# "AccessTokenExpiration": 3600 EŞLEŞMEZ (ardından 'Expiration' geliyor).
# Değer TIRNAKLI ve en az 8 karakter olmalı; 3600 gibi sayılar eşleşmez.
KIMLIK="${ANAHTAR}\"?[[:space:]]*[:=][[:space:]]*[\"'][^\"']{8,}[\"']"
BAGLANTI='((Server|Data Source|Host)=[^;"'\'']+;.*(Password|Pwd)=|(postgres|postgresql|mysql|mongodb\+srv|mongodb|redis|amqp)://[^:/@"'\'' ]+:[^@"'\'' ]+@)'
# Gerçek değer değil, yer tutucu olan satırlar muaf.
YERTUTUCU='(\$\{|<[A-Za-z_]|xxx|XXX|changeme|change-me|CHANGEME|your[-_]|YOUR[-_]|\*\*\*|REPLACE|PLACEHOLDER|placeholder|example|EXAMPLE|dummy|TODO)'

suz() { grep -vE "$YERTUTUCU" || true; }

BULGU_A="$(grep -nE "$ADRES" <<<"$ICERIK" | suz)"
BULGU_B="$(grep -nEi "$KIMLIK" <<<"$ICERIK" | suz)"
BULGU_C="$(grep -nE "$BAGLANTI" <<<"$ICERIK" | suz)"

if [ -n "$BULGU_A" ] || [ -n "$BULGU_B" ] || [ -n "$BULGU_C" ]; then
  NEDEN="$YOL içinde İlke VI ihlali var."
  [ -n "$BULGU_A" ] && NEDEN="$NEDEN

  Ortama bağlı adres literali:
$(sed 's/^/    /' <<<"$BULGU_A")"
  [ -n "$BULGU_B" ] && NEDEN="$NEDEN

  Kimlik bilgisi ataması:
$(sed 's/^/    /' <<<"$BULGU_B")"
  [ -n "$BULGU_C" ] && NEDEN="$NEDEN

  Bağlantı dizesi:
$(sed 's/^/    /' <<<"$BULGU_C")"
  NEDEN="$NEDEN

Anayasa: adres ortam değişkeninden okunur, tek bir yerde okunur ve eksikse AÇIKÇA
hata fırlatır — sessizce undefined'a düşmez. Bugün depoda zaten bir ihlal var
(web/src/App.tsx:8, BACKLOG B2); ikincisini eklemek borcu büyütür."

  blokla "VI" "Sır ve ortama bağlı adres depoya girmez" \
    "$NEDEN" \
    "değer gerçek bir sırsa ve nereye konacağı belirsizse — sır deposu seçimi kullanıcı kararıdır, koda asla yazılmaz." \
    "web tarafı: web/src/lib/config.ts içinde import.meta.env.VITE_API_BASE_URL oku; yoksa throw et. Kullanan yerde o sabiti çağır." \
    "web/.env.example dosyasına anahtarı örnek değerle ekle (bu dosya muaftır, bloklanmaz)." \
    "api tarafı: IConfiguration üzerinden oku; gerçek değeri appsettings.Development.json'a koy — .gitignore:19 onu zaten yoksayıyor." \
    "Literali kaldır ve değişiklikten sonra: git check-ignore -v <dosya> ile sızıntı olmadığını doğrula."
fi

exit 0
