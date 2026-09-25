using Api.Endpoints;
using SemiOtonom.Application.DependencyInjection;
using SemiOtonom.Infrastructure.DependencyInjection;

var builder = WebApplication.CreateBuilder(args);

// Add services to the container.
// Learn more about configuring OpenAPI at https://aka.ms/aspnet/openapi

builder.Services.AddOpenApi(options =>
{
    options.OpenApiVersion = Microsoft.OpenApi.OpenApiSpecVersion.OpenApi3_0;

options.AddSchemaTransformer((schema, context, cancellationToken) =>
{
    // .NET 10 integer alanları Integer|String flag birleşimi olarak modeller.
    // Serileştirmede 3.1'de union, 3.0'da anyOf olur; ikisi de üreteçleri kırar.
    if (schema.Type.HasValue &&
        schema.Type.Value.HasFlag(Microsoft.OpenApi.JsonSchemaType.Integer) &&
        schema.Type.Value.HasFlag(Microsoft.OpenApi.JsonSchemaType.String))
    {
        schema.Type = Microsoft.OpenApi.JsonSchemaType.Integer;
        schema.Pattern = null;
    }
    return Task.CompletedTask;
});
});

builder.Services.AddApplication(builder.Configuration);
builder.Services.AddInfrastructure(builder.Configuration);

var app = builder.Build();

// Configure the HTTP request pipeline.
if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
}

app.UseHttpsRedirection();

app.MapHealthEndpoints();

app.Run();
