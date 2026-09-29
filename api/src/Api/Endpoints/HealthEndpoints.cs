namespace Api.Endpoints;

/// <summary>
/// /health yanıtı. Şema adı (HealthResponse) ve alanları contracts/Api.json'a birebir
/// yansıyor — değiştirilirse üretilen TypeScript istemcisi ve web tarafı etkilenir.
/// </summary>
public sealed record HealthResponse(string Status, string Version, int State);

public static class HealthEndpoints
{
    public static IEndpointRouteBuilder MapHealthEndpoints(this IEndpointRouteBuilder app)
    {
        // WithName("GetHealth") OpenAPI operationId'sini belirliyor; sabit kalmalı.
        app.MapGet("/health", () => Results.Ok(new { status = "healthy" }))
           .WithName("GetHealth");

        return app;
    }
}
