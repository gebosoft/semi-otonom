#!/usr/bin/env bash
# Anayasa İlke IV — Katman sınırları proje referansı seviyesinde uygulanır.
#
# Bugünkü doğrulanmış durum:
#   Domain.csproj        → SIFIR referans (dosyada hiç ItemGroup yok)
#   Application.csproj   → yalnız Domain + 2 adet Microsoft.Extensions.*.Abstractions
#   Infrastructure.csproj→ Domain + Application; bilinçli olarak hiç EF Core yok
#   Program.cs           → yalnız AddApplication / AddInfrastructure
#
# Üç kural:
#   1) Domain'e HİÇBİR referans eklenemez
#   2) Application → Infrastructure veya veri erişim paketi eklenemez
#   3) Program.cs katman içindeki namespace'lere ulaşamaz
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

HOOK_JSON="$(cat)"
YOL="$(goreli_yol "$(alan '.tool_input.file_path')")"
[ -n "$YOL" ] || exit 0

ICERIK="$(degisen_icerik)"
[ -n "$ICERIK" ] || exit 0

VERI_PAKET='Microsoft\.EntityFrameworkCore|Microsoft\.Data\.SqlClient|Npgsql|Dapper|MongoDB\.|StackExchange\.Redis|Microsoft\.Extensions\.Caching\.StackExchangeRedis|RabbitMQ\.|Azure\.Storage|AWSSDK\.'

# ── Kural 1: Domain sıfır referanslı kalır ────────────────────────────────────
if [[ "$YOL" == api/src/Domain/*.csproj ]]; then
  BULGU="$(grep -nE '<(Project|Package)Reference' <<<"$ICERIK" || true)"
  if [ -n "$BULGU" ]; then
    blokla "IV" "Katman sınırları proje referansı seviyesinde uygulanır" \
      "Domain katmanına referans ekleniyor:
$(sed 's/^/    /' <<<"$BULGU")

Domain bugün SIFIR bağımlılıkla derleniyor; .csproj dosyasında hiç ItemGroup yok.
Anayasa: 'Yeni bir referans gerektiğinde varsayılan cevap referansı ekle değil,
SINIR YANLIŞ YERDE olmalıdır.'" \
      "gerçekten Domain'in bir dış tipe ihtiyacı olduğunu gösterebiliyorsan — bu bir sınır tasarımı kararıdır ve kullanıcıya sorulur." \
      "İhtiyacın olan tipi Domain'de bir arayüz olarak tanımla (örn. api/src/Domain/Repositories/ altındaki IUnitOfWork gibi)." \
      "Arayüzün implementasyonunu Infrastructure'a koy; referansı Infrastructure taşır." \
      "Domain.csproj'u değişmeden bırak."
  fi
fi

# ── Kural 2: Application yalnız Domain görür ──────────────────────────────────
if [[ "$YOL" == api/src/Application/*.csproj ]]; then
  KOTU_PROJE="$(grep -nE '<ProjectReference' <<<"$ICERIK" |
    grep -vE 'SemiOtonom\.Domain\.csproj' || true)"
  KOTU_PAKET="$(grep -nE '<PackageReference' <<<"$ICERIK" |
    grep -E "$VERI_PAKET" || true)"

  if [ -n "$KOTU_PROJE" ] || [ -n "$KOTU_PAKET" ]; then
    NEDEN="Application katmanına izinsiz referans ekleniyor."
    [ -n "$KOTU_PROJE" ] && NEDEN="$NEDEN

  Domain dışı proje referansı:
$(sed 's/^/    /' <<<"$KOTU_PROJE")"
    [ -n "$KOTU_PAKET" ] && NEDEN="$NEDEN

  Veri erişim paketi:
$(sed 's/^/    /' <<<"$KOTU_PAKET")"
    NEDEN="$NEDEN

Application bugün yalnız Domain'i ve iki Microsoft.Extensions.*.Abstractions
paketini görüyor. Sınır konvansiyonla değil derleyiciyle korunur: bir 'using'
satırı review'de gözden kaçar, bir ProjectReference .csproj diff'inde görünür."

    blokla "IV" "Katman sınırları proje referansı seviyesinde uygulanır" \
      "$NEDEN" \
      "katmanlamanın kendisinin değişmesi gerektiğini gösterebiliyorsan — bu mimari karardır, kullanıcıya sorulur ve ayrı commit'tir." \
      "İhtiyacın olan davranışı Application'da bir arayüz olarak tanımla (Application/Abstractions/)." \
      "Somut implementasyonu Infrastructure'a yaz; Infrastructure zaten Application'a referans veriyor." \
      "Bağlamayı Infrastructure'ın AddInfrastructure uzantısında yap." \
      "Application.csproj'a eklediğin referansı geri al."
  fi
fi

# ── Kural 3: Program.cs katman içine ulaşmaz ──────────────────────────────────
if [[ "$YOL" == "api/src/Api/Program.cs" ]]; then
  BULGU="$(grep -nE '^[[:space:]]*using[[:space:]]+SemiOtonom\.(Application|Infrastructure|Domain)\.' <<<"$ICERIK" |
    grep -vE '\.DependencyInjection;' || true)"
  if [ -n "$BULGU" ]; then
    blokla "IV" "Katman sınırları proje referansı seviyesinde uygulanır" \
      "Program.cs katman içindeki bir namespace'e ulaşıyor:
$(sed 's/^/    /' <<<"$BULGU")

Program.cs'in katman içine tek giriş noktası AddApplication ve AddInfrastructure'dır.
Bugün dosyada yalnızca bu iki uzantının namespace'i var." \
      "kompozisyon kökünün gerçekten yeni bir giriş noktasına ihtiyacı varsa — yeni bir Add* uzantısı tasarlamak mimari karardır, kullanıcıya sorulur." \
      "İhtiyacın olan kaydı ilgili katmanın DependencyInjection uzantısına taşı (ApplicationServiceCollectionExtensions veya InfrastructureServiceCollectionExtensions)." \
      "Program.cs'te yalnızca builder.Services.AddApplication(...) / AddInfrastructure(...) çağır." \
      "Eklediğin 'using' satırını kaldır."
  fi
fi

exit 0
