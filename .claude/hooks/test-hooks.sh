#!/usr/bin/env bash
# Anayasa hook'ları test paketi.
#
# Her hook için hem BLOK hem PASS senaryosu vardır. Testler ÇIKIŞ KODUNU kontrol
# eder — mesaj metnine bakmak yeterli değildir (Anayasa İlke III: kapı ancak
# kırmızı olması gereken durumda kırmızı olduğu GÖRÜLDÜĞÜNDE kapıdır).
#
# Bloklayan her senaryoda mesaj formatı da denetlenir: son iki zorunlu satır
# ("DURMA GEREKÇESİ" ve "SEÇENEK OLARAK SUNMA") yoksa test düşer — o satırlar
# olmadan ajan "bu kuralı atlayayım mı?" diye seçenek sunar.
#
# Kullanım:  ./.claude/hooks/test-hooks.sh      → 0 (hepsi geçti) / 1 (düşen var)
set -uo pipefail

KOK="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOKS="$KOK/.claude/hooks"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
STDERR="$TMP/stderr"

GECTI=0
KALDI=0

# ── Yardımcılar ───────────────────────────────────────────────────────────────
j_write() { jq -nc --arg f "$1" --arg c "$2" '{tool_name:"Write",tool_input:{file_path:$f,content:$c}}'; }
j_edit() { jq -nc --arg f "$1" --arg c "$2" '{tool_name:"Edit",tool_input:{file_path:$f,old_string:"",new_string:$c}}'; }
j_bash() { jq -nc --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c}}'; }

# bekle <beklenen-kod> <ad> <hook> <json> [cwd] [proje_kok]
bekle() {
  local beklenen="$1" ad="$2" hook="$3" gjson="$4" dizin="${5:-$KOK}" pk="${6:-$KOK}" kod
  (cd "$dizin" && CLAUDE_PROJECT_DIR="$pk" printf '%s' "$gjson" | CLAUDE_PROJECT_DIR="$pk" "$HOOKS/$hook") \
    >"$TMP/stdout" 2>"$STDERR"
  kod=$?

  if [ "$kod" -ne "$beklenen" ]; then
    printf '  ✗ %-56s EXIT=%s (beklenen %s)\n' "$ad" "$kod" "$beklenen"
    sed 's/^/        | /' "$STDERR" | head -8
    KALDI=$((KALDI + 1))
    return
  fi

  # Bloklayan/uyaran mesajlarda format zorunlulukları
  if [ "$beklenen" -eq 2 ]; then
    if ! grep -q 'DURMA GEREKÇESİ yalnızca şudur:' "$STDERR" ||
      ! grep -q 'SEÇENEK OLARAK SUNMA' "$STDERR" ||
      ! grep -q 'KENDİ KENDİNE DÜZELT' "$STDERR"; then
      printf '  ✗ %-56s EXIT=%s ama mesaj formatı eksik\n' "$ad" "$kod"
      KALDI=$((KALDI + 1))
      return
    fi
  fi

  printf '  ✓ %-56s EXIT=%s\n' "$ad" "$kod"
  GECTI=$((GECTI + 1))
}

baslik() { printf '\n%s\n' "$1"; }

# ══ İlke I — üretilmiş dosyalar ═══════════════════════════════════════════════
baslik "İlke I — üretilmiş dosya elle düzenlenmez (block-generated-files.sh)"
H=block-generated-files.sh
bekle 2 "BLOK: contracts/Api.json yazılıyor" $H \
  "$(j_write "$KOK/contracts/Api.json" '{"openapi":"3.0.4"}')"
bekle 2 "BLOK: schema.d.ts düzenleniyor" $H \
  "$(j_edit "$KOK/packages/api-client-ts/src/schema.d.ts" 'export type X = 1;')"
bekle 2 "BLOK: göreli yol da yakalanır" $H \
  "$(j_write "contracts/Api.json" '{}')"
bekle 0 "PASS: index.ts elle yazılan cephedir" $H \
  "$(j_edit "$KOK/packages/api-client-ts/src/index.ts" 'export type OrderResponse = 1;')"
bekle 0 "PASS: C# kaynağı serbest" $H \
  "$(j_write "$KOK/api/src/Api/Endpoints/HealthEndpoints.cs" 'namespace Api.Endpoints;')"

# ══ İlke II — adlandırılmış yanıt tipi ════════════════════════════════════════
baslik "İlke II — TypedResults + sealed record (block-anonymous-response.sh)"
H=block-anonymous-response.sh
bekle 2 "BLOK: çıplak Results.Ok" $H \
  "$(j_write "$KOK/api/src/Api/Endpoints/OrderEndpoints.cs" \
    'app.MapGet("/orders", () => Results.Ok(new OrderResponse("x")));')"
bekle 2 "BLOK: TypedResults ama anonim tip" $H \
  "$(j_write "$KOK/api/src/Api/Endpoints/OrderEndpoints.cs" \
    'app.MapGet("/orders", () => TypedResults.Ok(new { id = 1, name = "x" }));')"
bekle 2 "BLOK: Results.NotFound" $H \
  "$(j_edit "$KOK/api/src/Api/Endpoints/OrderEndpoints.cs" 'return Results.NotFound();')"
bekle 0 "PASS: TypedResults + record (bugünkü /health)" $H \
  "$(j_write "$KOK/api/src/Api/Endpoints/HealthEndpoints.cs" \
    'app.MapGet("/health", () => TypedResults.Ok(new HealthResponse("healthy", "1.0.0", 1))).WithName("GetHealth");')"
bekle 0 "PASS: TypedResults.NoContent()" $H \
  "$(j_edit "$KOK/api/src/Api/Endpoints/OrderEndpoints.cs" 'return TypedResults.NoContent();')"
bekle 0 "PASS[FP]: uç nokta dışı satırda anonim tip (LINQ)" $H \
  "$(j_edit "$KOK/api/src/Api/Endpoints/OrderEndpoints.cs" \
    'var gruplar = kayitlar.Select(k => new { k.Id, k.Ad }).ToList();')"
bekle 0 "PASS[FP]: 'MyResults.Ok' benzeri tanımlayıcı" $H \
  "$(j_edit "$KOK/api/src/Api/Endpoints/OrderEndpoints.cs" 'var x = MyResults.Ok();')"
bekle 0 "PASS[FP]: kapsam dışı dosya (web)" $H \
  "$(j_write "$KOK/web/src/App.tsx" 'const r = Results.Ok(new { a: 1 });')"

# ══ İlke IV — katman sınırları ════════════════════════════════════════════════
baslik "İlke IV — katman referansı (block-layer-violation.sh)"
H=block-layer-violation.sh
DOM="$KOK/api/src/Domain/SemiOtonom.Domain.csproj"
APP="$KOK/api/src/Application/SemiOtonom.Application.csproj"
INF="$KOK/api/src/Infrastructure/SemiOtonom.Infrastructure.csproj"
PRG="$KOK/api/src/Api/Program.cs"

bekle 2 "BLOK: Domain'e ProjectReference" $H \
  "$(j_edit "$DOM" '<ItemGroup><ProjectReference Include="..\Application\SemiOtonom.Application.csproj" /></ItemGroup>')"
bekle 2 "BLOK: Domain'e PackageReference" $H \
  "$(j_edit "$DOM" '<ItemGroup><PackageReference Include="Newtonsoft.Json" Version="13.0.3" /></ItemGroup>')"
bekle 0 "PASS: Domain referanssız kalıyor" $H \
  "$(j_write "$DOM" '<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><TargetFramework>net10.0</TargetFramework></PropertyGroup></Project>')"

bekle 2 "BLOK: Application -> Infrastructure" $H \
  "$(j_edit "$APP" '<ItemGroup><ProjectReference Include="..\Infrastructure\SemiOtonom.Infrastructure.csproj" /></ItemGroup>')"
bekle 2 "BLOK: Application -> EF Core" $H \
  "$(j_edit "$APP" '<ItemGroup><PackageReference Include="Microsoft.EntityFrameworkCore" Version="10.0.0" /></ItemGroup>')"
bekle 2 "BLOK: Application -> Dapper" $H \
  "$(j_edit "$APP" '<PackageReference Include="Dapper" Version="2.1.0" />')"
bekle 0 "PASS: Application'ın bugünkü gerçek içeriği" $H \
  "$(j_write "$APP" "$(cat "$APP")")"
bekle 0 "PASS[FP]: Infrastructure EF Core alabilir" $H \
  "$(j_edit "$INF" '<PackageReference Include="Microsoft.EntityFrameworkCore" Version="10.0.0" />')"

bekle 2 "BLOK: Program.cs katman içine ulaşıyor" $H \
  "$(j_edit "$PRG" 'using SemiOtonom.Infrastructure.Persistence;')"
bekle 0 "PASS: Program.cs'in bugünkü gerçek içeriği" $H \
  "$(j_write "$PRG" "$(cat "$PRG")")"

# ══ İlke VI — sır ve adres ════════════════════════════════════════════════════
baslik "İlke VI — sır/adres literali (block-secrets.sh)"
H=block-secrets.sh
bekle 2 "BLOK: localhost adresi kaynakta" $H \
  "$(j_write "$KOK/web/src/features/Order/api.ts" 'fetch("http://localhost:5027/orders")')"
bekle 2 "BLOK: IP adresi kaynakta" $H \
  "$(j_edit "$KOK/api/src/Api/Program.cs" 'var url = "https://10.0.14.22:8443/token";')"
bekle 2 "BLOK: parola ataması" $H \
  "$(j_write "$KOK/api/src/Api/appsettings.json" '{"Db":{"Password":"Hunter2Hunter2"}}')"
bekle 2 "BLOK: bağlantı dizesi" $H \
  "$(j_edit "$KOK/api/src/Infrastructure/Db.cs" 'const string c = "postgres://admin:s3cretpw@db.internal:5432/app";')"
bekle 2 "BLOK: api key" $H \
  "$(j_edit "$KOK/web/src/lib/x.ts" 'const apiKey = "sk-live-9f2b7c1d4e8a";')"

bekle 0 "PASS[FP]: \"AccessTokenExpiration\": 3600" $H \
  "$(j_write "$KOK/api/src/Api/appsettings.json" '{"Jwt":{"AccessTokenExpiration": 3600,"RefreshTokenExpiration": 86400}}')"
bekle 0 "PASS[FP]: web/.env.example şablonu" $H \
  "$(j_write "$KOK/web/.env.example" 'VITE_API_BASE_URL=http://localhost:5027')"
bekle 0 "PASS[FP]: AGENTS.md localhost'u anıyor" $H \
  "$(j_edit "$KOK/AGENTS.md" 'API adresi `http://localhost:5027` olarak gömülü.')"
bekle 0 "PASS[FP]: launchSettings.json applicationUrl" $H \
  "$(j_write "$KOK/api/src/Api/Properties/launchSettings.json" '{"profiles":{"http":{"applicationUrl":"http://localhost:5027"}}}')"
bekle 0 "PASS[FP]: Api.http istek dosyası" $H \
  "$(j_write "$KOK/api/src/Api/Api.http" '@Api_HostAddress = http://localhost:5027')"
bekle 0 "PASS[FP]: vite.config.ts doküman linki" $H \
  "$(j_write "$KOK/web/vite.config.ts" '// https://vite.dev/config/
export default defineConfig({})')"
bekle 0 "PASS[FP]: components.json \$schema" $H \
  "$(j_write "$KOK/web/components.json" '{"$schema":"https://ui.shadcn.com/schema.json"}')"
bekle 0 "PASS[FP]: yer tutucu değer" $H \
  "$(j_edit "$KOK/web/src/lib/config.ts" 'const base = import.meta.env.VITE_API_BASE_URL ?? "${API_URL}";')"
bekle 0 "PASS: ortam değişkeninden okuyan doğru kod" $H \
  "$(j_write "$KOK/web/src/lib/config.ts" 'const u = import.meta.env.VITE_API_BASE_URL;
if (!u) throw new Error("VITE_API_BASE_URL tanımlı değil");
export const API_BASE_URL = u;')"

# ══ İlke VII — npm ci ═════════════════════════════════════════════════════════
baslik "İlke VII — npm install yasak (block-npm-install.sh)"
H=block-npm-install.sh
bekle 2 "BLOK: npm install" $H "$(j_bash 'npm install')"
bekle 2 "BLOK: npm i react-router" $H "$(j_bash 'npm i react-router')"
bekle 2 "BLOK: npm install --package-lock-only" $H "$(j_bash 'npm install --package-lock-only')"
bekle 2 "BLOK: npm update" $H "$(j_bash 'npm update')"
bekle 2 "BLOK: pnpm add" $H "$(j_bash 'pnpm add zod')"
bekle 2 "BLOK: zincirin ikinci komutunda" $H "$(j_bash 'npm ci && npm install foo')"
bekle 0 "PASS: npm ci" $H "$(j_bash 'npm ci')"
bekle 0 "PASS: npm run build --workspace web" $H "$(j_bash 'npm run build --workspace web')"
bekle 0 "PASS[FP]: global kurulum (-g)" $H "$(j_bash 'npm i -g typescript-language-server')"
bekle 0 "PASS[FP]: npm ls typescript" $H "$(j_bash 'npm ls typescript')"
bekle 0 "PASS[FP]: npm run contracts" $H "$(j_bash 'npm run contracts')"
bekle 0 "PASS[FP]: commit mesajında 'npm install'" $H \
  "$(j_bash 'git commit -m "docs: npm install yerine npm ci kullanın"')"
bekle 0 "PASS[FP]: heredoc gövdesinde 'npm install'" $H \
  "$(j_bash "cat <<'EOF' > NOT.md
Asla npm install çalıştırma.
EOF")"

# ══ İlke V — korumalı dal ═════════════════════════════════════════════════════
baslik "İlke V — korumalı dal (block-protected-branch.sh)"
H=block-protected-branch.sh
# main dalında gerçek bir depo kur (sahte dal adı değil, gerçek git durumu)
MAIN_REPO="$TMP/main-repo"
git init -q -b main "$MAIN_REPO"
FEAT_REPO="$TMP/feat-repo"
git init -q -b feat/x "$FEAT_REPO"

bekle 2 "BLOK: main üzerinde git commit" $H "$(j_bash 'git commit -m "x"')" "$MAIN_REPO"
bekle 2 "BLOK: main üzerinde git push" $H "$(j_bash 'git push')" "$MAIN_REPO"
bekle 2 "BLOK: hedefi main olan push" $H "$(j_bash 'git push origin main')" "$FEAT_REPO"
bekle 2 "BLOK: main'e force push" $H "$(j_bash 'git push --force origin main')" "$FEAT_REPO"
bekle 2 "BLOK: HEAD:main push" $H "$(j_bash 'git push origin HEAD:main')" "$FEAT_REPO"
bekle 2 "BLOK: gh pr merge --admin" $H "$(j_bash 'gh pr merge 7 --admin --squash')" "$FEAT_REPO"
bekle 2 "BLOK: ruleset zayıflatma" $H \
  "$(j_bash 'gh api repos/gebosoft/semi-otonom/rulesets/23933135 -X PATCH -f enforcement=disabled')" "$FEAT_REPO"
bekle 2 "BLOK: --no-verify" $H "$(j_bash 'git commit --no-verify -m "x"')" "$FEAT_REPO"

bekle 0 "PASS: özellik dalında commit" $H "$(j_bash 'git commit -m "feat(web): x"')" "$FEAT_REPO"
bekle 0 "PASS: özellik dalını itme" $H "$(j_bash 'git push -u origin feat/x')" "$FEAT_REPO"
bekle 0 "PASS[FP]: özellik dalında force-with-lease" $H "$(j_bash 'git push --force-with-lease')" "$FEAT_REPO"
bekle 0 "PASS[FP]: gh pr create --base main" $H "$(j_bash 'gh pr create --base main --fill')" "$FEAT_REPO"
bekle 0 "PASS[FP]: ruleset OKUMA" $H \
  "$(j_bash 'gh api repos/gebosoft/semi-otonom/rulesets/23933135')" "$FEAT_REPO"
bekle 0 "PASS[FP]: 'main' kelimesi geçen commit mesajı" $H \
  "$(j_bash 'git commit -m "docs: main korumasını anlat"')" "$FEAT_REPO"
bekle 0 "PASS: git status" $H "$(j_bash 'git status')" "$MAIN_REPO"

# ── Regresyon: heredoc gövdesi VERİDİR ────────────────────────────────────────
# Canlıda yaşandı: bu hook'ları anlatan PR'ın gövdesinde örnek olarak geçen
# 'git push --force origin main' satırı, hook tarafından gerçek komut sanıldı ve
# PR açılışı bloklandı. Yanlış pozitifin en pahalı türü: doğru işi engelliyor.
PR_HEREDOC=$(
  cat <<'DIS'
gh pr create --base main --body-file - <<'EOF'
Kanıt bloğu:
  6. İlke V   git push origin main                     EXIT=2
Özellik dalında git push --force-with-lease serbesttir.
EOF
DIS
)
bekle 0 "PASS[FP]: PR gövdesinde örnek komut geçiyor" $H \
  "$(j_bash "$PR_HEREDOC")" "$FEAT_REPO"
bekle 0 "PASS[FP]: commit mesajında 'git push --force'" $H \
  "$(j_bash 'git commit -m "docs: git push --force origin main neden yasak"')" "$FEAT_REPO"
bekle 2 "BLOK: heredoc ÖNCESİNDE gerçek ihlal" $H \
  "$(j_bash "git push --force origin main <<'EOF'
zararsız metin
EOF")" "$FEAT_REPO"

# ══ İlke I — cephe uyarısı (PostToolUse) ══════════════════════════════════════
baslik "İlke I — cephe eksik uyarısı (warn-facade-missing.sh)"
H=warn-facade-missing.sh
kur_fixture() { # kur_fixture <dizin> <index.ts içeriği>
  local d="$1"
  mkdir -p "$d/api/src/Api/Endpoints" "$d/packages/api-client-ts/src" "$d/contracts"
  printf '%s\n' 'app.MapGet("/orders", () => TypedResults.Ok(new OrderResponse("x"))).WithName("GetOrders");' \
    >"$d/api/src/Api/Endpoints/OrderEndpoints.cs"
  printf '%s\n' "$2" >"$d/packages/api-client-ts/src/index.ts"
  printf '{}\n' >"$d/contracts/Api.json"
}

FX_EKSIK="$TMP/fx-eksik"
kur_fixture "$FX_EKSIK" 'export type HealthResponse = paths["/health"]["get"];'
bekle 2 "UYARI: rota cephede yok" $H \
  "$(j_write "$FX_EKSIK/api/src/Api/Endpoints/OrderEndpoints.cs" 'x')" "$KOK" "$FX_EKSIK"

# mtime'ları AÇIKÇA damgala: aynı saniyede yazılan iki dosyada -nt karşılaştırması
# yanlış sonuç verir ve test sessizce yeşile döner.
FX_TAM="$TMP/fx-tam"
kur_fixture "$FX_TAM" 'export type OrderResponse = paths["/orders"]["get"];'
touch -t 203001010000 "$FX_TAM/contracts/Api.json" # sözleşme kaynaktan YENİ
bekle 0 "PASS: rota cephede var, sözleşme taze" $H \
  "$(j_write "$FX_TAM/api/src/Api/Endpoints/OrderEndpoints.cs" 'x')" "$KOK" "$FX_TAM"

FX_BAYAT="$TMP/fx-bayat"
kur_fixture "$FX_BAYAT" 'export type OrderResponse = paths["/orders"]["get"];'
touch -t 202001010000 "$FX_BAYAT/contracts/Api.json" # sözleşme kaynaktan ESKİ
bekle 2 "UYARI: sözleşme kaynaktan eski" $H \
  "$(j_write "$FX_BAYAT/api/src/Api/Endpoints/OrderEndpoints.cs" 'x')" "$KOK" "$FX_BAYAT"

bekle 0 "PASS[FP]: kapsam dışı dosya (web)" $H \
  "$(j_write "$KOK/web/src/App.tsx" 'x')"

# ══ SessionStart ══════════════════════════════════════════════════════════════
baslik "Oturum başı kontrol (session-check.sh)"
H=session-check.sh
bekle 0 "PASS: oturumu asla bloklamaz (gerçek depo)" $H '{"hook_event_name":"SessionStart","source":"startup"}'
if ! grep -q 'Anayasa oturum kontrolü' "$TMP/stdout"; then
  printf '  ✗ %-56s stdout boş/beklenmedik\n' "stdout bağlama eklenecek içeriği taşıyor"
  KALDI=$((KALDI + 1))
else
  printf '  ✓ %-56s\n' "stdout bağlama eklenecek içeriği taşıyor"
  GECTI=$((GECTI + 1))
fi

git -C "$MAIN_REPO" commit -q --allow-empty -m "init" 2>/dev/null || true
bekle 0 "PASS: main dalında da bloklamaz" $H \
  '{"hook_event_name":"SessionStart","source":"startup"}' "$MAIN_REPO" "$MAIN_REPO"
if grep -q "main'e doğrudan commit/push yasak" "$TMP/stdout"; then
  printf '  ✓ %-56s\n' "main dalında uyarı metni üretiliyor"
  GECTI=$((GECTI + 1))
else
  printf '  ✗ %-56s uyarı yok\n' "main dalında uyarı metni üretiliyor"
  KALDI=$((KALDI + 1))
fi

# ══ Özet ══════════════════════════════════════════════════════════════════════
printf '\n────────────────────────────────────────────────────────────\n'
printf 'Geçen: %d   Düşen: %d\n' "$GECTI" "$KALDI"
if [ "$KALDI" -ne 0 ]; then
  printf 'SONUÇ: BAŞARISIZ\n'
  exit 1
fi
printf 'SONUÇ: TAMAM\n'
exit 0
