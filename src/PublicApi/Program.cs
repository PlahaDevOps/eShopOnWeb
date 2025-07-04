﻿using BlazorShared;
using FastEndpoints;
using FastEndpoints.Swagger;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.AspNetCore.Identity;
using Microsoft.eShopWeb.Infrastructure;
using Microsoft.eShopWeb.Infrastructure.Identity;
using Microsoft.eShopWeb.PublicApi;
using Microsoft.eShopWeb.PublicApi.Extensions;
using Microsoft.eShopWeb.PublicApi.Middleware;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Diagnostics.HealthChecks;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using NimblePros.Metronome;
using Microsoft.AspNetCore.Http;

var builder = WebApplication.CreateBuilder(args);

// 1) Add service defaults & Aspire components.
builder.AddAspireServiceDefaults();

// 2) FastEndpoints & Swagger
builder.Services.AddFastEndpoints();

// 3) Force-load test config if needed
builder.Configuration.AddConfigurationFile("appsettings.test.json");

// 4) Database contexts (local)
builder.Services.ConfigureLocalDatabaseContexts(builder.Configuration);

// 5) Identity
builder.Services.AddIdentity<ApplicationUser, IdentityRole>()
       .AddRoles<IdentityRole>()
       .AddEntityFrameworkStores<AppIdentityDbContext>()
       .AddDefaultTokenProviders();

// 6) Domain services
builder.Services.AddCustomServices(builder.Configuration);

// 7) Memory cache
builder.Services.AddMemoryCache();

// 8) JWT Authentication
builder.Services.AddJwtAuthentication();

// 9) CORS
const string CORS_POLICY = "CorsPolicy";
var configSection = builder.Configuration.GetRequiredSection(BaseUrlConfiguration.CONFIG_NAME);
builder.Services.Configure<BaseUrlConfiguration>(configSection);
var baseUrlConfig = configSection.Get<BaseUrlConfiguration>();
builder.Services.AddCorsPolicy(CORS_POLICY, baseUrlConfig!);

// 10) Controllers & AutoMapper
builder.Services.AddControllers();
builder.Services.AddAutoMapper(typeof(MappingProfile).Assembly);

// 11) Swagger
builder.Services.AddSwagger();

// 12) HealthChecks (with a "selfapi" check to always return Healthy)
builder.Services.AddHealthChecks()
       .AddCheck("selfapi", () => HealthCheckResult.Healthy());

// 13) Metronome & Seq
builder.Services.AddMetronome();
string seqUrl = builder.Configuration["Seq:ServerUrl"] ?? "http://localhost:5341";
builder.AddSeqEndpoint(connectionName: "seq", options =>
{
  options.ServerUrl = seqUrl;
});

var app = builder.Build();

app.Logger.LogInformation("PublicApi App created...");

// 14) Data seeding
await app.SeedDatabaseAsync();

// 15) Dev exception page
if (app.Environment.IsDevelopment())
{
  app.UseDeveloperExceptionPage();
}

// 16) Global exception handler
app.UseMiddleware<ExceptionMiddleware>();

app.UseHttpsRedirection();
app.UseRouting();
app.UseCors(CORS_POLICY);
app.UseAuthorization();

// 17) FastEndpoints & Swagger UI
app.UseFastEndpoints();
app.UseSwaggerGen();

// 18) Map only the "selfapi" health-check at /api/health
app.MapHealthChecks(
    "/api/health",
    new HealthCheckOptions {
        Predicate = registration => registration.Name == "selfapi",
        ResponseWriter = async (context, report) =>
        {
            context.Response.ContentType = "application/json";
            var result = System.Text.Json.JsonSerializer.Serialize(
                new { status = report.Status.ToString() }
            );
            await context.Response.WriteAsync(result);
        }
    }
);

app.Logger.LogInformation("LAUNCHING PublicApi");
app.Run();

public partial class Program { }
