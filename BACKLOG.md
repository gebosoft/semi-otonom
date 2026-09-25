# BACKLOG.md

Faz 0 sırasında biriken açık işler. `AGENTS.md`'nin "Açık işler" bölümüyle senkron
tutulur: bir madde kapandığında iki dosyadan da silinir.

Sıralama önceliğe göredir. **B1 ve B2, Faz 1'e (ilk gerçek özellik) geçmeden
kapatılmalıdır** — ikisi de hattın doğrulama katmanındaki boşluklar.

---

## B1 — Çalıştırılabilir test yok 🔴

**Durum:** CI'daki `api` job'ı bugün hiçbir şey doğrulamıyor.

- `api/tests/Api.Tests` boş bir placeholder `[Fact]` içeriyor; `dotnet test` çalışıyor,
  geçiyor, ama hiçbir şeyi kontrol etmiyor.
- `web` tarafında `vitest` ve testing-library kurulu, ama `test` script'i, config'i ve
  tek bir test dosyası yok. CI'da JS testi hiç koşmuyor.

**Neden kritik:** Bu, `check-contracts.sh`'ta yaşadığımız "eksik `exit 1`" durumunun
aynısı — yeşil görünen ama koruma sağlamayan bir kapı. Ajan kod yazmaya başladığında
tek gerçek doğrulama katmanı testlerdir.

**Kabul kriterleri**
- [ ] `Api.Tests` içinde `/health` uç noktasını gerçekten çağıran bir integration test
      (`WebApplicationFactory`)
- [ ] Testi bilerek bozup `dotnet test`'in **exit 1** döndüğü doğrulandı
- [ ] `web/vitest.config.ts` + `npm run test --workspace web` script'i
- [ ] En az bir gerçek web testi (App render edilip `/health` çağrısı mock'lanır)
- [ ] `ci.yml`'deki `web` job'ına `npm run test --workspace web` eklendi
- [ ] Web testini bilerek bozup CI'ın kırmızı olduğu doğrulandı

---

## B2 — API adresi koda gömülü 🔴

**Durum:** `web/src/App.tsx` içinde `http://localhost:5027` literal olarak yazılı.
`VITE_*` ortam değişkeni ve `.env.example` yok.

**Neden kritik:** İlk gerçek özellikte her API çağrısı bu adresi kullanacak. Sonradan
düzeltmek, dağılmış literal'leri toplamak demek. Ayrıca sır yönetimi konvansiyonunun
zemini de burada kurulur.

**Kabul kriterleri**
- [ ] `web/.env.example` — `VITE_API_BASE_URL=http://localhost:5027`
- [ ] `.env` dosyaları `.gitignore`'da (kontrol et, varsa dokunma)
- [ ] `web/src/lib/config.ts` — değişkeni okur, eksikse **açık hata fırlatır**
      (sessizce `undefined`'a düşmez)
- [ ] `App.tsx` literal'i kaldırıldı
- [ ] `ci.yml`'deki `web` job'ına derleme için `VITE_API_BASE_URL` env eklendi

---

## B3 — react-query ve react-router kurulu ama kullanılmıyor 🟡

**Durum:** `@tanstack/react-query` ve `react-router` bağımlılık olarak var, hiçbir
yerden import edilmiyor. Provider ve router yok.

**Neden önemli:** İlk özellik yazılırken ajan bunları kendi bildiği gibi kuracak.
Pattern'i önceden koymak, her özellikte yeniden karar verilmesini önler.

**Kabul kriterleri**
- [ ] `QueryClientProvider` kök seviyede (`main.tsx`)
- [ ] `createBrowserRouter` ile en az iki route (`/` ve bir 404)
- [ ] Sözleşme tiplerini kullanan **bir** örnek `useQuery` — `/health` üzerinden,
      `components["schemas"]["HealthResponse"]` tipiyle
- [ ] Örnek, "yeni bir sorgu nasıl yazılır" sorusunun cevabı olacak kadar net

---

## B4 — İki package-lock.json 🟡

**Durum:** Kökte ve `web/` altında iki lock dosyası var. Geçerli olan köktekidir.

**Neden önemli:** npm workspace'lerde alt lock dosyası çakışma ve kararsız çözümleme
kaynağı. CI ile lokal arasında farklı sürümler çekilebilir.

**Kabul kriterleri**
- [ ] `web/package-lock.json` silindi
- [ ] Kökten `npm ci` temiz çalışıyor
- [ ] Temiz klonda (`git clone` → `npm ci` → `npm run build --workspace web`) doğrulandı

---

## B5 — Ölü artıklar 🟢

**Durum:** Faz 0'da yön değiştirirken kalan dosya ve satırlar.

- `openapitools.json` (kökte ve `api/` altında) — openapi-generator-cli artık
  kullanılmıyor, araç `openapi-typescript`
- `api/src/Api/Api.http` içindeki `/weatherforecast/` referansı — o uç nokta yok
- `.gitignore`'daki Flutter satırları (`.dart_tool/`, `*.iml`, `.flutter-plugins*`)
- `master` dalı kalıntısı varsa

**Neden önemli:** Ajan bu dosyaları okuyup var olmayan araçlar/uç noktalar hakkında
yanlış varsayım üretir. `Migration.Md` tipi bayat dosyaların nasıl zarar verdiğini
biliyoruz.

**Kabul kriterleri**
- [ ] Yukarıdakiler silindi
- [ ] `grep -rn "weatherforecast\|openapi-generator" --include="*.json" --include="*.http" .`
      boş dönüyor
- [ ] `AGENTS.md`'den "Ölü artıklar" maddesi çıkarıldı

---

## B6 — Result/Error → HTTP eşlemesi yok 🟡

**Durum:** `Application/Common/Result.cs` var, ama bir `Result<T>`'nin HTTP yanıtına
nasıl dönüşeceği tanımlı değil.

**Neden önemli:** İlk özellikte her uç nokta bunu kendi başına çözerse tutarsızlık
doğar. Ayrıca hata yanıtlarının da OpenAPI'de görünmesi gerekir — aksi halde istemci
tarafında hata tipleri kaybolur.

**Kabul kriterleri**
- [ ] `Result<T>` → `TypedResults` eşlemesi tek bir yerde (extension veya filter)
- [ ] Hata yanıtı named bir `record` (anonim tip değil — sözleşme kuralı)
- [ ] `ProducesProblem` / `Produces<T>` ile OpenAPI'ye yansıyor
- [ ] `contracts/Api.json`'da hata şeması görünüyor
- [ ] TS tarafında hata tipi erişilebilir

---

## Kapanmış

<!-- Kapanan maddeler buraya taşınır, tarih ve PR numarasıyla -->