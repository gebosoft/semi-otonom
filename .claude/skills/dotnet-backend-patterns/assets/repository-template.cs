// Repository Implementation Template for .NET 8+
//
// LAYERING — read this before copying:
//   YourApp.Domain.Entities      → Entity classes (Product, Order, …)
//   YourApp.Domain.Repositories  → Repository interfaces + IUnitOfWork (NO SaveChangesAsync on repos)
//   YourApp.Infrastructure.Persistence            → AppDbContext (implements IUnitOfWork)
//   YourApp.Infrastructure.Persistence.Repositories → EF Core / Dapper implementations (stage only)
//
// Repositories STAGE changes (Add/Update/Remove). The IUnitOfWork is the single
// commit point. One service operation = one SaveChangesAsync call, regardless
// of how many repositories it touched.

using System.Data;
using System.Linq.Expressions;
using Dapper;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using Microsoft.EntityFrameworkCore.Storage;
using Microsoft.Extensions.Logging;

// =============================================================================
// DOMAIN LAYER — no dependencies on EF Core, Dapper, or any infrastructure.
// =============================================================================

namespace YourApp.Domain.Entities
{
    public class Product
    {
        public string Id { get; set; } = string.Empty;
        public string Name { get; set; } = string.Empty;
        public string Sku { get; set; } = string.Empty;
        public decimal Price { get; set; }
        public int CategoryId { get; set; }
        public int Stock { get; set; }
        public bool IsDeleted { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }

        public Category? Category { get; set; }
    }

    public class Category
    {
        public int Id { get; set; }
        public string Name { get; set; } = string.Empty;
        public ICollection<Product> Products { get; set; } = new List<Product>();
    }

    public class Order
    {
        public int Id { get; set; }
        public string CustomerOrderCode { get; set; } = string.Empty;
        public decimal Total { get; set; }
        public DateTime CreatedAt { get; set; }
        public ICollection<OrderItem> Items { get; set; } = new List<OrderItem>();
    }

    public class OrderItem
    {
        public int Id { get; set; }
        public int OrderId { get; set; }
        public string ProductId { get; set; } = string.Empty;
        public int Quantity { get; set; }
        public decimal UnitPrice { get; set; }

        public Order? Order { get; set; }
        public Product? Product { get; set; }
    }

    public class ProductSearchRequest
    {
        public string? SearchTerm { get; set; }
        public int? CategoryId { get; set; }
        public decimal? MinPrice { get; set; }
        public decimal? MaxPrice { get; set; }
        public int? Page { get; set; }
        public int? PageSize { get; set; }
    }
}

namespace YourApp.Domain.Repositories
{
    using YourApp.Domain.Entities;

    // Repository interface — STAGE only. No SaveChangesAsync here.
    public interface IProductRepository
    {
        Task<Product?> GetByIdAsync(string id, CancellationToken ct = default);
        Task<Product?> GetBySkuAsync(string sku, CancellationToken ct = default);
        Task<(IReadOnlyList<Product> Items, int TotalCount)> SearchAsync(
            ProductSearchRequest request, CancellationToken ct = default);
        Task<IReadOnlyList<Product>> GetByIdsAsync(
            IEnumerable<string> ids, CancellationToken ct = default);
        Task AddAsync(Product product, CancellationToken ct = default);
        void Update(Product product);
        void Remove(Product product);
    }

    public interface IOrderRepository
    {
        Task<Order?> GetByIdAsync(int id, CancellationToken ct = default);
        Task AddAsync(Order order, CancellationToken ct = default);
        void Update(Order order);
    }

    // Unit of Work — the single commit point.
    // The minimal contract is just SaveChangesAsync. Extend with explicit
    // transaction methods only when you need atomicity beyond the DbContext's
    // built-in transactional boundary.
    public interface IUnitOfWork
    {
        Task<int> SaveChangesAsync(CancellationToken ct = default);
        Task BeginTransactionAsync(CancellationToken ct = default);
        Task CommitTransactionAsync(CancellationToken ct = default);
        Task RollbackTransactionAsync(CancellationToken ct = default);
    }

    // Specification pattern — Domain-level query description, infrastructure-free.
    public interface ISpecification<T>
    {
        Expression<Func<T, bool>> Criteria { get; }
        List<Expression<Func<T, object>>> Includes { get; }
        List<string> IncludeStrings { get; }
        Expression<Func<T, object>>? OrderBy { get; }
        Expression<Func<T, object>>? OrderByDescending { get; }
        int? Take { get; }
        int? Skip { get; }
    }

    public abstract class BaseSpecification<T> : ISpecification<T>
    {
        public Expression<Func<T, bool>> Criteria { get; private set; } = _ => true;
        public List<Expression<Func<T, object>>> Includes { get; } = new();
        public List<string> IncludeStrings { get; } = new();
        public Expression<Func<T, object>>? OrderBy { get; private set; }
        public Expression<Func<T, object>>? OrderByDescending { get; private set; }
        public int? Take { get; private set; }
        public int? Skip { get; private set; }

        protected void AddCriteria(Expression<Func<T, bool>> criteria) => Criteria = criteria;
        protected void AddInclude(Expression<Func<T, object>> include) => Includes.Add(include);
        protected void AddInclude(string include) => IncludeStrings.Add(include);
        protected void ApplyOrderBy(Expression<Func<T, object>> orderBy) => OrderBy = orderBy;
        protected void ApplyOrderByDescending(Expression<Func<T, object>> orderBy) => OrderByDescending = orderBy;
        protected void ApplyPaging(int skip, int take) { Skip = skip; Take = take; }
    }

    public class ProductsByCategorySpec : BaseSpecification<Product>
    {
        public ProductsByCategorySpec(int categoryId, int page, int pageSize)
        {
            AddCriteria(p => p.CategoryId == categoryId);
            AddInclude(p => p.Category!);
            ApplyOrderBy(p => p.Name);
            ApplyPaging((page - 1) * pageSize, pageSize);
        }
    }
}

// =============================================================================
// INFRASTRUCTURE LAYER — implements Domain abstractions using EF Core / Dapper.
// =============================================================================

namespace YourApp.Infrastructure.Persistence
{
    using YourApp.Domain.Entities;
    using YourApp.Domain.Repositories;

    // AppDbContext implements IUnitOfWork directly — keeps the seam minimal.
    public class AppDbContext : DbContext, IUnitOfWork
    {
        private IDbContextTransaction? _transaction;

        public AppDbContext(DbContextOptions<AppDbContext> options) : base(options) { }

        public DbSet<Product> Products => Set<Product>();
        public DbSet<Category> Categories => Set<Category>();
        public DbSet<Order> Orders => Set<Order>();
        public DbSet<OrderItem> OrderItems => Set<OrderItem>();

        protected override void OnModelCreating(ModelBuilder modelBuilder)
        {
            modelBuilder.ApplyConfigurationsFromAssembly(typeof(AppDbContext).Assembly);
            modelBuilder.Entity<Product>().HasQueryFilter(p => !p.IsDeleted);
        }

        Task<int> IUnitOfWork.SaveChangesAsync(CancellationToken ct) =>
            base.SaveChangesAsync(ct);

        async Task IUnitOfWork.BeginTransactionAsync(CancellationToken ct) =>
            _transaction = await Database.BeginTransactionAsync(ct);

        async Task IUnitOfWork.CommitTransactionAsync(CancellationToken ct)
        {
            if (_transaction is null) return;
            await _transaction.CommitAsync(ct);
            await _transaction.DisposeAsync();
            _transaction = null;
        }

        async Task IUnitOfWork.RollbackTransactionAsync(CancellationToken ct)
        {
            if (_transaction is null) return;
            await _transaction.RollbackAsync(ct);
            await _transaction.DisposeAsync();
            _transaction = null;
        }
    }

    public class ProductConfiguration : IEntityTypeConfiguration<Product>
    {
        public void Configure(EntityTypeBuilder<Product> builder)
        {
            builder.ToTable("Products");
            builder.HasKey(p => p.Id);
            builder.Property(p => p.Id).HasMaxLength(40);
            builder.Property(p => p.Name).HasMaxLength(200).IsRequired();
            builder.Property(p => p.Sku).HasMaxLength(50).IsRequired();
            builder.Property(p => p.Price).HasPrecision(18, 2);

            builder.HasIndex(p => p.Sku).IsUnique();
            builder.HasIndex(p => p.CategoryId);
            builder.HasIndex(p => new { p.CategoryId, p.Name });

            builder.HasOne(p => p.Category)
                .WithMany(c => c.Products)
                .HasForeignKey(p => p.CategoryId);
        }
    }
}

namespace YourApp.Infrastructure.Persistence.Repositories
{
    using YourApp.Domain.Entities;
    using YourApp.Domain.Repositories;
    using YourApp.Infrastructure.Persistence;

    // Dapper implementation — high-performance read path.
    // Dapper repos still don't commit; if they execute writes, those writes
    // are auto-committed by the connection. Mix carefully with EF Core UoW;
    // typical pattern is "Dapper for reads, EF Core for writes".
    public class DapperProductRepository : IProductRepository
    {
        private readonly IDbConnection _connection;
        private readonly ILogger<DapperProductRepository> _logger;

        public DapperProductRepository(
            IDbConnection connection,
            ILogger<DapperProductRepository> logger)
        {
            _connection = connection;
            _logger = logger;
        }

        public async Task<Product?> GetByIdAsync(string id, CancellationToken ct = default)
        {
            const string sql = """
                SELECT Id, Name, Sku, Price, CategoryId, Stock, CreatedAt, UpdatedAt
                FROM Products
                WHERE Id = @Id AND IsDeleted = 0
                """;

            return await _connection.QueryFirstOrDefaultAsync<Product>(
                new CommandDefinition(sql, new { Id = id }, cancellationToken: ct));
        }

        public async Task<Product?> GetBySkuAsync(string sku, CancellationToken ct = default)
        {
            const string sql = """
                SELECT Id, Name, Sku, Price, CategoryId, Stock, CreatedAt, UpdatedAt
                FROM Products
                WHERE Sku = @Sku AND IsDeleted = 0
                """;

            return await _connection.QueryFirstOrDefaultAsync<Product>(
                new CommandDefinition(sql, new { Sku = sku }, cancellationToken: ct));
        }

        public async Task<(IReadOnlyList<Product> Items, int TotalCount)> SearchAsync(
            ProductSearchRequest request,
            CancellationToken ct = default)
        {
            // ... build SQL with conditional WHERE clauses, see ef-core-best-practices.md
            // for the equivalent EF Core pattern.
            throw new NotImplementedException("See SearchAsync example in skill body.");
        }

        public async Task<IReadOnlyList<Product>> GetByIdsAsync(
            IEnumerable<string> ids,
            CancellationToken ct = default)
        {
            var idList = ids.ToList();
            if (idList.Count == 0) return Array.Empty<Product>();

            const string sql = """
                SELECT Id, Name, Sku, Price, CategoryId, Stock, CreatedAt, UpdatedAt
                FROM Products
                WHERE Id IN @Ids AND IsDeleted = 0
                """;

            var rows = await _connection.QueryAsync<Product>(
                new CommandDefinition(sql, new { Ids = idList }, cancellationToken: ct));
            return rows.ToList();
        }

        // Dapper write paths typically execute immediately. If you need them
        // inside an EF Core UoW, share the same DbConnection/Transaction.
        public Task AddAsync(Product product, CancellationToken ct = default) =>
            throw new NotSupportedException("Use EfCoreProductRepository for writes.");

        public void Update(Product product) =>
            throw new NotSupportedException("Use EfCoreProductRepository for writes.");

        public void Remove(Product product) =>
            throw new NotSupportedException("Use EfCoreProductRepository for writes.");
    }

    // EF Core implementation — STAGE only. No SaveChangesAsync calls in here;
    // the application service commits via IUnitOfWork.
    public class EfCoreProductRepository : IProductRepository
    {
        private readonly AppDbContext _context;
        private readonly ILogger<EfCoreProductRepository> _logger;

        public EfCoreProductRepository(AppDbContext context, ILogger<EfCoreProductRepository> logger)
        {
            _context = context;
            _logger = logger;
        }

        public Task<Product?> GetByIdAsync(string id, CancellationToken ct = default) =>
            _context.Products.AsNoTracking().FirstOrDefaultAsync(p => p.Id == id, ct);

        public Task<Product?> GetBySkuAsync(string sku, CancellationToken ct = default) =>
            _context.Products.AsNoTracking().FirstOrDefaultAsync(p => p.Sku == sku, ct);

        public async Task<(IReadOnlyList<Product> Items, int TotalCount)> SearchAsync(
            ProductSearchRequest request,
            CancellationToken ct = default)
        {
            var query = _context.Products.AsNoTracking();

            if (!string.IsNullOrWhiteSpace(request.SearchTerm))
            {
                var term = request.SearchTerm.ToLower();
                query = query.Where(p =>
                    p.Name.ToLower().Contains(term) ||
                    p.Sku.ToLower().Contains(term));
            }

            if (request.CategoryId.HasValue)
                query = query.Where(p => p.CategoryId == request.CategoryId.Value);

            if (request.MinPrice.HasValue)
                query = query.Where(p => p.Price >= request.MinPrice.Value);

            if (request.MaxPrice.HasValue)
                query = query.Where(p => p.Price <= request.MaxPrice.Value);

            var totalCount = await query.CountAsync(ct);

            var page = request.Page ?? 1;
            var pageSize = request.PageSize ?? 50;

            var items = await query
                .OrderBy(p => p.Name)
                .Skip((page - 1) * pageSize)
                .Take(pageSize)
                .ToListAsync(ct);

            return (items, totalCount);
        }

        public async Task<IReadOnlyList<Product>> GetByIdsAsync(
            IEnumerable<string> ids,
            CancellationToken ct = default)
        {
            var idList = ids.ToList();
            if (idList.Count == 0) return Array.Empty<Product>();

            return await _context.Products
                .AsNoTracking()
                .Where(p => idList.Contains(p.Id))
                .ToListAsync(ct);
        }

        // STAGE — no SaveChangesAsync. The caller commits via IUnitOfWork.
        public async Task AddAsync(Product product, CancellationToken ct = default) =>
            await _context.Products.AddAsync(product, ct);

        public void Update(Product product) => _context.Products.Update(product);

        public void Remove(Product product)
        {
            // Soft delete: flip the flag, the global query filter hides it.
            product.IsDeleted = true;
            product.UpdatedAt = DateTime.UtcNow;
            _context.Products.Update(product);
        }
    }
}

// =============================================================================
// DI REGISTRATION — wire it up so callers see Domain abstractions only.
// =============================================================================
//
//   services.AddDbContext<AppDbContext>(opt => opt.UseSqlServer(connStr));
//   services.AddScoped<IUnitOfWork>(sp => sp.GetRequiredService<AppDbContext>());
//   services.AddScoped<IProductRepository, EfCoreProductRepository>();
//   services.AddScoped<IOrderRepository, EfCoreOrderRepository>();
//
// Application service usage:
//
//   public class CheckoutService
//   {
//       private readonly IProductRepository _products;
//       private readonly IOrderRepository _orders;
//       private readonly IUnitOfWork _unitOfWork;
//
//       public async Task<Result<Order>> PlaceOrderAsync(PlaceOrderRequest req, CancellationToken ct)
//       {
//           var product = await _products.GetByIdAsync(req.ProductId, ct);
//           if (product is null) return new Error("NOT_FOUND", "Product not found");
//
//           var order = Order.Create(product, req.Quantity);
//           await _orders.AddAsync(order, ct);
//           product.Stock -= req.Quantity;
//           _products.Update(product);
//
//           await _unitOfWork.SaveChangesAsync(ct);   // ← single atomic commit
//           return order;
//       }
//   }
