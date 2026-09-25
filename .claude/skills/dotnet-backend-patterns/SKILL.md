---
name: dotnet-backend-patterns
description: Master C#/.NET backend development patterns for building robust APIs, MCP servers, and enterprise applications. Covers Clean Architecture layout (Domain-owned repository interfaces + IUnitOfWork), async/await, dependency injection, Entity Framework Core, Dapper, configuration, caching, and testing with xUnit. Use when scaffolding a new .NET backend, adding a feature, or designing API architecture. For reviewing existing code or validating PRs, use `dotnet-code-review` instead.
---

# .NET Backend Development Patterns

Master C#/.NET patterns for building production-grade APIs, MCP servers, and enterprise backends with modern best practices (2024/2025).

## When to Use This Skill

- Scaffolding new .NET Web APIs or MCP servers
- Adding a new feature or aggregate to an existing .NET backend
- Designing service architectures with dependency injection
- Implementing caching strategies with Redis
- Writing unit and integration tests
- Optimizing database access with EF Core or Dapper
- Configuring applications with IOptions pattern
- Handling errors and implementing resilience patterns

For reviewing existing code, auditing PRs, or validating changes before merge, use **`dotnet-code-review`** instead — it's the companion checklist skill.

## Core Concepts

### 1. Project Structure (Clean Architecture)

```
src/
├── Domain/                     # Core business logic (no dependencies)
│   ├── Common/                 # Entity, AuditableEntity, AggregateRoot, IDomainEvent, exceptions
│   ├── Entities/               # Concrete entities (inherit Entity / AuditableEntity / AggregateRoot)
│   ├── ValueObjects/           # Immutable records with constructor-validated invariants
│   ├── Enums/                  # Domain enums (mapped via HasConversion<string>())
│   ├── Events/                 # Concrete IDomainEvent records raised by aggregates
│   ├── Services/               # Stateless cross-aggregate domain logic (static)
│   └── Repositories/           # Repository interfaces + IUnitOfWork (NOT impls)
├── Application/                # Use cases, DTOs, validation
│   ├── Services/               # Inject Domain repository interfaces + IUnitOfWork
│   ├── DTOs/
│   ├── Validators/
│   └── Abstractions/           # Application-only contracts (e.g. ICurrentUser)
├── Infrastructure/             # External implementations
│   ├── Persistence/
│   │   ├── AppDbContext.cs     # implements IUnitOfWork
│   │   ├── Configurations/     # IEntityTypeConfiguration<T> + EntityConfigurationExtensions
│   │   ├── Interceptors/       # AuditingInterceptor, others
│   │   └── Repositories/       # EF Core / Dapper repository implementations
│   ├── Caching/                # Redis, Memory cache
│   ├── External/               # HTTP clients, third-party APIs
│   └── DependencyInjection/    # Service registration
└── Api/                        # Entry point
    ├── Controllers/            # Or MinimalAPI endpoints
    ├── Middleware/
    ├── Filters/
    └── Program.cs
```

**Dependency direction:** `Api → Application → Domain ← Infrastructure`. Domain has zero dependencies. Application depends only on Domain. Infrastructure implements Domain abstractions. Api wires everything in `Program.cs`.

### 2. Dependency Injection Patterns

```csharp
// Service registration by lifetime
public static class ServiceCollectionExtensions
{
    public static IServiceCollection AddApplicationServices(
        this IServiceCollection services,
        IConfiguration configuration)
    {
        // Scoped: One instance per HTTP request
        services.AddScoped<IProductService, ProductService>();
        services.AddScoped<IOrderService, OrderService>();

        // Singleton: One instance for app lifetime
        services.AddSingleton<ICacheService, RedisCacheService>();
        services.AddSingleton<IConnectionMultiplexer>(_ =>
            ConnectionMultiplexer.Connect(configuration["Redis:Connection"]!));

        // Transient: New instance every time
        services.AddTransient<IValidator<CreateOrderRequest>, CreateOrderValidator>();

        // Options pattern for configuration
        services.Configure<CatalogOptions>(configuration.GetSection("Catalog"));
        services.Configure<RedisOptions>(configuration.GetSection("Redis"));

        // Factory pattern for conditional creation
        services.AddScoped<IPriceCalculator>(sp =>
        {
            var options = sp.GetRequiredService<IOptions<PricingOptions>>().Value;
            return options.UseNewEngine
                ? sp.GetRequiredService<NewPriceCalculator>()
                : sp.GetRequiredService<LegacyPriceCalculator>();
        });

        // Keyed services (.NET 8+)
        services.AddKeyedScoped<IPaymentProcessor, StripeProcessor>("stripe");
        services.AddKeyedScoped<IPaymentProcessor, PayPalProcessor>("paypal");

        return services;
    }
}

// Usage with keyed services
public class CheckoutService
{
    public CheckoutService(
        [FromKeyedServices("stripe")] IPaymentProcessor stripeProcessor)
    {
        _processor = stripeProcessor;
    }
}
```

### 3. Async/Await Patterns

```csharp
// ✅ CORRECT: Async all the way down
public async Task<Product> GetProductAsync(string id, CancellationToken ct = default)
{
    return await _repository.GetByIdAsync(id, ct);
}

// ✅ CORRECT: Parallel execution with WhenAll
public async Task<(Stock, Price)> GetStockAndPriceAsync(
    string productId,
    CancellationToken ct = default)
{
    var stockTask = _stockService.GetAsync(productId, ct);
    var priceTask = _priceService.GetAsync(productId, ct);

    await Task.WhenAll(stockTask, priceTask);

    return (await stockTask, await priceTask);
}

// ✅ CORRECT: ConfigureAwait in libraries
public async Task<T> LibraryMethodAsync<T>(CancellationToken ct = default)
{
    var result = await _httpClient.GetAsync(url, ct).ConfigureAwait(false);
    return await result.Content.ReadFromJsonAsync<T>(ct).ConfigureAwait(false);
}

// ✅ CORRECT: ValueTask for hot paths with caching
public ValueTask<Product?> GetCachedProductAsync(string id)
{
    if (_cache.TryGetValue(id, out Product? product))
        return ValueTask.FromResult(product);

    return new ValueTask<Product?>(GetFromDatabaseAsync(id));
}

// ❌ WRONG: Blocking on async (deadlock risk)
var result = GetProductAsync(id).Result;  // NEVER do this
var result2 = GetProductAsync(id).GetAwaiter().GetResult(); // Also bad

// ❌ WRONG: async void (except event handlers)
public async void ProcessOrder() { }  // Exceptions are lost

// ❌ WRONG: Unnecessary Task.Run for already async code
await Task.Run(async () => await GetDataAsync());  // Wastes thread
```

### 4. Configuration with IOptions

```csharp
// Configuration classes
public class CatalogOptions
{
    public const string SectionName = "Catalog";

    public int DefaultPageSize { get; set; } = 50;
    public int MaxPageSize { get; set; } = 200;
    public TimeSpan CacheDuration { get; set; } = TimeSpan.FromMinutes(15);
    public bool EnableEnrichment { get; set; } = true;
}

public class RedisOptions
{
    public const string SectionName = "Redis";

    public string Connection { get; set; } = "localhost:6379";
    public string KeyPrefix { get; set; } = "mcp:";
    public int Database { get; set; } = 0;
}

// appsettings.json
{
    "Catalog": {
        "DefaultPageSize": 50,
        "MaxPageSize": 200,
        "CacheDuration": "00:15:00",
        "EnableEnrichment": true
    },
    "Redis": {
        "Connection": "localhost:6379",
        "KeyPrefix": "mcp:",
        "Database": 0
    }
}

// Registration
services.Configure<CatalogOptions>(configuration.GetSection(CatalogOptions.SectionName));
services.Configure<RedisOptions>(configuration.GetSection(RedisOptions.SectionName));

// Usage with IOptions (singleton, read once at startup)
public class CatalogService
{
    private readonly CatalogOptions _options;

    public CatalogService(IOptions<CatalogOptions> options)
    {
        _options = options.Value;
    }
}

// Usage with IOptionsSnapshot (scoped, re-reads on each request)
public class DynamicService
{
    private readonly CatalogOptions _options;

    public DynamicService(IOptionsSnapshot<CatalogOptions> options)
    {
        _options = options.Value;  // Fresh value per request
    }
}

// Usage with IOptionsMonitor (singleton, notified on changes)
public class MonitoredService
{
    private CatalogOptions _options;

    public MonitoredService(IOptionsMonitor<CatalogOptions> monitor)
    {
        _options = monitor.CurrentValue;
        monitor.OnChange(newOptions => _options = newOptions);
    }
}
```

### 5. Result Pattern (Avoiding Exceptions for Flow Control)

```csharp
// A business-rule failure with a machine-readable code and a human-readable
// message. Implicitly convertible to any Result<T> so handlers can write
// `return new Error("WALLET_NOT_FOUND", "...");`.
public sealed record Error(string Code, string Message);

// Standard result wrapper used across the Application layer to avoid throwing
// exceptions for expected business-rule failures. Implicit conversions keep
// handler returns readable:
//   return order;                            // success
//   return new Error("CODE", "message");     // failure
public class Result<T>
{
    public bool IsSuccess { get; }
    public T? Value { get; }
    public Error? Error { get; }

    private Result(bool isSuccess, T? value, Error? error)
    {
        IsSuccess = isSuccess;
        Value = value;
        Error = error;
    }

    public static Result<T> Success(T value) => new(true, value, null);

    public static Result<T> Failure(Error error) => new(false, default, error);

    public static implicit operator Result<T>(T value) => Success(value);

    public static implicit operator Result<T>(Error error) => Failure(error);
}

// Usage in service
public async Task<Result<Order>> CreateOrderAsync(CreateOrderRequest request, CancellationToken ct)
{
    // Validation
    var validation = await _validator.ValidateAsync(request, ct);
    if (!validation.IsValid)
        return new Error("VALIDATION_ERROR", validation.Errors.First().ErrorMessage);

    // Business rule check
    var stock = await _stockService.CheckAsync(request.ProductId, request.Quantity, ct);
    if (!stock.IsAvailable)
        return new Error("INSUFFICIENT_STOCK",
            $"Insufficient stock: {stock.Available} available, {request.Quantity} requested");

    // Create order — repository stages the change, UoW commits
    var order = request.ToEntity();
    await _repository.AddAsync(order, ct);
    await _unitOfWork.SaveChangesAsync(ct);

    return order; // implicit success conversion
}

// Required for the Results<,> union and the Created<>/BadRequest<> result types.
// (TypedResults itself is in Microsoft.AspNetCore.Http, which the web SDK already
// brings in via global usings — this one you must add yourself.)
using Microsoft.AspNetCore.Http.HttpResults;

// The wire-level shape of a failure. A named record — NOT an anonymous type:
// anonymous types never make it into the OpenAPI schema, so client generators
// emit untyped or broken code for the error branch.
public record ErrorResponse(string Code, string Message);

// Usage in controller/endpoint.
// TypedResults (not Results) + an explicit Results<...> union return type is what
// lets the OpenAPI document list both 201 and 400 with their real payload schemas.
app.MapPost("/orders", async Task<Results<Created<Order>, BadRequest<ErrorResponse>>> (
    CreateOrderRequest request,
    IOrderService orderService,
    CancellationToken ct) =>
{
    var result = await orderService.CreateOrderAsync(request, ct);

    return result.IsSuccess
        ? TypedResults.Created($"/orders/{result.Value!.Id}", result.Value)
        : TypedResults.BadRequest(new ErrorResponse(result.Error!.Code, result.Error.Message));
});
```

## Repository Layout & Unit of Work

**This is the architectural contract — read before writing repository code.**

### Where each piece lives

| Piece | Project | Folder |
|-------|---------|--------|
| Repository **interface** (`IUserRepository`, `IOrderRepository`, …) | `Domain` | `Domain/Repositories/` |
| `IUnitOfWork` interface | `Domain` | `Domain/Repositories/` |
| Repository **implementation** (EF Core / Dapper) | `Infrastructure` | `Infrastructure/Persistence/Repositories/` |
| `DbContext` | `Infrastructure` | `Infrastructure/Persistence/` |

The Domain layer owns the **abstractions**. Infrastructure owns the **implementations**. Application services depend on the Domain interfaces, never on EF Core or `DbContext` directly.

### Repository contract rules

1. Repository methods **stage** changes (`AddAsync`, `Update`, `Remove`, query methods). They do **not** call `SaveChangesAsync`.
2. Committing the unit of work is the responsibility of the application service, via `IUnitOfWork.SaveChangesAsync(ct)`.
3. This way one service operation that touches multiple repositories is one atomic database round-trip.

### Why not `repository.SaveChangesAsync()` per repo?

Because two repositories called in the same service method would commit twice. Half-applied state on failure. Hidden coupling. The UoW is the seam where "the operation succeeded" is decided.

### Domain interfaces

```csharp
// Domain/Repositories/IUserRepository.cs
namespace YourApp.Domain.Repositories;

public interface IUserRepository
{
    Task<User?> GetByIdAsync(Guid id, CancellationToken ct = default);
    Task<User?> GetByEmailAsync(string email, CancellationToken ct = default);
    Task AddAsync(User user, CancellationToken ct = default);
    void Remove(User user);
    // NOTE: no SaveChangesAsync here — that's the UoW's job.
}

// Domain/Repositories/IUnitOfWork.cs
namespace YourApp.Domain.Repositories;

public interface IUnitOfWork
{
    Task<int> SaveChangesAsync(CancellationToken ct = default);
}
```

### Infrastructure implementations

```csharp
// Infrastructure/Persistence/Repositories/UserRepository.cs
public class UserRepository : IUserRepository
{
    private readonly AppDbContext _context;
    public UserRepository(AppDbContext context) => _context = context;

    public Task<User?> GetByIdAsync(Guid id, CancellationToken ct = default) =>
        _context.Users.FirstOrDefaultAsync(u => u.Id == id, ct);

    public Task<User?> GetByEmailAsync(string email, CancellationToken ct = default) =>
        _context.Users.FirstOrDefaultAsync(u => u.Email == email, ct);

    public async Task AddAsync(User user, CancellationToken ct = default) =>
        await _context.Users.AddAsync(user, ct);

    public void Remove(User user) => _context.Users.Remove(user);
}
```

The simplest `IUnitOfWork` implementation is the `DbContext` itself:

```csharp
// Infrastructure/Persistence/AppDbContext.cs
public class AppDbContext : DbContext, IUnitOfWork
{
    // ...DbSets and OnModelCreating...
    Task<int> IUnitOfWork.SaveChangesAsync(CancellationToken ct) =>
        base.SaveChangesAsync(ct);
}

// DI registration
services.AddDbContext<AppDbContext>(opt => opt.UseSqlServer(connStr));
services.AddScoped<IUnitOfWork>(sp => sp.GetRequiredService<AppDbContext>());
services.AddScoped<IUserRepository, UserRepository>();
```

If you need explicit transactions (e.g. multi-aggregate atomicity beyond `SaveChangesAsync`), extend `IUnitOfWork` with `BeginTransactionAsync/CommitAsync/RollbackAsync` — see `assets/repository-template.cs` for a full version.

### Service usage

```csharp
public class UserService
{
    private readonly IUserRepository _users;
    private readonly IUnitOfWork _unitOfWork;

    public UserService(IUserRepository users, IUnitOfWork unitOfWork)
    {
        _users = users;
        _unitOfWork = unitOfWork;
    }

    public async Task<Result<User>> RegisterAsync(RegisterRequest req, CancellationToken ct)
    {
        if (await _users.GetByEmailAsync(req.Email, ct) is not null)
            return new Error("EMAIL_TAKEN", "Email taken");

        var user = User.Create(req.Email, req.FullName);
        await _users.AddAsync(user, ct);
        await _unitOfWork.SaveChangesAsync(ct);   // ← the only commit point
        return user;
    }
}
```

### Common mistakes to avoid

- ❌ Putting `IUserRepository` inline in the same file as `UserService` (Application layer). Move it to `Domain/Repositories/`.
- ❌ Adding `Task SaveChangesAsync(CancellationToken)` to the repository interface. Belongs on `IUnitOfWork`.
- ❌ Repository implementations calling `_context.SaveChangesAsync()` themselves. Caller commits.
- ❌ Application services injecting `AppDbContext` directly. Inject `IUnitOfWork` + the repos you need.

## Entity Identity & Auditing

Every entity in the Domain layer carries two cross-cutting concerns: **identity** (`Id`) and **timestamps** (`CreatedAt`, optionally `UpdatedAt`). Solve both with a small inheritance chain — do **not** repeat these properties on every entity, and do **not** use `Guid.NewGuid()` field initializers.

### Two-level base hierarchy

```csharp
// Domain/Common/Entity.cs — for append-only / immutable records.
public abstract class Entity
{
    public Guid Id { get; protected set; }
    public DateTime CreatedAt { get; protected set; }

    protected Entity() { }   // EF Core hydration entry point

    /// <summary>Sortable, sequential UUIDv7. Far better clustered-index locality than Guid.NewGuid().</summary>
    protected static Guid NewId() => Guid.CreateVersion7();
}

// Domain/Common/AuditableEntity.cs — for entities that mutate after creation.
public abstract class AuditableEntity : Entity
{
    public DateTime? UpdatedAt { get; private set; }

    protected AuditableEntity() { }
}
```

**Choosing between them:**

- `Entity` — **append-only** records that never UPDATE in place: ledger/transaction entries, audit logs, outbox events.
- `AuditableEntity` — records that DO get UPDATEd: user profiles, account balances, catalog items, anything with mutable state.

The decision rule: "does a state change to this thing produce a new row, or modify an existing one?" New row → `Entity`. Modify existing → `AuditableEntity`.

### Why `Guid.NewGuid()` in property initializers is wrong

```csharp
// ❌ DON'T do this:
public class User
{
    public Guid Id { get; set; } = Guid.NewGuid();
}
```

Two real problems:

1. **UUIDv4 is random.** Each INSERT lands at a random spot in the SQL Server clustered index → page splits, fragmentation, write amplification. UUIDv7 (`Guid.CreateVersion7()`) is timestamp-prefixed and sortable, so inserts append at the tail.
2. **Initializers fire on EF hydration.** Every time EF Core materializes a `User` from the DB, the parameterless ctor runs, `Guid.NewGuid()` produces a fresh GUID, and EF immediately overwrites it with the loaded value. Wasted work on every read.

The fix is the factory pattern below — `Id` is set exactly once, in the factory, using UUIDv7.

### Factory pattern with private setters

```csharp
public class User : AuditableEntity
{
    public string Email { get; private set; } = string.Empty;
    public string PasswordHash { get; private set; } = string.Empty;
    public string FullName { get; private set; } = string.Empty;
    public string? PhoneNumber { get; private set; }

    public LoyaltyAccount? LoyaltyAccount { get; private set; }

    private User() { }   // EF Core uses this; external callers cannot.

    public static User Create(string email, string passwordHash, string fullName, string? phoneNumber)
    {
        if (string.IsNullOrWhiteSpace(email))
            throw new ArgumentException("Email is required.", nameof(email));
        if (string.IsNullOrWhiteSpace(passwordHash))
            throw new ArgumentException("Password hash is required.", nameof(passwordHash));
        if (string.IsNullOrWhiteSpace(fullName))
            throw new ArgumentException("Full name is required.", nameof(fullName));

        var user = new User
        {
            Id = NewId(),                  // inherited helper → Guid.CreateVersion7()
            CreatedAt = DateTime.UtcNow,
            Email = email,
            PasswordHash = passwordHash,
            FullName = fullName,
            PhoneNumber = phoneNumber,
        };

        // Cross-aggregate creation handled inside the factory — application services
        // don't need to know that "every user gets a Bronze loyalty account".
        user.LoyaltyAccount = LoyaltyAccount.CreateForNewUser(user.Id);
        return user;
    }
}
```

**Rules:**

- Inherit `Entity` or `AuditableEntity` — never declare `Id` / `CreatedAt` / `UpdatedAt` directly on a concrete entity.
- All properties have `private set`.
- Private parameterless constructor for EF Core (it uses reflection — works fine).
- Static factory (`Create`, `CreateForX`) is the **only** public construction path. Validates invariants, calls `NewId()`, sets `CreatedAt`.
- Mutating behavior is exposed via methods (`DeductPoints`, `MarkUnavailable`), never raw setters. Methods enforce invariants: `if (amount > PointsBalance) throw new InvalidOperationException(...)`.

### Append-only entity example

```csharp
public class PointTransaction : Entity   // not AuditableEntity — never updated in place
{
    public Guid LoyaltyAccountId { get; private set; }
    public PointTransactionType Type { get; private set; }
    public int Points { get; private set; }
    public string Description { get; private set; } = string.Empty;

    private PointTransaction() { }

    public static PointTransaction CreateRedemption(Guid loyaltyAccountId, Reward reward) =>
        new()
        {
            Id = NewId(),
            CreatedAt = DateTime.UtcNow,
            LoyaltyAccountId = loyaltyAccountId,
            Type = PointTransactionType.Redeem,
            Points = -reward.PointsCost,
            Description = $"Redeemed: {reward.Title}",
        };
}
```

### Automatic `UpdatedAt` via SaveChangesInterceptor

Domain code must **not** be responsible for setting `UpdatedAt`. Wire an interceptor that stamps it on every Modified `AuditableEntity`:

```csharp
// Infrastructure/Persistence/Interceptors/AuditingInterceptor.cs
public class AuditingInterceptor : SaveChangesInterceptor
{
    public override ValueTask<InterceptionResult<int>> SavingChangesAsync(
        DbContextEventData eventData,
        InterceptionResult<int> result,
        CancellationToken cancellationToken = default)
    {
        Stamp(eventData.Context);
        return base.SavingChangesAsync(eventData, result, cancellationToken);
    }

    public override InterceptionResult<int> SavingChanges(
        DbContextEventData eventData,
        InterceptionResult<int> result)
    {
        Stamp(eventData.Context);
        return base.SavingChanges(eventData, result);
    }

    private static void Stamp(DbContext? context)
    {
        if (context is null) return;
        var now = DateTime.UtcNow;

        foreach (var entry in context.ChangeTracker.Entries<AuditableEntity>())
        {
            if (entry.State == EntityState.Modified)
            {
                // Going through ChangeTracker writes the value via EF's accessor,
                // so the private setter is no obstacle.
                entry.Property(nameof(AuditableEntity.UpdatedAt)).CurrentValue = now;
            }
        }
    }
}
```

Register it on the DbContext via DI:

```csharp
services.AddSingleton<AuditingInterceptor>();
services.AddDbContext<AppDbContext>((sp, options) =>
{
    options.UseSqlServer(connectionString);
    options.AddInterceptors(sp.GetRequiredService<AuditingInterceptor>());
});
```

**Why not set `CreatedAt` in the interceptor too?** Because then in-memory entities would have `CreatedAt = default(DateTime)` between construction and SaveChanges — a sharp footgun. Factory sets `CreatedAt`, interceptor sets `UpdatedAt`. Each timestamp has a single, obvious owner.

### EF configuration helper for the base properties

Don't repeat `HasKey`, `ValueGeneratedNever`, and the timestamp configurations on every entity. Extract:

```csharp
// Infrastructure/Persistence/Configurations/EntityConfigurationExtensions.cs
public static class EntityConfigurationExtensions
{
    public static EntityTypeBuilder<T> ConfigureEntityBase<T>(this EntityTypeBuilder<T> builder)
        where T : Entity
    {
        builder.HasKey(e => e.Id);
        builder.Property(e => e.Id).ValueGeneratedNever();   // factory provides the value
        builder.Property(e => e.CreatedAt);
        return builder;
    }

    public static EntityTypeBuilder<T> ConfigureAuditableBase<T>(this EntityTypeBuilder<T> builder)
        where T : AuditableEntity
    {
        builder.ConfigureEntityBase();
        builder.Property(e => e.UpdatedAt);
        return builder;
    }
}
```

Each entity config calls one line:

```csharp
public class UserConfiguration : IEntityTypeConfiguration<User>
{
    public void Configure(EntityTypeBuilder<User> builder)
    {
        builder.ToTable("Users");
        builder.ConfigureAuditableBase();              // ← Id, CreatedAt, UpdatedAt configured

        builder.Property(u => u.Email).HasMaxLength(256).IsRequired();
        builder.HasIndex(u => u.Email).IsUnique();
        // ...
    }
}
```

`ValueGeneratedNever()` is **critical** — without it, EF Core may default to SQL Server's `NEWID()` for the column, ignore your factory's UUIDv7, and silently break the whole pattern. Confirm this line is present after every refactor.

### New-entity checklist

- [ ] Inherits `Entity` (immutable) or `AuditableEntity` (mutates after creation).
- [ ] All properties have `private set`.
- [ ] Private parameterless constructor present for EF Core hydration.
- [ ] Static factory method (`Create`, `CreateForX`, `CreateRedemption`, …) is the only public construction path.
- [ ] Factory uses `NewId()` for the GUID, sets `CreatedAt = DateTime.UtcNow`, validates invariants.
- [ ] Mutating behavior exposed via methods, not raw setters.
- [ ] EF configuration calls `.ConfigureEntityBase()` or `.ConfigureAuditableBase()`.
- [ ] If `AuditableEntity`, the project's DI registers `AuditingInterceptor` against the DbContext.

## Value Objects & EF Core Persistence

Domain often has small immutable types — a money amount, a date range, a star balance. Don't expand these into entities; model them as **value objects** (records with constructor-validated invariants) and map them with EF Core's value conversion or owned types.

### Two mapping strategies — pick based on column shape

| Strategy | When to use | Result |
|----------|-------------|--------|
| `HasConversion` | VO wraps a single primitive — store as one column | One column on the parent table |
| `OwnsOne` | VO has multiple fields you want as separate columns | Multiple columns prefixed with the property name |

| VO type | EF mapping | DB column(s) |
|---------|-----------|--------------|
| `StarBalance` (decimal Amount) | `HasConversion` | `StarBalance numeric(18,2)` |
| `EarningMultiplier` (decimal Value) | `HasConversion` | `EarningMultiplier numeric(5,2)` |
| `enum CustomerTier` | `HasConversion<string>()` | `CurrentTier varchar(20)` |
| `MoneyAmount` (decimal + string) | `OwnsOne` | `{Prop}_Amount numeric(18,2)`, `{Prop}_Currency varchar(3)` |
| `CommitmentPeriod` (DateOnly + DateOnly) | `OwnsOne` | `Commitment_StartDate date`, `Commitment_EndDate date` |

### Single-column VO via `HasConversion`

```csharp
// Domain/ValueObjects/StarBalance.cs
public sealed record StarBalance
{
    public decimal Amount { get; }
    public static StarBalance Zero => new(0m);

    public StarBalance(decimal amount)
    {
        if (amount < 0) throw new ArgumentOutOfRangeException(nameof(amount));
        Amount = amount;
    }

    public StarBalance Add(decimal amount) => new(Amount + amount);
    public StarBalance Deduct(decimal amount) =>
        amount > Amount
            ? throw new InvalidOperationException("Insufficient balance.")
            : new(Amount - amount);
}
```

```csharp
// EF configuration
builder.Property(c => c.StarBalance)
    .HasConversion(v => v.Amount, v => new StarBalance(v))
    .HasColumnName("StarBalance")
    .HasColumnType("numeric(18,2)")        // SQL Server: decimal(18,2)
    .IsRequired();
```

The converter writes the wrapped primitive on save and re-wraps it on load. Invariants are re-validated by the constructor on read — defense in depth against direct DB tampering.

### Multi-column VO via `OwnsOne`

```csharp
// Domain/ValueObjects/MoneyAmount.cs
public sealed record MoneyAmount
{
    public decimal Amount { get; }
    public string Currency { get; }

    public MoneyAmount(decimal amount, string currency = "TRY")
    {
        if (amount < 0) throw new ArgumentOutOfRangeException(nameof(amount));
        if (string.IsNullOrWhiteSpace(currency))
            throw new ArgumentException("Currency required.", nameof(currency));
        Amount = amount;
        Currency = currency.ToUpperInvariant();
    }
}
```

```csharp
// EF configuration on the owning entity
builder.OwnsOne(p => p.Price, money =>
{
    money.Property(m => m.Amount)
        .HasColumnName("Price_Amount")
        .HasColumnType("numeric(18,2)")
        .IsRequired();
    money.Property(m => m.Currency)
        .HasColumnName("Price_Currency")
        .HasMaxLength(3)
        .IsRequired();
});
```

Each owned property becomes its own column on the parent table, prefixed by the navigation name. Use `OwnsOne` (not `HasMany` / `HasOne`) — owned types share the parent's lifetime and are loaded automatically.

### Date-range VO with `OwnsOne`

```csharp
public sealed record CommitmentPeriod
{
    public DateOnly StartDate { get; }
    public DateOnly EndDate { get; }

    public CommitmentPeriod(DateOnly startDate, DateOnly endDate)
    {
        if (endDate <= startDate)
            throw new ArgumentException("End must be after start.");
        StartDate = startDate;
        EndDate = endDate;
    }

    public bool IsActive(DateOnly today) => today >= StartDate && today <= EndDate;
}

// Configuration — explicit column names so the schema reads naturally.
builder.OwnsOne(c => c.Period, period =>
{
    period.Property(p => p.StartDate).HasColumnName("Commitment_StartDate");
    period.Property(p => p.EndDate).HasColumnName("Commitment_EndDate");
});
```

### Enum-backed property — always `HasConversion<string>()`

Don't store enums as `int` on disk: refactors, deletions, and reordering are silent footguns. Map to string and let EF's conversion handle it:

```csharp
builder.Property(c => c.CurrentTier)
    .HasConversion<string>()
    .HasMaxLength(20)
    .IsRequired();
```

Renaming an enum value now becomes a migration — visible, reviewable.

### Mutable collection VOs (Dictionary, List of primitives) — JSONB + ValueComparer

```csharp
var converter = new ValueConverter<Dictionary<int, decimal>, string>(
    v => JsonSerializer.Serialize(v, (JsonSerializerOptions?)null),
    v => JsonSerializer.Deserialize<Dictionary<int, decimal>>(v, (JsonSerializerOptions?)null)
         ?? new Dictionary<int, decimal>());

var comparer = new ValueComparer<Dictionary<int, decimal>>(
    (l, r) => (l == null && r == null) ||
              (l != null && r != null &&
               l.OrderBy(kv => kv.Key).SequenceEqual(r.OrderBy(kv => kv.Key))),
    v => v.OrderBy(kv => kv.Key).Aggregate(0, (h, kv) => HashCode.Combine(h, kv.Key, kv.Value)),
    v => new Dictionary<int, decimal>(v));

builder.Property(c => c.EarlyRenewalBonuses)
    .HasConversion(converter, comparer)
    .HasColumnType("jsonb")          // Postgres; SQL Server: nvarchar(max) + JSON
    .IsRequired();
```

Without the `ValueComparer`, EF treats every load as a new-reference modification and writes the column on every save. Always pair JSON-mapped mutable collections with a comparer.

### Why the constructor must validate

The constructor enforces invariants (`Amount < 0` rejected, `EndDate <= StartDate` rejected). The HasConversion's "load" function calls the constructor — so even data already in the DB gets re-validated on read. If something corrupted the row (manual SQL, a buggy older migration), the load throws and the bug surfaces immediately instead of silently propagating an invalid VO into business logic.

### Postgres ↔ SQL Server type cheat sheet

| SQL Server type | Postgres equivalent (use this in `HasColumnType`) |
|-----------------|---------------------------------------------------|
| `decimal(p, s)` | `numeric(p, s)` (same precision; `decimal` is an alias in Postgres) |
| `nvarchar(N)` | `varchar(N)` (or just use `HasMaxLength(N)` and let EF pick) |
| `nvarchar(max)` + JSON | `jsonb` |
| `rowversion` | shadow `xmin` property — see Concurrency notes |
| `datetime2` | `timestamp with time zone` (pair with `DateTime.Kind = Utc`) |

Prefer `HasMaxLength(N)` over a raw `HasColumnType("varchar(N)")` for varchar columns — it's portable across providers.

## Data Access Patterns

### Entity Framework Core

```csharp
// DbContext configuration
public class AppDbContext : DbContext
{
    public DbSet<Product> Products => Set<Product>();
    public DbSet<Order> Orders => Set<Order>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        // Apply all configurations from assembly
        modelBuilder.ApplyConfigurationsFromAssembly(typeof(AppDbContext).Assembly);

        // Global query filters
        modelBuilder.Entity<Product>().HasQueryFilter(p => !p.IsDeleted);
    }
}

// Entity configuration
public class ProductConfiguration : IEntityTypeConfiguration<Product>
{
    public void Configure(EntityTypeBuilder<Product> builder)
    {
        builder.ToTable("Products");

        builder.HasKey(p => p.Id);
        builder.Property(p => p.Id).HasMaxLength(40);
        builder.Property(p => p.Name).HasMaxLength(200).IsRequired();
        builder.Property(p => p.Price).HasPrecision(18, 2);

        builder.HasIndex(p => p.Sku).IsUnique();
        builder.HasIndex(p => new { p.CategoryId, p.Name });

        builder.HasMany(p => p.OrderItems)
            .WithOne(oi => oi.Product)
            .HasForeignKey(oi => oi.ProductId);
    }
}

// Repository with EF Core
// IProductRepository lives in Domain/Repositories/; this class lives in
// Infrastructure/Persistence/Repositories/. See "Repository Layout & Unit of Work" above.
public class ProductRepository : IProductRepository
{
    private readonly AppDbContext _context;

    public ProductRepository(AppDbContext context) => _context = context;

    public async Task<Product?> GetByIdAsync(string id, CancellationToken ct = default)
    {
        return await _context.Products
            .AsNoTracking()
            .FirstOrDefaultAsync(p => p.Id == id, ct);
    }

    public async Task<IReadOnlyList<Product>> SearchAsync(
        ProductSearchCriteria criteria,
        CancellationToken ct = default)
    {
        var query = _context.Products.AsNoTracking();

        if (!string.IsNullOrWhiteSpace(criteria.SearchTerm))
            query = query.Where(p => EF.Functions.Like(p.Name, $"%{criteria.SearchTerm}%"));

        if (criteria.CategoryId.HasValue)
            query = query.Where(p => p.CategoryId == criteria.CategoryId);

        if (criteria.MinPrice.HasValue)
            query = query.Where(p => p.Price >= criteria.MinPrice);

        if (criteria.MaxPrice.HasValue)
            query = query.Where(p => p.Price <= criteria.MaxPrice);

        return await query
            .OrderBy(p => p.Name)
            .Skip((criteria.Page - 1) * criteria.PageSize)
            .Take(criteria.PageSize)
            .ToListAsync(ct);
    }
}
```

### Dapper for Performance

```csharp
public class DapperProductRepository : IProductRepository
{
    private readonly IDbConnection _connection;

    public async Task<Product?> GetByIdAsync(string id, CancellationToken ct = default)
    {
        const string sql = """
            SELECT Id, Name, Sku, Price, CategoryId, Stock, CreatedAt
            FROM Products
            WHERE Id = @Id AND IsDeleted = 0
            """;

        return await _connection.QueryFirstOrDefaultAsync<Product>(
            new CommandDefinition(sql, new { Id = id }, cancellationToken: ct));
    }

    public async Task<IReadOnlyList<Product>> SearchAsync(
        ProductSearchCriteria criteria,
        CancellationToken ct = default)
    {
        var sql = new StringBuilder("""
            SELECT Id, Name, Sku, Price, CategoryId, Stock, CreatedAt
            FROM Products
            WHERE IsDeleted = 0
            """);

        var parameters = new DynamicParameters();

        if (!string.IsNullOrWhiteSpace(criteria.SearchTerm))
        {
            sql.Append(" AND Name LIKE @SearchTerm");
            parameters.Add("SearchTerm", $"%{criteria.SearchTerm}%");
        }

        if (criteria.CategoryId.HasValue)
        {
            sql.Append(" AND CategoryId = @CategoryId");
            parameters.Add("CategoryId", criteria.CategoryId);
        }

        if (criteria.MinPrice.HasValue)
        {
            sql.Append(" AND Price >= @MinPrice");
            parameters.Add("MinPrice", criteria.MinPrice);
        }

        if (criteria.MaxPrice.HasValue)
        {
            sql.Append(" AND Price <= @MaxPrice");
            parameters.Add("MaxPrice", criteria.MaxPrice);
        }

        sql.Append(" ORDER BY Name OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY");
        parameters.Add("Offset", (criteria.Page - 1) * criteria.PageSize);
        parameters.Add("PageSize", criteria.PageSize);

        var results = await _connection.QueryAsync<Product>(
            new CommandDefinition(sql.ToString(), parameters, cancellationToken: ct));

        return results.ToList();
    }

    // Multi-mapping for related data
    public async Task<Order?> GetOrderWithItemsAsync(int orderId, CancellationToken ct = default)
    {
        const string sql = """
            SELECT o.*, oi.*, p.*
            FROM Orders o
            LEFT JOIN OrderItems oi ON o.Id = oi.OrderId
            LEFT JOIN Products p ON oi.ProductId = p.Id
            WHERE o.Id = @OrderId
            """;

        var orderDictionary = new Dictionary<int, Order>();

        await _connection.QueryAsync<Order, OrderItem, Product, Order>(
            new CommandDefinition(sql, new { OrderId = orderId }, cancellationToken: ct),
            (order, item, product) =>
            {
                if (!orderDictionary.TryGetValue(order.Id, out var existingOrder))
                {
                    existingOrder = order;
                    existingOrder.Items = new List<OrderItem>();
                    orderDictionary.Add(order.Id, existingOrder);
                }

                if (item != null)
                {
                    item.Product = product;
                    existingOrder.Items.Add(item);
                }

                return existingOrder;
            },
            splitOn: "Id,Id");

        return orderDictionary.Values.FirstOrDefault();
    }
}
```

## Caching Patterns

### Multi-Level Cache with Redis

```csharp
public class CachedProductService : IProductService
{
    private readonly IProductRepository _repository;
    private readonly IMemoryCache _memoryCache;
    private readonly IDistributedCache _distributedCache;
    private readonly ILogger<CachedProductService> _logger;

    private static readonly TimeSpan MemoryCacheDuration = TimeSpan.FromMinutes(1);
    private static readonly TimeSpan DistributedCacheDuration = TimeSpan.FromMinutes(15);

    public async Task<Product?> GetByIdAsync(string id, CancellationToken ct = default)
    {
        var cacheKey = $"product:{id}";

        // L1: Memory cache (in-process, fastest)
        if (_memoryCache.TryGetValue(cacheKey, out Product? cached))
        {
            _logger.LogDebug("L1 cache hit for {CacheKey}", cacheKey);
            return cached;
        }

        // L2: Distributed cache (Redis)
        var distributed = await _distributedCache.GetStringAsync(cacheKey, ct);
        if (distributed != null)
        {
            _logger.LogDebug("L2 cache hit for {CacheKey}", cacheKey);
            var product = JsonSerializer.Deserialize<Product>(distributed);

            // Populate L1
            _memoryCache.Set(cacheKey, product, MemoryCacheDuration);
            return product;
        }

        // L3: Database
        _logger.LogDebug("Cache miss for {CacheKey}, fetching from database", cacheKey);
        var fromDb = await _repository.GetByIdAsync(id, ct);

        if (fromDb != null)
        {
            var serialized = JsonSerializer.Serialize(fromDb);

            // Populate both caches
            await _distributedCache.SetStringAsync(
                cacheKey,
                serialized,
                new DistributedCacheEntryOptions
                {
                    AbsoluteExpirationRelativeToNow = DistributedCacheDuration
                },
                ct);

            _memoryCache.Set(cacheKey, fromDb, MemoryCacheDuration);
        }

        return fromDb;
    }

    public async Task InvalidateAsync(string id, CancellationToken ct = default)
    {
        var cacheKey = $"product:{id}";

        _memoryCache.Remove(cacheKey);
        await _distributedCache.RemoveAsync(cacheKey, ct);

        _logger.LogInformation("Invalidated cache for {CacheKey}", cacheKey);
    }
}

// Stale-while-revalidate pattern
public class StaleWhileRevalidateCache<T>
{
    private readonly IDistributedCache _cache;
    private readonly TimeSpan _freshDuration;
    private readonly TimeSpan _staleDuration;

    public async Task<T?> GetOrCreateAsync(
        string key,
        Func<CancellationToken, Task<T>> factory,
        CancellationToken ct = default)
    {
        var cached = await _cache.GetStringAsync(key, ct);

        if (cached != null)
        {
            var entry = JsonSerializer.Deserialize<CacheEntry<T>>(cached)!;

            if (entry.IsStale && !entry.IsExpired)
            {
                // Return stale data immediately, refresh in background
                _ = Task.Run(async () =>
                {
                    var fresh = await factory(CancellationToken.None);
                    await SetAsync(key, fresh, CancellationToken.None);
                });
            }

            if (!entry.IsExpired)
                return entry.Value;
        }

        // Cache miss or expired
        var value = await factory(ct);
        await SetAsync(key, value, ct);
        return value;
    }

    private record CacheEntry<TValue>(TValue Value, DateTime CreatedAt)
    {
        public bool IsStale => DateTime.UtcNow - CreatedAt > _freshDuration;
        public bool IsExpired => DateTime.UtcNow - CreatedAt > _staleDuration;
    }
}
```

## Testing Patterns

### Unit Tests with xUnit and Moq

```csharp
public class OrderServiceTests
{
    private readonly Mock<IOrderRepository> _mockRepository;
    private readonly Mock<IStockService> _mockStockService;
    private readonly Mock<IValidator<CreateOrderRequest>> _mockValidator;
    private readonly OrderService _sut; // System Under Test

    public OrderServiceTests()
    {
        _mockRepository = new Mock<IOrderRepository>();
        _mockStockService = new Mock<IStockService>();
        _mockValidator = new Mock<IValidator<CreateOrderRequest>>();

        // Default: validation passes
        _mockValidator
            .Setup(v => v.ValidateAsync(It.IsAny<CreateOrderRequest>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(new ValidationResult());

        _sut = new OrderService(
            _mockRepository.Object,
            _mockStockService.Object,
            _mockValidator.Object);
    }

    [Fact]
    public async Task CreateOrderAsync_WithValidRequest_ReturnsSuccess()
    {
        // Arrange
        var request = new CreateOrderRequest
        {
            ProductId = "PROD-001",
            Quantity = 5,
            CustomerOrderCode = "ORD-2024-001"
        };

        _mockStockService
            .Setup(s => s.CheckAsync("PROD-001", 5, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new StockResult { IsAvailable = true, Available = 10 });

        _mockRepository
            .Setup(r => r.CreateAsync(It.IsAny<Order>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(new Order { Id = 1, CustomerOrderCode = "ORD-2024-001" });

        // Act
        var result = await _sut.CreateOrderAsync(request);

        // Assert
        Assert.True(result.IsSuccess);
        Assert.NotNull(result.Value);
        Assert.Equal(1, result.Value.Id);

        _mockRepository.Verify(
            r => r.CreateAsync(It.Is<Order>(o => o.CustomerOrderCode == "ORD-2024-001"),
            It.IsAny<CancellationToken>()),
            Times.Once);
    }

    [Fact]
    public async Task CreateOrderAsync_WithInsufficientStock_ReturnsFailure()
    {
        // Arrange
        var request = new CreateOrderRequest { ProductId = "PROD-001", Quantity = 100 };

        _mockStockService
            .Setup(s => s.CheckAsync(It.IsAny<string>(), It.IsAny<int>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(new StockResult { IsAvailable = false, Available = 5 });

        // Act
        var result = await _sut.CreateOrderAsync(request);

        // Assert
        Assert.False(result.IsSuccess);
        Assert.Equal("INSUFFICIENT_STOCK", result.Error!.Code);
        Assert.Contains("5 available", result.Error.Message);

        _mockRepository.Verify(
            r => r.CreateAsync(It.IsAny<Order>(), It.IsAny<CancellationToken>()),
            Times.Never);
    }

    [Theory]
    [InlineData(0)]
    [InlineData(-1)]
    [InlineData(-100)]
    public async Task CreateOrderAsync_WithInvalidQuantity_ReturnsValidationError(int quantity)
    {
        // Arrange
        var request = new CreateOrderRequest { ProductId = "PROD-001", Quantity = quantity };

        _mockValidator
            .Setup(v => v.ValidateAsync(request, It.IsAny<CancellationToken>()))
            .ReturnsAsync(new ValidationResult(new[]
            {
                new ValidationFailure("Quantity", "Quantity must be greater than 0")
            }));

        // Act
        var result = await _sut.CreateOrderAsync(request);

        // Assert
        Assert.False(result.IsSuccess);
        Assert.Equal("VALIDATION_ERROR", result.Error!.Code);
    }
}
```

### Integration Tests with WebApplicationFactory

```csharp
public class ProductsApiTests : IClassFixture<WebApplicationFactory<Program>>
{
    private readonly WebApplicationFactory<Program> _factory;
    private readonly HttpClient _client;

    public ProductsApiTests(WebApplicationFactory<Program> factory)
    {
        _factory = factory.WithWebHostBuilder(builder =>
        {
            builder.ConfigureServices(services =>
            {
                // Replace real database with in-memory
                services.RemoveAll<DbContextOptions<AppDbContext>>();
                services.AddDbContext<AppDbContext>(options =>
                    options.UseInMemoryDatabase("TestDb"));

                // Replace Redis with memory cache
                services.RemoveAll<IDistributedCache>();
                services.AddDistributedMemoryCache();
            });
        });

        _client = _factory.CreateClient();
    }

    [Fact]
    public async Task GetProduct_WithValidId_ReturnsProduct()
    {
        // Arrange
        using var scope = _factory.Services.CreateScope();
        var context = scope.ServiceProvider.GetRequiredService<AppDbContext>();

        context.Products.Add(new Product
        {
            Id = "TEST-001",
            Name = "Test Product",
            Price = 99.99m
        });
        await context.SaveChangesAsync();

        // Act
        var response = await _client.GetAsync("/api/products/TEST-001");

        // Assert
        response.EnsureSuccessStatusCode();
        var product = await response.Content.ReadFromJsonAsync<Product>();
        Assert.Equal("Test Product", product!.Name);
    }

    [Fact]
    public async Task GetProduct_WithInvalidId_Returns404()
    {
        // Act
        var response = await _client.GetAsync("/api/products/NONEXISTENT");

        // Assert
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }
}
```

## Best Practices

### DO

1. **Use async/await** all the way through the call stack
2. **Inject dependencies** through constructor injection
3. **Use IOptions<T>** for typed configuration
4. **Return Result types** instead of throwing exceptions for business logic
5. **Use CancellationToken** in all async methods
6. **Prefer Dapper** for read-heavy, performance-critical queries
7. **Use EF Core** for complex domain models with change tracking
8. **Cache aggressively** with proper invalidation strategies
9. **Write unit tests** for business logic, integration tests for APIs
10. **Use record types** for DTOs and immutable data
11. **Use `TypedResults`** instead of `Results` in minimal APIs — compile-time type safety and accurate OpenAPI metadata
12. **Return named record types** from endpoints, never anonymous types — anonymous types don't appear in the OpenAPI schema

### DON'T

1. **Don't block on async** with `.Result` or `.Wait()`
2. **Don't use async void** except for event handlers
3. **Don't catch generic Exception** without re-throwing or logging
4. **Don't hardcode** configuration values
5. **Don't expose EF entities** directly in APIs (use DTOs)
6. **Don't forget** `AsNoTracking()` for read-only queries
7. **Don't ignore** CancellationToken parameters
8. **Don't create** `new HttpClient()` manually (use IHttpClientFactory)
9. **Don't mix** sync and async code unnecessarily
10. **Don't skip** validation at API boundaries
11. **Don't return anonymous types** from endpoints (`new { code, message }`) — use a named record

## Common Pitfalls

- **N+1 Queries**: Use `.Include()` or explicit joins
- **Memory Leaks**: Dispose IDisposable resources, use `using`
- **Deadlocks**: Don't mix sync and async, use ConfigureAwait(false) in libraries
- **Over-fetching**: Select only needed columns, use projections
- **Missing Indexes**: Check query plans, add indexes for common filters
- **Timeout Issues**: Configure appropriate timeouts for HTTP clients
- **Cache Stampede**: Use distributed locks for cache population
