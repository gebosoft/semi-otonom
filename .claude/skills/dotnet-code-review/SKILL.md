---
name: dotnet-code-review
description: Reviewer's checklist for .NET/C# code — quality, correctness, and consistency. Use when reviewing a PR, auditing existing code, or validating a change before merge. NOT for scaffolding new code (use `dotnet-backend-patterns` for that). Trigger on phrases like "review this C# code", "audit the .NET service", "is this PR ready", or when the user opens a diff/PR for a .NET project.
---

# .NET / C# Code Review Checklist

This skill is a **reviewer's lens**. It is the companion to `dotnet-backend-patterns` (which teaches *how to build*). When you spot something that violates this checklist, fix it or flag it — don't just nod past it.

## When to use

- Reviewing a PR or diff
- Auditing an existing service for quality
- Validating a refactor before merge
- Spot-checking code style and convention adherence

If the user is **scaffolding new code or a new feature**, use `dotnet-backend-patterns` instead — that one has the architecture, repository layout, IUnitOfWork rules, EF/Dapper patterns, etc. This skill assumes those decisions were already made; it just verifies the result.

## Architecture & layering (delegated)

For repository placement, IUnitOfWork rules, EF Core configuration, Result types, entity base classes, and DI setup, defer to **`dotnet-backend-patterns`**. During review, verify:

- Repository **interfaces** live in `{Project}.Domain/Repositories/`, not in Application or Infrastructure.
- `IUnitOfWork` lives in `{Project}.Domain/Repositories/`.
- Repository **implementations** live in `{Project}.Infrastructure/Persistence/Repositories/`.
- Repository methods do NOT call `SaveChangesAsync` — only the application service does, via `IUnitOfWork`.
- Application services depend on Domain abstractions, not on `DbContext` or EF Core types directly.

If the PR puts repository interfaces in Application, or repos call `SaveChangesAsync` themselves, that's a fix-before-merge.

## Entity identity & auditing

Defined in `dotnet-backend-patterns`. During review, flag any of the following as fix-before-merge:

- Entity declares its own `Id` / `CreatedAt` / `UpdatedAt` instead of inheriting `Entity` or `AuditableEntity`.
- Field initializer like `public Guid Id { get; set; } = Guid.NewGuid();`. Should be UUIDv7 via `NewId()` in a factory method.
- Public parameterless constructor on an entity, or `public set` / `init` on entity properties — entities must be constructed only via the static factory.
- Service code mutates entity state by writing to a property (`account.PointsBalance -= ...`). Mutation must go through a behavior method (`account.DeductPoints(...)`).
- Service or interceptor manually setting `UpdatedAt`. The `AuditingInterceptor` should own this.
- EF configuration missing `.ConfigureEntityBase()` / `.ConfigureAuditableBase()` (or equivalent `ValueGeneratedNever()` on `Id`). Without it EF may generate its own ID and bypass the UUIDv7 factory.
- `AuditingInterceptor` exists but is not registered on `AppDbContext` via `options.AddInterceptors(...)`. Auditing silently doesn't work.

## Async / await

- All I/O methods are `async Task` / `async Task<T>` — no `async void` outside event handlers.
- No blocking on async (`.Result`, `.Wait()`, `.GetAwaiter().GetResult()`).
- Library code uses `.ConfigureAwait(false)` where the caller might be on a sync-context thread; ASP.NET Core app code does not need it.
- Every public async method accepts a `CancellationToken` parameter and threads it through to the next call.
- Parallelizable work uses `Task.WhenAll`, not sequential `await`s, when there's no dependency between calls.

## Dependency injection

- Constructor injection is used; no service locator anti-pattern (`IServiceProvider.GetService<T>()` inside business code).
- Lifetimes are deliberate: `Scoped` for per-request services and DbContext-bound things, `Singleton` for stateless infrastructure (caches, factories), `Transient` only when justified.
- `IOptions<T>` is used for configuration, not raw `IConfiguration` reads inside services.
- `HttpClient` is consumed via `IHttpClientFactory` — never `new HttpClient()` inside a class.
- For optional/nullable dependencies prefer constructor parameters with sensible defaults over runtime null-checks.
- `ArgumentNullException.ThrowIfNull(...)` only at public boundaries that can receive untrusted input — internal DI-injected dependencies don't need null guards.

## Configuration

- Strongly-typed options classes bound via `services.Configure<TOptions>(config.GetSection("..."))`.
- Required values are validated at startup (`ValidateDataAnnotations()` / `ValidateOnStart()`).
- Secrets are NOT in `appsettings.json` checked into git — User Secrets, env vars, or a secret manager.
- No magic strings for config keys; use `const string SectionName` on the options class.

## Error handling & logging

- Exceptions are used for **exceptional** failures only. Expected business outcomes (validation errors, not-found, conflict) flow through a `Result<T>` (or equivalent) — see `dotnet-backend-patterns`.
- Logging uses `Microsoft.Extensions.Logging` with structured templates: `_logger.LogInformation("Order {OrderId} created", order.Id)`, NOT string interpolation.
- No `catch (Exception ex)` followed by silent swallow. Every catch either re-throws, logs with context, or converts to a typed Result.
- Specific exception types over generic `Exception`: `ArgumentException`, `InvalidOperationException`, custom domain exceptions.
- No `throw ex` (loses stack trace) — use bare `throw`.

## Minimal API endpoints

- Endpoints return **named records**, never anonymous types (`new { code = ..., message = ... }`). Anonymous types don't surface in the OpenAPI schema, so client generators emit untyped or broken code. Declare a response record and return that — fix-before-merge.
- `TypedResults.*` over `Results.*` (`TypedResults.Ok(dto)`, `TypedResults.NotFound()`). It gives compile-time type safety on the response shape and emits correct OpenAPI metadata; `Results.*` erases both.

## Data access

- Read-only EF Core queries use `.AsNoTracking()`.
- Avoid N+1: `.Include()` for related data, or projections to a DTO with the columns you actually need.
- Migrations are reviewed alongside the code change. Destructive migrations (drop column, rename table) are flagged for explicit approval.
- Parameterized queries everywhere. No string concatenation into raw SQL.
- Indexes exist for common WHERE/ORDER BY columns; the migration that added the column also added the index.

## Testing

- Test framework is **xUnit** (consistent with `dotnet-backend-patterns`). Don't introduce MSTest or NUnit into a project that's already on xUnit.
- Mocking via **Moq** (or `NSubstitute` if the project already uses it). Don't mix.
- Assertions are clear: `Assert.Equal(expected, actual)` directly, or FluentAssertions if the project already uses it. Pick one style per project.
- Each test follows AAA: Arrange / Act / Assert, visually separated.
- Test names describe behavior: `Login_WithInvalidPassword_ReturnsFailure`, not `Test1`.
- Both happy path and at least one failure path covered for each public method that has branching logic.
- Integration tests use `WebApplicationFactory<Program>` with the real DI container, swapping only the bits that matter (DB → in-memory, external HTTP → fake).

## Security

- All user input is validated at the API boundary (FluentValidation, DataAnnotations, or explicit guard clauses).
- SQL queries are parameterized.
- Authorization checks at the endpoint level (`[Authorize]`, policy-based attributes), not buried inside services.
- Secrets aren't logged. PII isn't logged at Info level. Tokens/passwords never reach logs.
- `[ApiController]` automatic model validation is enabled, or equivalent manual validation.

## Code quality

- SOLID violations flagged: classes doing too much (SRP), interfaces with unrelated methods (ISP), implementations that can't be substituted (LSP).
- No copy-pasted logic across two services — extract a helper or a shared utility.
- Names reflect the domain. `customerOrderCode` over `code`, `pendingShipments` over `list`. No abbreviations (`ord`, `usr`).
- Methods are focused and short. A method longer than ~40 lines is a smell unless it's a single linear pipeline.
- `IDisposable` resources are released via `using` declarations or explicit `Dispose`/`DisposeAsync`.
- C# 12+ features used where they improve readability: collection expressions, primary constructors for simple classes, `required` properties, file-scoped namespaces.

## Documentation

- XML doc comments are **not required everywhere**. Default to no comments. Add them only on:
  - Public APIs of a published library (NuGet package, SDK).
  - Non-obvious behavior, surprising invariants, intentional workarounds.
  - Public interfaces whose method names alone don't fully describe the contract.
- A method named `GetActiveCustomersAsync(CancellationToken ct)` doesn't need an XML comment saying "Gets active customers." That comment is noise.
- `README.md` exists for the API project and explains how to run locally and where to find configuration.

## Performance — quick wins to verify

- Hot-path allocations: `StringBuilder` for repeated concatenation, `Span<T>`/`ReadOnlySpan<T>` where appropriate, pooled buffers via `ArrayPool<T>`.
- Caching considered for repeated, expensive reads (memory cache for in-process, Redis for cross-process).
- No synchronous I/O on the request thread.
- Pagination on every endpoint that returns a list.

## Reviewer output

When you complete a review, summarize:

1. **Must-fix before merge** — correctness, security, layering violations.
2. **Should-fix** — quality and maintainability concerns that aren't blockers but matter.
3. **Nits** — style, naming, optional improvements.

Don't bury the must-fix items in a wall of nits.
