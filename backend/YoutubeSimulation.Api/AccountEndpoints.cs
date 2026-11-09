using System.Data;
using Microsoft.Data.SqlClient;

public static class AccountEndpoints
{
    public static void Map(RouteGroupBuilder api, ApiDatabase database)
    {
        api.MapGet("/account/me", async (HttpContext context, CancellationToken ct) =>
        {
            await using var connection = await database.OpenAsync(ct);
            await using var command = new SqlCommand("""
                SELECT u.UserId, u.DisplayName, u.Email, u.AvatarUrl, COALESCE(p.ThemeMode, 'system')
                FROM dbo.Users u LEFT JOIN dbo.UserPreferences p ON p.UserId = u.UserId
                WHERE u.UserId = @UserId AND u.IsActive = 1;
                """, connection);
            command.Add("@UserId", SqlDbType.BigInt, ApiSql.UserId(context));
            await using var reader = await command.ExecuteReaderAsync(ct);
            if (!await reader.ReadAsync(ct))
                return Results.Unauthorized();
            return Results.Ok(new
            {
                user = new UserDto(reader.GetInt64(0), reader.GetString(1), reader.GetString(2),
                    reader.IsDBNull(3) ? null : reader.GetString(3)),
                theme = reader.GetString(4),
                preferences = new { themeMode = reader.GetString(4) }
            });
        });

        api.MapGet("/account/me/theme", async (HttpContext context, CancellationToken ct) =>
        {
            await using var connection = await database.OpenAsync(ct);
            await using var command = new SqlCommand("""
                SELECT COALESCE((SELECT ThemeMode FROM dbo.UserPreferences WHERE UserId = @UserId), 'system');
                """, connection);
            command.Add("@UserId", SqlDbType.BigInt, ApiSql.UserId(context));
            var theme = Convert.ToString(await command.ExecuteScalarAsync(ct)) ?? "system";
            return Results.Ok(new { theme, themeMode = theme });
        });

        async Task<IResult> UpdateThemeAsync(ThemeRequest request, HttpContext context, CancellationToken ct)
        {
            var theme = request.ThemeMode?.Trim().ToLowerInvariant();
            if (theme is not ("system" or "light" or "dark"))
                return Results.ValidationProblem(new Dictionary<string, string[]> { ["themeMode"] = ["Theme must be system, light, or dark."] });
            await using var connection = await database.OpenAsync(ct);
            await using var command = new SqlCommand("""
                UPDATE dbo.UserPreferences SET ThemeMode = @Theme, UpdatedAt = SYSUTCDATETIME()
                WHERE UserId = @UserId;
                IF @@ROWCOUNT = 0
                    INSERT dbo.UserPreferences (UserId, ThemeMode) VALUES (@UserId, @Theme);
                """, connection);
            command.Add("@UserId", SqlDbType.BigInt, ApiSql.UserId(context));
            command.Add("@Theme", SqlDbType.VarChar, theme, 10);
            await command.ExecuteNonQueryAsync(ct);
            return Results.Ok(new { theme, themeMode = theme });
        }
        api.MapPut("/account/me/theme", UpdateThemeAsync);
        api.MapPut("/account/preferences", UpdateThemeAsync);
    }
}

public sealed record ThemeRequest(string? ThemeMode);
