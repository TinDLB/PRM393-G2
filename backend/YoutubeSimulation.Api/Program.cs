using Microsoft.AspNetCore.Http.Features;
using Microsoft.Data.SqlClient;

var builder = WebApplication.CreateBuilder(args);
builder.Services.Configure<FormOptions>(options => options.MultipartBodyLengthLimit = 2L * 1024 * 1024 * 1024);
builder.WebHost.ConfigureKestrel(options => options.Limits.MaxRequestBodySize = 2L * 1024 * 1024 * 1024);

var database = new ApiDatabase(builder.Configuration.GetConnectionString("YoutubeSimulationDb"));
var configuredMediaRoot = builder.Configuration["Media:Root"] ?? "media";
var mediaRoot = Path.GetFullPath(Path.IsPathRooted(configuredMediaRoot)
    ? configuredMediaRoot : Path.Combine(builder.Environment.ContentRootPath, configuredMediaRoot));
var maxUploadBytes = builder.Configuration.GetValue<long?>("Media:MaxUploadBytes") ?? 2L * 1024 * 1024 * 1024;
var chunkedVideoUploadStore = new ChunkedVideoUploadStore(mediaRoot);
var sessionDays = Math.Clamp(builder.Configuration.GetValue("Auth:SessionDays", 30), 1, 365);
var passwordResetEmailSender = new PasswordResetEmailSender(builder.Configuration);
var isDevelopment = builder.Environment.IsDevelopment();
var corsOrigins = builder.Configuration.GetSection("Cors:AllowedOrigins").Get<string[]>()
    ?? ["http://localhost:7357", "http://127.0.0.1:7357"];
builder.Services.AddCors(options => options.AddDefaultPolicy(policy => policy
    .SetIsOriginAllowed(origin =>
        corsOrigins.Contains(origin, StringComparer.OrdinalIgnoreCase)
        || isDevelopment
            && Uri.TryCreate(origin, UriKind.Absolute, out var uri)
            && uri.Scheme == Uri.UriSchemeHttp
            && uri.IsLoopback)
    .AllowAnyMethod()
    .AllowAnyHeader()
    .WithExposedHeaders("Accept-Ranges", "Content-Range", "Content-Length")));
var app = builder.Build();

app.UseExceptionHandler(errorApp => errorApp.Run(async context =>
{
    context.Response.StatusCode = StatusCodes.Status500InternalServerError;
    await Results.Problem(statusCode: StatusCodes.Status500InternalServerError,
        title: "An unexpected server error occurred.").ExecuteAsync(context);
}));

app.UseCors();

app.Use(async (context, next) =>
{
    var auth = context.Request.Headers.Authorization.ToString();
    if (auth.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase))
    {
        var token = auth["Bearer ".Length..].Trim();
        if (token.Length is > 0 and <= 256)
        {
            var userId = await database.FindSessionUserAsync(token, context.RequestAborted);
            if (userId.HasValue)
                context.Items[ApiDatabase.UserIdKey] = userId.Value;
        }
    }
    await next();
});

app.MapGet("/health/live", () => Results.Ok(new { status = "live" }));
app.MapGet("/health/ready", async (CancellationToken cancellationToken) =>
{
    if (!database.IsConfigured)
        return Results.Json(new { status = "not_ready", reason = "ConnectionStrings:YoutubeSimulationDb is not configured." },
            statusCode: StatusCodes.Status503ServiceUnavailable);
    try
    {
        await database.CheckReadyAsync(cancellationToken);
        return Results.Ok(new { status = "ready" });
    }
    catch (Exception ex) when (ex is SqlException or SqlExceptionProxy)
    {
        return Results.Json(new { status = "not_ready", reason = "The configured SQL Server database is unavailable or not initialized." },
            statusCode: StatusCodes.Status503ServiceUnavailable);
    }
});

var api = app.MapGroup("/api");
AuthEndpoints.Map(api, database, passwordResetEmailSender, sessionDays,
    app.Logger);
var protectedApi = api.MapGroup("").AddEndpointFilter(async (invocation, next) =>
    invocation.HttpContext.Items.ContainsKey(ApiDatabase.UserIdKey)
        ? await next(invocation)
        : Results.Unauthorized());

AccountEndpoints.Map(protectedApi, database);
VideoEndpoints.Map(api, protectedApi, database, mediaRoot);
SocialEndpoints.Map(protectedApi, database);
ChannelEndpoints.Map(protectedApi, database, mediaRoot, maxUploadBytes, chunkedVideoUploadStore);
NotificationEndpoints.Map(protectedApi, database);
CommentEndpoints.Map(protectedApi, database);
app.Run();

public partial class Program { }
