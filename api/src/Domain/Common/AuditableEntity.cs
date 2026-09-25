namespace SemiOtonom.Domain.Common;

/// <summary>
/// Oluşturulduktan sonra güncellenen kayıtların taban tipi.
/// <see cref="UpdatedAt"/> domain kodu tarafından değil, Infrastructure'daki
/// SaveChanges interceptor'ı tarafından damgalanır.
/// </summary>
public abstract class AuditableEntity : Entity
{
    public DateTime? UpdatedAt { get; private set; }

    /// <summary>EF Core hydration için.</summary>
    protected AuditableEntity()
    {
    }
}
