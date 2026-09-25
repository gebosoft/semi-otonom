using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace SemiOtonom.Infrastructure.DependencyInjection;

public static class InfrastructureServiceCollectionExtensions
{
    /// <summary>
    /// Infrastructure katmanının kayıtlarını ekler. Program.cs hangi veritabanının veya
    /// cache'in kullanıldığını bilmez; tek giriş noktası burası.
    /// </summary>
    public static IServiceCollection AddInfrastructure(
        this IServiceCollection services,
        IConfiguration configuration)
    {
        // Veritabanı henüz yok. İlk feature'da buraya gelecek sıra:
        //   services.AddDbContext<AppDbContext>(...);
        //   services.AddScoped<IUnitOfWork>(sp => sp.GetRequiredService<AppDbContext>());
        //   services.AddScoped<I...Repository, ...Repository>();
        return services;
    }
}
