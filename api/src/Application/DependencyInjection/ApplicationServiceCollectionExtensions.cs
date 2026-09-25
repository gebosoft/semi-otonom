using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace SemiOtonom.Application.DependencyInjection;

public static class ApplicationServiceCollectionExtensions
{
    /// <summary>
    /// Application katmanının kayıtlarını ekler. Program.cs bu katmanın iç yapısını bilmez;
    /// tek giriş noktası burası.
    /// </summary>
    public static IServiceCollection AddApplication(
        this IServiceCollection services,
        IConfiguration configuration)
    {
        // Uygulama servisleri, validator'lar ve IOptions bağlamaları ilk feature'da buraya.
        return services;
    }
}
