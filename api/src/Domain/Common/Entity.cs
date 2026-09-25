namespace SemiOtonom.Domain.Common;

/// <summary>
/// Yalnızca ekleme yapılan (append-only) kayıtların taban tipi: ledger satırları,
/// denetim kayıtları, outbox olayları. Durum değişikliği yeni satır üretiyorsa bu,
/// mevcut satırı güncelliyorsa <see cref="AuditableEntity"/> kullanılır.
/// </summary>
public abstract class Entity
{
    public Guid Id { get; protected set; }

    public DateTime CreatedAt { get; protected set; }

    /// <summary>EF Core hydration için.</summary>
    protected Entity()
    {
    }

    /// <summary>
    /// Sıralanabilir UUIDv7. Guid.NewGuid() rastgele olduğu için clustered index'te
    /// sayfa bölünmesine yol açıyor; v7 zaman önekli olduğundan insert'ler sona ekleniyor.
    /// </summary>
    protected static Guid NewId() => Guid.CreateVersion7();
}
