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
        app.MapGet("/health", () => TypedResults.Ok(new HealthResponse("healthy", "1.0.0", 1)))
           .WithName("GetHealth");

        return app;
    }
}
