
# semi-otonom Anayasası

Bu belge `AGENTS.md`'yi tekrar etmez. `AGENTS.md` "bu proje nasıl çalışır" sorusunu
cevaplar; bu belge "neye asla izin verilmez" sorusunu cevaplar. İkisi çeliştiğinde bu
belge üstündür ve `AGENTS.md` düzeltilir.

Buradaki her iddia, 2026-09-29 tarihinde depo üzerinde dosya okunarak veya komut
çalıştırılarak doğrulanmıştır. Kanıt satırları ve komut çıktıları ilkelerin içindedir;
bir ilkeyi değiştirmek isteyen önce kanıtını yeniden üretmek zorundadır.

## Core Principles

### I. Sözleşme zinciri tek yönlüdür

Üretilmiş dosyalar (`contracts/Api.json`, `packages/api-client-ts/src/schema.d.ts`) **elle
düzenlenmemeli (MUST NOT)**. C# kaynağını değiştiren her commit, üretilmiş çıktıyı **aynı
commit içinde** yeniden üretip işlemek zorundadır (MUST). Yeni bir uç nokta eklendiğinde
`packages/api-client-ts/src/index.ts` içine o uç noktanın yanıt tipi için okunabilir bir
takma ad eklenmesi **zorunludur (MUST)**.

**Kanıt.** Üretim `api/src/Api/Api.csproj:13-15` içindeki `OpenApiGenerateDocuments` ile
derleme zamanında tetikleniyor; elle yazılmış spec yok. Kapı doğrulandı: `HealthResponse`
kaydına bir alan eklenip `./scripts/check-contracts.sh` çalıştırıldığında çıktı
`+ probe: string` farkını basıp `EXIT=1` döndü; kaynak geri alınıp üretim tazelendiğinde
`✓ Sözleşmeler güncel` ve `EXIT=0`.

Takma ad kuralının kanıtı ayrıca üretildi: `/health` anonim tipe çevrildiğinde
`packages/api-client-ts/src/index.ts:8` satırı `TS2339: Property 'application/json' does
not exist on type 'undefined'` hatası verdi. Yani zincirin sessizce kopmasını fark eden
tek mekanizma, elle yazılmış cephedeki dereference'tır.

**Gerekçe.** Bu kural olmasaydı sözleşme uyumsuzluğu derleme zamanında değil, kullanıcının
tarayıcısında ortaya çıkardı. Takma ad zorunluluğu olmasaydı, cephe tarafından
dereference edilmeyen bir uç noktanın kaybolan şeması hiçbir yerde hata üretmez; `web` job'ı
yeşil kalır ve istemci tipi sessizce `never` olur.

### II. Her uç nokta adlandırılmış yanıt tipi döndürür

Uç noktalar `TypedResults` ve `sealed record` **kullanmalı (MUST)**; anonim tip veya
`Results.Ok(new { ... })` **kullanılmamalı (MUST NOT)**. Hata yanıtları da bu kuralın
kapsamındadır: `Result<T>` → HTTP eşlemesi yazıldığında hata gövdesi de adlandırılmış bir
`record` olmalıdır (MUST).

**Kanıt.** `api/src/Api/Endpoints/HealthEndpoints.cs:7,14` bugün kurala uyuyor. Kural
deneysel olarak doğrulandı: aynı uç nokta `Results.Ok(new { status, version, state })`
biçimine çevrilip `./scripts/generate-contracts.sh` çalıştırıldığında `contracts/Api.json`
içindeki 200 yanıtı yalnızca `{"description": "OK"}`'e indi, `components` nesnesi `{}`
oldu ve üretilen TypeScript `content?: never` üretti — buna rağmen üretim komutu `EXIT=0`
döndü.

**Gerekçe.** Bu kural olmasaydı bir uç nokta çalışır, `/health` doğru JSON döndürür,
sözleşme kapısı yeşil geçer — ama istemci o yanıtın alanlarını tipte hiç göremezdi. Kapının
yeşil kalması, kaybın sessiz olduğu anlamına gelir; ilke bu yüzden kapıya değil koda
bağlanmıştır.

### III. Kapı, kırmızı olduğu görülene kadar kapı değildir

Yeni bir CI job'ı, script, hook veya test eklendiğinde; **bilerek bozulup ÇIKIŞ KODUNUN 1
olduğu gözlenmeli (MUST)** ve bu gözlem PR açıklamasına yazılmalıdır (MUST). Çıkış kodu
doğrulanmamış bir kapı merge **edilmemeli (MUST NOT)**. Hiçbir test yalnızca "derleniyor"
diye kabul **edilmemelidir (MUST NOT)**.

**Kanıt — çalışan kapı.** `scripts/check-contracts.sh:27` `exit 1` içeriyor ve yukarıda
İlke I'de kırmızı olduğu görüldü.

**Kanıt — yeşil ama koruma sağlamayan kapı.** `api/tests/Api.Tests/UnitTest1.cs:5-9` gövdesi
boş bir `[Fact]`. `dotnet test api/Api.sln` çıktısı: `Passed! - Failed: 0, Passed: 1,
Skipped: 0, Total: 1, Duration: 2 ms`. Yani CI'ın `api` job'ı (`.github/workflows/ci.yml:43`)
bugün hiçbir davranışı doğrulamıyor. `Api.Tests.csproj:10-15` içinde
`Microsoft.AspNetCore.Mvc.Testing` yok, dolayısıyla `WebApplicationFactory` henüz
kullanılamaz durumda.

**Gerekçe.** Bu kural olmasaydı — ve bir kez olmadı — `check-contracts.sh` farkı bulup
"HATA" yazar, `exit 1` içermediği için CI yeşil geçerdi (commit `8fb270c`,
"fix(ci): kapıya exit 1 eklendi"). Yeşil bir kapı, korumadığını kanıtlamaz; yalnızca
kırmızı olabildiği görülmüş bir kapı korur.

### IV. Katman sınırları proje referansı seviyesinde uygulanır

`Domain` projesine **hiçbir** `ProjectReference` veya `PackageReference`
**eklenmemeli (MUST NOT)**. `Application` yalnızca `Domain`'e referans **vermeli (MUST)**;
`Infrastructure`'a, EF Core'a veya herhangi bir veri erişim paketine referans
**vermemeli (MUST NOT)**. `Program.cs` katman içindeki tiplere **ulaşmamalı (MUST NOT)**;
tek giriş noktaları `AddApplication` ve `AddInfrastructure`'dır.

**Kanıt.** `api/src/Domain/SemiOtonom.Domain.csproj` bugün sıfır referansla derleniyor
(dosyada hiç `ItemGroup` yok). `api/src/Application/SemiOtonom.Application.csproj:11-19`
yalnızca `Domain` proje referansı ve iki `Microsoft.Extensions.*.Abstractions` paketi
taşıyor. `api/src/Infrastructure/SemiOtonom.Infrastructure.csproj:20-23` bilinçli olarak
hiç EF Core paketi içermiyor. `api/src/Api/Program.cs:29-30` yalnızca iki uzantı metodunu
çağırıyor.

**Gerekçe.** Sınır konvansiyonla değil, derleyiciyle korunur. Bir `using` satırı code review'de
gözden kaçar; bir `ProjectReference` `.csproj` diff'inde görünür ve tartışma konusu olur.
Bu kural olmasaydı `Application` içinde bir `DbContext` görmek için bir özelliğin
yazılmasını beklemek gerekirdi — geri almanın en pahalı olduğu an.

Yeni bir referans gerektiğinde varsayılan cevap "referansı ekle" değil, **"sınır yanlış
yerde"** olmalıdır; referans ancak PR'da gerekçelendirilerek eklenir.

### V. main'e giden tek yol PR'dır ve kapılar bypass edilmez

`main`'e doğrudan push **yapılmamalı (MUST NOT)**. Bir PR'ı yeşile çevirmek için required
check zayıflatılmamalı, devre dışı bırakılmamalı veya ruleset'e bypass aktörü
**eklenmemelidir (MUST NOT)**. `main`'e force push ve history rewrite **yasaktır (MUST NOT)**.

**Kanıt.** Ruleset `23933135` ("main protection", `enforcement: active`,
`bypass_actors: []`, `current_user_can_bypass: never`) `~DEFAULT_BRANCH` üzerinde üç kural
işletiyor: `deletion`, `non_fast_forward` ve `required_status_checks` — sonuncusu
`contracts`, `api`, `web` context'lerini `strict_required_status_checks_policy: true` ile
zorunlu kılıyor. `main`'in first-parent geçmişinde `d59e210`'dan bugüne inen her şey PR
merge commit'i; doğrudan inen tek üç commit depo kurulumuna ait (`157797f`, `33a34d9`,
`f261b69`).

**Gerekçe.** Bu kural olmasaydı sözleşme, katman ve test kapılarının hiçbirinin anlamı
kalmazdı: üç ilke de yalnızca CI çalıştığı sürece geçerlidir, CI ise yalnızca PR akışında
tetiklenir (`.github/workflows/ci.yml:3-6`).

### VI. Sır ve ortama bağlı adres depoya girmez

Kimlik bilgisi, anahtar, bağlantı dizesi veya ortama göre değişen adres kaynak koda
**gömülmemeli (MUST NOT)**; ortam değişkeninden okunmalıdır (MUST). Ortam değişkeni tek bir
yerde okunmalı ve eksik olduğunda **açıkça hata fırlatmalıdır (MUST)** — sessizce
`undefined` veya boş dizeye düşmemelidir (MUST NOT). Depoya bir `.env` ya da gerçek değer
taşıyan bir `appsettings.*.json` **commit edilmemelidir (MUST NOT)**.

**Kanıt.** `.gitignore:18-21` bugün `.env`, `.env.local`, `*.Development.json` ve
`*.Production.json` kalıplarını taşıyor; `git ls-files` çıktısında hiçbir `.env` ve hiçbir
`*.Development.json` takip edilmiyor. `api/src/Api/appsettings.json` yalnızca log seviyesi
ve `AllowedHosts` içeriyor — bugün sır yok.

**Bilinen iki boşluk — borç olarak kayıtlı.**
1. `web/src/App.tsx:8` API adresini literal olarak taşıyor (`http://localhost:5027`);
   `VITE_*` değişkeni ve `.env.example` yok. Bu `BACKLOG.md` B2'dir ve Faz 1'den önce
   kapatılmalıdır.

**Gerekçe.** Bugün gömülü olan tek şey zararsız bir localhost adresi. Ama ilk gerçek
özellikte her çağrı bu adresi kullanacak; literal dağıldıktan sonra toplamak, tek noktada
kurmaktan pahalıdır. Sır yönetiminin zemini, henüz sır yokken atılır — sır geldikten sonra
değil.

### VII. Belirlenimcilik: aynı girdi aynı çıktıyı üretir

Sözleşme üretimi ve CI, kilitli bağımlılıklarla **çalışmalıdır (MUST)**: CI ve sözleşme
üretimi öncesi `npm ci` kullanılmalı, `npm install` **kullanılmamalıdır (MUST NOT)**.
`package-lock.json` ve `global.json` her değişiklikte commit **edilmelidir (MUST)**. Üretim
komutu, kaynak değişmediği halde farklı çıktı verebiliyorsa o komut **düzeltilmeden
kullanılmamalıdır (MUST NOT)**.

**Kanıt.** `.github/workflows/ci.yml:28,54` her iki job'da `npm ci` çalıştırıyor.
`global.json` SDK'yı `10.0.101` olarak sabitliyor. `scripts/generate-contracts.sh:9`
`--no-incremental` ile derliyor. `packages/api-client-ts/package.json:13` üreteci caret'sız
`"7.13.0"` olarak sabitliyor — yani belirlenimcilik yalnızca kilit dosyasına değil, spec'e de
yazılmış durumda; `npm install` çalıştıran biri de aynı üreteci alır.

Kapı bu haliyle iki yönlü doğrulandı: temiz ağaçta `./scripts/check-contracts.sh` → `EXIT=0`;
`HealthResponse` kaydına bir alan eklendiğinde → `EXIT=1`; kaynak geri alınıp üretim
tazelendiğinde `EXIT=0` ve `git diff contracts packages/api-client-ts/src` boş. `npm ci`
temiz çalışıyor, `openapi-typescript` 7.13.0'a, kök `typescript` 6.0.3'e çözülüyor.

**Gerekçe.** Artımlı derleme OpenAPI belgesini yeniden yazmayabilir; o durumda
`generate-contracts.sh` eski belgeyi TypeScript'e verir, üretilenler kaynakla tutarlı
*görünür* ve `check-contracts.sh` fark bulamaz. Bu, İlke III'ün tarif ettiği sessiz
işlevsizleşmenin ikinci biçimidir: kapı çalışır, kırmızı olabilir, ama yanlış girdiye bakar.

## Doğrulama Sınırları ve Borç Kaydı

Bir anayasa, neyi koruduğu kadar **neyi korumadığını** da açıkça söylemek zorundadır.
Aşağıdaki liste bugün itibarıyla doğrulanmıştır ve her PR'da bu sınırların dışına
çıkılmadığı varsayılamaz.

CI bugün şunları **doğrulamaz**:

- **Hiçbir davranışı.** `api` job'ı boş bir `[Fact]` çalıştırıyor (İlke III kanıtı).
- **Hiçbir JS testini.** `web/package.json:6-11` içinde `test` script'i yok; `web/` altında
  `vitest.config.*` yok; `find web/src packages -name "*.test.*" -o -name "*.spec.*"` boş
  dönüyor. `vitest`, `jsdom` ve `@testing-library/*` kurulu ama kullanılmıyor.
- **Lint'i.** `.github/workflows/ci.yml:45-56` `web` job'ında `npm run lint` yok. Kökte
  `lint` script'i de yok (`package.json:8-11`). Lint yalnızca yerelde çalışır.
- **PR incelemesini.** İlke V'teki `pull_request` kuralı boşluğu.

Açık borçlar ve bağlı oldukları ilkeler:

| Kod | Borç | İlke | Kaynak |
|---|---|---|---|
| B1 | Çalıştırılabilir test yok | III | `BACKLOG.md` |
| B2 | API adresi koda gömülü, `.env.example` yok | VI | `BACKLOG.md` |
| B6 | `Result<T>` → HTTP eşlemesi yok | II | `BACKLOG.md` |

`B1` ve `B2` ilk gerçek özellikten (Faz 1) önce **kapatılmalıdır (MUST)**. `D3` ve `D4` bir
sonraki altyapı PR'ında kapatılmalıdır (MUST); `D3` depo ayarında, `D4` tek satırlık bir
`.gitignore` değişikliğidir.

Kapanmış borçlar (v1.0.1): **D1** — `generate-contracts.sh:9` artık `--no-incremental`
taşıyor; **D2** — `openapi-typescript` spec'i `^7.13.0` yerine `7.13.0`. İkisi de
`AGENTS.md`'nin zaten iddia ettiği durumdu; kod belgeye çekildiği için `AGENTS.md`
değiştirilmedi.
(v1.0.2): **D3** — ruleset'e pull_request kuralı eklendi; **D4** — .gitignore .env* + !.env.example

## Değişiklik Akışı

Bir dalın PR'a dönüşebilmesi için aşağıdakiler yerine getirilmiş **olmalıdır (MUST)**:

1. API şeması veya uç nokta değiştiyse `npm run contracts` çalıştırılmış ve üretilenler
   **aynı commit'e** eklenmiştir. `npm run contracts:check` yerelde `EXIT=0` vermelidir.
2. Yeni uç nokta eklendiyse `WithName(...)` verilmiş, yanıt adlandırılmış `record` olarak
   tanımlanmış ve `packages/api-client-ts/src/index.ts` cephesine takma adı eklenmiştir.
3. Yeni bir kapı eklendiyse bilerek bozulmuş, `echo $?` ile **1** görülmüş ve bu çıktı PR
   açıklamasına yapıştırılmıştır.
4. `.csproj` dosyalarına referans eklendiyse İlke IV gerekçesi PR açıklamasında yazılıdır.
5. Yerelde `dotnet build api/Api.sln`, `npm run build --workspace web` ve
   `npm run lint --workspace web` çalıştırılmıştır — sonuncusu CI'da koşmadığı için bu
   adım atlanamaz.
6. Proje eklendi/çıkarıldıysa hem `api/Api.sln` hem kökteki `semi-otonom.sln` güncellenmiştir;
   ikisi de aynı beş projeyi referanslamaya devam eder (bugün doğrulandı).

Commit mesajları Conventional Commits ve Türkçe küçük harfli özet biçimindedir.
`main`'in first-parent geçmişindeki `fe821d5` ("rm") ve `44da149` ("react skill") bu kurala
uymaz; bunlar geçmişte kalmış ihlallerdir, emsal **değildir**.

## Governance

Bu anayasa depodaki diğer tüm pratiklerin üstündedir. `AGENTS.md`, skill dosyaları veya bir
code review yorumu bu belgeyle çeliştiğinde bu belge geçerlidir; çelişen taraf düzeltilir.

### Sürümleme

Anayasa semantik sürümlenir. Sürüm numarası uygulama sürümünden bağımsızdır.

- **MAJOR** — bir ilke kaldırıldığında, bir yasak serbest bırakıldığında veya bir ilkenin
  kapsamı mevcut kodu geriye dönük uyumsuz hale getirecek şekilde yeniden tanımlandığında.
  Örnek: İlke IV'ün `Application → Infrastructure` yasağının kaldırılması.
- **MINOR** — yeni bir ilke veya bölüm eklendiğinde, ya da mevcut bir ilkenin kapsamı yeni
  bir MUST ile genişletildiğinde. Örnek: İlke VI'ya "sır tarayıcı CI job'ı zorunludur"
  maddesinin eklenmesi.
- **PATCH** — kanıt satır numaralarının tazelenmesi, borç kaydının güncellenmesi, dil ve
  yazım düzeltmeleri, kural anlamını değiştirmeyen netleştirmeler. Bir borcun kapanıp
  tablodan silinmesi PATCH'tir; o borcun ilkeyi değiştirmesi MINOR veya MAJOR'dır.

Sürümü değiştiren her PR, dosyanın en altındaki sürüm satırını ve `Last Amended` tarihini
güncellemelidir (MUST).

### Her PR'da denetlenecek uyum listesi

İnceleyen aşağıdaki maddeleri tek tek işaretlemelidir. İşaretlenemeyen bir madde varsa PR
merge **edilmez (MUST NOT)** — madde ya karşılanır ya da aşağıdaki çelişki prosedürüyle borç
olarak kaydedilir.

- [ ] Üretilmiş dosyalar elle düzenlenmemiş; API değiştiyse üretim aynı commit'te. (İlke I)
- [ ] Yeni uç noktanın `index.ts` cephesinde takma adı var. (İlke I)
- [ ] Her uç nokta `TypedResults` + adlandırılmış `record` döndürüyor; anonim tip yok. (İlke II)
- [ ] Eklenen her kapı bilerek bozulmuş, **çıkış kodu 1** görülmüş, çıktı PR'da. (İlke III)
- [ ] Boş gövdeli veya hiçbir şey doğrulamayan test eklenmemiş. (İlke III)
- [ ] `Domain.csproj` hâlâ sıfır referanslı; `Application` Infrastructure/EF görmüyor;
      `Program.cs` yalnızca `AddApplication`/`AddInfrastructure` çağırıyor. (İlke IV)
- [ ] Required check zayıflatılmamış, atlanmamış, ruleset'e bypass eklenmemiş. (İlke V)
- [ ] Kaynakta kimlik bilgisi, anahtar veya yeni bir ortam adresi literali yok. (İlke VI)
- [ ] `package-lock.json` / `global.json` değişimi commit'lenmiş; `npm install` ile
      oluşturulmuş bir lock farkı yok. (İlke VII)
- [ ] Yerel lint çalıştırılmış (CI koşmuyor). (Değişiklik Akışı madde 5)
- [ ] İki `.sln` senkron. (Değişiklik Akışı madde 6)
- [ ] Bir ilke ile çelişen şey varsa, borç kaydına satır eklenmiş. (aşağıdaki prosedür)

### Bir ilke ile kod gerçeği çeliştiğinde

Kural **gevşetilmez**. Çelişki bir kanıttır: ya kod yanlıştır ya da ilkenin kanıtı
eskimiştir. Sıra şudur:

1. **Kanıtı yeniden üret.** İlkenin altındaki komutu çalıştır veya dosyayı oku. Kanıt hâlâ
   geçerliyse kod yanlıştır; kanıt geçersizse (satır kaymış, dosya taşınmış) bu bir PATCH
   düzeltmesidir, ilke değişmez.
2. **Kod yanlışsa ve aynı PR'da düzeltilebiliyorsa düzelt.** Varsayılan budur.
3. **Aynı PR'da düzeltilemiyorsa borç olarak kaydet.** "Doğrulama Sınırları ve Borç Kaydı"
   tablosuna satır ekle: kod, tek cümlelik tanım, ilke numarası, kaynak. Gerekiyorsa
   `BACKLOG.md`'ye kabul kriterleriyle birlikte yaz. İlkenin metnine, borcu adıyla anan bir
   "Bilinen boşluk" paragrafı ekle — İlke V, VI ve VII'deki paragraflar bunun örneğidir.
   İlkenin MUST dili **değişmez**; yalnızca bugün nerede uygulanamadığı yazılır.
4. **İlkeyi ancak gerekçeyi çürüterek değiştir.** Her ilkenin "Gerekçe" bölümü, kural
   olmasaydı ne olacağını söyler. Bir ilkeyi kaldırmak veya zayıflatmak isteyen PR, o
   gerekçenin neden artık geçerli olmadığını göstermek zorundadır (MUST). "Yavaşlatıyor",
   "şimdilik gereksiz" veya "CI'da zaten yakalanır" geçerli gerekçe değildir — sonuncusu
   için İlke III'ün kanıtına bakın.

Borç kaydetmek ilkeyi ihlal etmenin meşru yolu **değildir**; ihlali görünür kılmanın
yoludur. Kaydedilmiş bir borç, kapatılana kadar her yeni PR'da o ilkeyi ihlal etme hakkı
vermez.

**Version**: 1.0.2 | **Ratified**: 2026-09-29 | **Last Amended**: 2026-09-29
