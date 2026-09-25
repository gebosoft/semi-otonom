# AGENTS.md

## Proje

semi-otonom; .NET 10 minimal API (`api/`), OpenAPI'den üretilen paylaşımlı tip paketi
(`packages/api-client-ts`) ve React 19 + Vite ön yüzünden (`web/`) oluşan tek depodur.
API, Clean Architecture ile katmanlanır (Domain / Application / Infrastructure / Api).
JS tarafı npm workspaces kullanır; geçerli lock dosyası köktekidir. Bugün gerçek olan tek
uç nokta `/health` — geri kalan, ilk özellik için önceden kurulmuş iskelettir. Depodaki
commit mesajları, kod yorumları ve script çıktıları Türkçedir; tanımlayıcılar ve genel API
yüzeyi İngilizce.

## Komutlar

Ön koşul: .NET SDK 10.0.101 (`global.json` sabitler), Node 22 (CI'de sabit).

| İş | Komut |
|---|---|
| Kurulum | `npm ci` (kökten) |
| Sözleşme üretimi | `npm run contracts` |
| Sözleşmeler güncel mi | `npm run contracts:check` |
| API derleme | `dotnet build api/Api.sln` |
| API test | `dotnet test api/Api.sln` |
| Web derleme + tip kontrolü | `npm run build --workspace web` |
| İstemci tip kontrolü | `npm run typecheck --workspace @semi-otonom/api-client` |
| Web lint | `npm run lint --workspace web` |
| Geliştirme | `npm run dev --workspace web` + `dotnet run --project api/src/Api` |

CI (`.github/workflows/ci.yml`) üç paralel job çalıştırır: `contracts` →
`./scripts/check-contracts.sh`; `api` → `dotnet restore/build/test api/Api.sln`; `web` →
`npm ci`, istemci `typecheck`, `build --workspace web`.
CI **lint çalıştırmaz** ve **hiçbir JS testi çalıştırmaz**; kök seviyede `build`/`test`/`lint`
script'i yoktur. Bunları yerelde siz yürütün.

## Mimari — sözleşme zinciri

C# uç noktası → (derleme sırasında) `contracts/Api.json` → openapi-typescript →
`packages/api-client-ts/src/schema.d.ts` → `web`.

1. `api/src/Api/Api.csproj` içindeki `OpenApiGenerateDocuments` sayesinde Api projesinin her
   derlenişi OpenAPI belgesini `contracts/` altına yazar. Elle yazılan bir spec dosyası
   yoktur; kaynak kod tek gerçektir.
2. `packages/api-client-ts` bu belgeden yalnızca **tip** üretir — çalışma zamanı istemcisi
   yok. Paket derlenmez, `main`/`types` doğrudan TS kaynağını gösterir, Vite onu okur.
   `src/index.ts` elle yazılmış cephedir; okunabilir takma adlar orada tanımlanır.
3. `web` tipleri `@semi-otonom/api-client` üzerinden alır.

Neden böyle: sözleşme uyumsuzluğu çalışma zamanında değil, derleme zamanında patlasın diye.
Üretilmiş dosyalar (`contracts/Api.json`, `schema.d.ts`) **depoya işlenir** — böylece
sözleşme değişikliği diff'te görünür ve CI eskimiş üretimi yakalayabilir:
`check-contracts.sh` üretimi yeniden koşturup sonucu diff'ler, fark varsa `exit 1`.

## Sembol arama

Sembol tanımı/kullanımı ararken grep yerine LSP kullanın (`goToDefinition`,
`findReferences`, `documentSymbol`) — grep yorum, Markdown ve ölü kodda yanlış pozitif
üretir, sözleşme zincirini (`web` → `api-client` → `schema.d.ts`) ise hiç takip edemez.
Plugin'ler `.claude/settings.json`'da açıktır, ama **sunucular makine seviyesindedir**;
depoyu ilk klonlayan bir kez kurar: `dotnet tool install --global csharp-ls` ve
`npm i -g typescript-language-server`. Eksikse LSP `ENOENT` döndürür.
C# boş dönüyorsa sunucu kök `semi-otonom.sln` yokken başlamıştır: `pkill csharp-ls` yeterli.

## Konvansiyonlar

- Commit: Conventional Commits, Türkçe küçük harfli özet — `feat(web): ...`, `fix(ci): ...`.
  Dal adları `feat/...`, `fix/...`. `main`'e PR ile girilir (ruleset korumalı).
- Katman sınırları sert: Domain hiçbir şeye referans vermez; Application yalnız Domain'e
  bakar (Infrastructure'a ve EF Core'a asla); `Program.cs` katman içini bilmez — tek giriş
  noktaları `AddApplication` / `AddInfrastructure`. Yeni referans gerekiyorsa sınır yanlış
  yerdedir.
- Beklenen iş kuralı hataları için `Result<T>` / `Error` döndürülür; exception akış kontrolü
  aracı değildir. (`Result`/`Error` → HTTP eşlemesi henüz yok; ilk özellikte yazılacak.)
- Kimlikler `Guid.CreateVersion7()` ile üretilir. `Entity` append-only kayıtlar,
  `AuditableEntity` güncellenebilir kayıtlar içindir; `UpdatedAt` interceptor'da damgalanır.
- **Her uç nokta named bir response type döndürür**: `Results.Ok` değil `TypedResults.Ok`,
  anonim tip değil `record`. Anonim tip OpenAPI şemasına çıkmaz; istemci tipleri `undefined`
  olur ve sözleşme zinciri sessizce işlevsizleşir.
- Uç nokta yazımı: `static class *Endpoints` + `IEndpointRouteBuilder` uzantısı.
  `WithName(...)` değeri OpenAPI `operationId`'sidir ve TS tarafında anahtar olur.
- **Bir kapı (CI check, hook, script) yazıldığında bilerek bozularak test edilir ve ÇIKIŞ
  KODU kontrol edilir** (`echo $?`). Yeşil geçmesi kapının çalıştığını kanıtlamaz:
  `check-contracts.sh` bir dönem farkı buluyor, "HATA" yazıyor, ama `exit 1` içermediği için
  CI her durumda yeşil geçiyordu. Kapı ancak kırmızı olması gereken durumda kırmızı olduğu
  görüldüğünde kapıdır.
- Soyutlamayı üçüncü tekrarda ekleyin, tahminle değil.
- Web klasör yapısı feature bazlıdır (`vite-react-best-practices/react-colocation`):
  `src/features/<Alan>/` içine o özelliğin bileşenleri, hook'ları ve yardımcıları
  birlikte konur. Paylaşılan, elle yazılmış bileşenler `src/components/`; `components/ui/`
  shadcn üretimidir, oraya elle dosya eklenmez.
- Skill'ler `.claude/skills/` altında yaşar; ilgili tarafta kod yazmadan ya da
  incelemeden önce bakın:
  - `dotnet-backend-patterns` — .NET yazarken (katman yapısı, Result, entity, EF/Dapper)
  - `dotnet-code-review` — .NET incelerken (fix-before-merge / should-fix / nit ayrımı)
  - `vite-react-best-practices` — web tarafında (Vite SPA, route splitting, VITE_ env,
    server state). Next.js DEĞİL — SSR/RSC/`next/*` kuralları bu repoda geçersizdir.
- **İki çözüm dosyası var, ikisi de kasıtlı.** Derlemenin ve CI'ın hedefi `api/Api.sln`'dir;
  komutlarda onu kullanın. Kökteki `semi-otonom.sln` yalnızca araçlar içindir: C# dil
  sunucusu (csharp-ls) çözümü çalışma alanı **kökünde** arar, bulamazsa hiçbir sembol
  döndürmez. İkisi de aynı beş projeyi referanslar; proje ekler/çıkarırsanız ikisini de
  güncelleyin.

## Dokunma listesi

- `contracts/Api.json` ve `packages/api-client-ts/src/schema.d.ts` — üretilmiş dosyalar.
  Elle düzenlemeyin: `./scripts/generate-contracts.sh && git add -A`.
- Api projesinin adı ve `Api.csproj` içindeki `OpenApi*` özellikleri — assembly adı çıktı
  dosya adını, OpenAPI başlığını ve `tags[0].name`'i belirler; yeniden adlandırma zinciri
  kırar. `OpenApiDocumentsDirectory` göreli yolu projenin konumuna bağlıdır.
- `Program.cs` içindeki `AddSchemaTransformer` ve OpenAPI 3.0 sabitlemeleri — zorunlu.
- `scripts/generate-contracts.sh` içindeki `--no-incremental` bayrağı — zorunlu, aşağıya
  bakın.
- Var olan `WithName(...)` değerleri — değişirse üretilmiş TS anahtarları kayar.
- `global.json` ve `ci.yml` sürüm sabitleri — oynatmadan önce sorun.

## Bilinen tuzaklar

- **En sık kırmızı veren yer sözleşme kapısıdır.** API'de şema veya uç nokta değiştirdiyseniz
  `npm run contracts` çalıştırıp üretilenleri de commit'leyin; yoksa `contracts` job'ı düşer.
- **`--no-incremental` zorunludur.** Artımlı derleme OpenAPI belgesini yeniden yazmaz;
  `generate-contracts.sh` eski belgeyi kullanır, üretilenler kaynakla tutarlı görünür ve
  kapı yanlış yere yeşil geçer. Bu, kapının sessizce işlevsizleştiği iki durumdan biridir
  (diğeri eksik `exit 1`).
- **OpenAPI sürümü ve schema transformer FARKLI mekanizmalardır.** Sürüm ayarı
  (`AddOpenApi(o => o.OpenApiVersion = ...)`) yalnızca runtime `/openapi/v1.json` uç noktasını
  etkiler; derleme zamanı üretimi `Api.csproj`'daki `OpenApiGenerateDocumentsOptions
  --openapi-version` ile ayarlanır. Ama `AddSchemaTransformer` derleme zamanına DA geçer.
  Sürüm bu yüzden iki yerde, transformer tek yerde tanımlıdır — ikisi de silinmemeli.
- **Neden 3.0 ve neden transformer:** .NET 10 tüm tamsayı alanlarını `Integer|String` flag
  birleşimi olarak modeller (şablon projede bile — dotnet/aspnetcore#64501). Bu 3.1'de
  `"type": ["integer","string"]`, 3.0'da `anyOf` olarak serileşir; kod üreteçleri ikisini de
  ya string'e düşürür ya da bozuk tip üretir. Sürüm düşürmek tek başına çözmez; transformer
  şarttır.
- **Araç sürümleri sabitlenir.** `global.json` (SDK), `package-lock.json` (npm), tam sürüm
  (`openapi-typescript`). Aynı girdiden farklı çıktı üreten bir kapı, kapı değildir.
- `npm run contracts` içeride **dotnet derlemesi** yapar — Node-only bir ortamda çalışmaz.
- `web/src/components/ui/` shadcn/ui'nin ürettiği koddur; `react-refresh/only-export-components`
  o klasör için `eslint.config.js`'te kapalıdır. Dışarıda kural aktiftir — elle yazdığınız
  bileşenleri oraya koymayın.
- TypeScript **tek sürüm** olarak kökte sabitlenmiştir (`~6.0.2`); workspace'ler ve dil
  sunucusu aynı derleyiciyi kullanır. Kök `devDependencies`'teki girdiyi silmeyin — npm o
  zaman `openapi-typescript`'in `^5.x` peer'i yüzünden köke 5.x indirir. `npm ls typescript`
  "invalid" uyarısı beklenendir; üretim TS 6 ile doğrulanmıştır.
- Kökte ve `web/` altında iki `package-lock.json` var; geçerli olan **köktekidir**. npm
  komutlarını kökten `--workspace` ile çalıştırın.

## Açık işler

Bunlar bilinen eksiklerdir; `BACKLOG.md` ile senkron tutulur, çözülünce buradan silinir.

- API adresi `web/src/App.tsx` içinde gömülü (`http://localhost:5027`); `VITE_*` ortam
  değişkeni ve `.env.example` yok.
- `@tanstack/react-query` ve `react-router` kurulu ama hiçbir yerden import edilmiyor —
  provider ve router yok.
- **Çalıştırılabilir test yok.** Web'de `vitest` kurulu ama `test` script'i, config'i ve tek
  bir test dosyası yok; `Api.Tests` boş bir placeholder `[Fact]`'ten ibaret. Yani CI'daki
  `api` job'ı bugün hiçbir şey doğrulamıyor.
- Ölü artıklar: iki `openapitools.json` (kullanılan araç openapi-typescript),
  `Api.http` içindeki `/weatherforecast/`, `.gitignore`'daki Flutter satırları.