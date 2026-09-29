#!/usr/bin/env bash
# Anayasa İlke V — main'e giden tek yol PR'dır ve kapılar bypass edilmez.
#
# Ruleset 23933135 ("main protection", aktif, bypass_actors boş) dört kural
# işletiyor: pull_request, deletion, non_fast_forward, required_status_checks
# (contracts, api, web; strict). Sunucu zaten reddeder — bu hook ajanın oraya
# kadar gidip anlamsız bir hata almasını ve "acaba --admin ile mi geçsem" diye
# düşünmesini engeller.
#
# Dört durum:
#   1) main üzerindeyken commit/push
#   2) hedefi açıkça main olan push
#   3) main'e force push / history rewrite
#   4) kapı bypass girişimi (gh pr merge --admin, ruleset düzenleme, --no-verify)
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

HOOK_JSON="$(cat)"
KOMUT="$(alan '.tool_input.command')"
[ -n "$KOMUT" ] || exit 0

# symbolic-ref ÖNCE: 'git rev-parse --abbrev-ref HEAD' henüz commit'i olmayan bir
# depoda (unborn branch) hata verir ve dal boş kalırdı — yani hook sessizce
# geçerdi. Testte yakalandı; sessizce geçen kapı kapı değildir (İlke III).
DAL="$(git symbolic-ref --short HEAD 2>/dev/null ||
  git rev-parse --abbrev-ref HEAD 2>/dev/null ||
  printf '')"
KORUMALI='main|master'

ORTAK_DURMA="gerçekten main üzerinde çalışılması gereken bir depo bakımı varsa — bu kullanıcının kararıdır."

# ── 4) Kapı bypass girişimi (dalı önemsemez) ──────────────────────────────────
RULESET_YAZMA=0
if grep -qE 'gh[[:space:]]+api.*(rulesets|/protection)' <<<"$KOMUT" &&
  grep -qE '(-X|--method)[[:space:]]*(PATCH|PUT|POST|DELETE)' <<<"$KOMUT"; then
  RULESET_YAZMA=1
fi

if grep -qE 'gh[[:space:]]+pr[[:space:]]+merge.*--admin' <<<"$KOMUT" || [ "$RULESET_YAZMA" -eq 1 ]; then
  blokla "V" "main'e giden tek yol PR'dır ve kapılar bypass edilmez" \
    "Bu komut korumayı zayıflatmaya çalışıyor:

    $KOMUT

Anayasa: 'Bir PR'\''ı yeşile çevirmek için required check zayıflatılmamalı, devre
dışı bırakılmamalı veya ruleset'\''e bypass aktörü eklenmemelidir.' Ruleset bugün
bypass_actors: [] ile duruyor; current_user_can_bypass: never." \
    "kuralların kendisinin değişmesi gerekiyorsa — bu bir yönetişim kararıdır, kullanıcıya aittir ve anayasa değişikliğiyle birlikte AYRI commit'tir." \
    "Kırmızı check'i zayıflatmak yerine SEBEBİNİ düzelt: contracts → ./scripts/generate-contracts.sh; api → dotnet test api/Api.sln; web → npm run build --workspace web." \
    "Üç check de yeşilken normal yoldan merge et: gh pr merge --squash."
fi

if grep -qE 'git[[:space:]]+(push|commit).*--no-verify' <<<"$KOMUT"; then
  blokla "V" "main'e giden tek yol PR'dır ve kapılar bypass edilmez" \
    "--no-verify yerel kapıları atlıyor:

    $KOMUT

Atlanan kontrol kaybolmaz; CI'da ya da incelemede geri gelir. Anayasa İlke III:
bir kapı ancak kırmızı olabildiği görüldüğünde kapıdır — atlanan kapı kapı değildir." \
    "kancanın kendisi bozuksa (kod doğruyken bile hata veriyorsa) — kancayı düzeltmek ayrı bir iştir." \
    "--no-verify'ı komuttan çıkar ve kancanın söylediği şeyi düzelt." \
    "Kanca çıktısını oku; genelde tek bir somut düzeltme ister."
fi

# ── 3) main'e force push ──────────────────────────────────────────────────────
if grep -qE 'git[[:space:]]+push' <<<"$KOMUT" &&
  grep -qE '(--force([[:space:]]|=|$)|--force-with-lease|[[:space:]]-f([[:space:]]|$))' <<<"$KOMUT"; then
  if [[ "$DAL" =~ ^($KORUMALI)$ ]] || grep -qE "(^|[[:space:]:])($KORUMALI)([[:space:]]|$)" <<<"$KOMUT"; then
    blokla "V" "main'e giden tek yol PR'dır ve kapılar bypass edilmez" \
      "main'e force push / history rewrite girişimi:

    $KOMUT

Anayasa: 'main'\''e force push ve history rewrite YASAKTIR.' Ruleset'te
non_fast_forward kuralı zaten aktif; sunucu da reddeder." \
      "$ORTAK_DURMA" \
      "Yeni bir dal aç: git switch -c feat/<konu>" \
      "Değişikliği oraya taşı ve PR aç: gh pr create --base main" \
      "Özellik dalında geçmişi düzeltmen gerekiyorsa force-with-lease serbesttir — bu hook yalnızca main'i korur."
  fi
fi

# ── 2) Hedefi açıkça main olan push ───────────────────────────────────────────
if grep -qE "git[[:space:]]+push([[:space:]]+[^[:space:]]+)*[[:space:]]+($KORUMALI)([[:space:]]|$)" <<<"$KOMUT" ||
  grep -qE "git[[:space:]]+push.*HEAD:($KORUMALI)([[:space:]]|$)" <<<"$KOMUT"; then
  blokla "V" "main'e giden tek yol PR'dır ve kapılar bypass edilmez" \
    "Hedefi doğrudan main olan push:

    $KOMUT

Ruleset 23933135 pull_request kuralını işletiyor; bu push sunucuda da reddedilir.
main'in first-parent geçmişinde d59e210'dan bugüne inen her şey PR merge commit'i." \
    "$ORTAK_DURMA" \
    "Özellik dalını it: git push -u origin \$(git rev-parse --abbrev-ref HEAD)" \
    "PR aç: gh pr create --base main --fill" \
    "Üç required check (contracts, api, web) yeşilken merge et."
fi

# ── 1) main üzerindeyken commit/push ──────────────────────────────────────────
if [[ "$DAL" =~ ^($KORUMALI)$ ]] &&
  grep -qE '(^|[;&|][[:space:]]*|[[:space:]])git[[:space:]]+(commit|push|merge|rebase)([[:space:]]|$)' <<<"$KOMUT"; then
  blokla "V" "main'e giden tek yol PR'dır ve kapılar bypass edilmez" \
    "Şu an '$DAL' dalındasın ve şunu çalıştırmak üzeresin:

    $KOMUT

main korumalı bir daldır; üzerinde doğrudan commit birikmesi, sonradan mutlaka bir
dala taşınmayı gerektirir. Anayasa: 'main'\''e doğrudan push YAPILMAMALI.'" \
    "$ORTAK_DURMA" \
    "Önce dal aç — çalışma dizinindeki değişiklikler seninle taşınır: git switch -c feat/<konu>" \
    "Commit'i orada at ve dalı it: git push -u origin feat/<konu>" \
    "PR aç: gh pr create --base main --fill"
fi

exit 0
