namespace SemiOtonom.Domain.Repositories;

/// <summary>
/// Tek commit noktası. Repository'ler değişiklikleri yalnızca sahneye koyar
/// (AddAsync / Update / Remove); "işlem başarılı" kararını burası verir.
/// Böylece birden çok repository'e dokunan bir servis metodu tek atomik
/// veritabanı turuna iniyor.
/// </summary>
public interface IUnitOfWork
{
    Task<int> SaveChangesAsync(CancellationToken ct = default);
}
