using System.Data;
using System.Security.Cryptography;
using System.Text;
using Microsoft.Data.SqlClient;

public sealed class ApiDatabase(string? connectionString)
{
    public const string UserIdKey = "current-user-id";
    public bool IsConfigured => !string.IsNullOrWhiteSpace(connectionString);

    public async Task<SqlConnection> OpenAsync(CancellationToken cancellationToken = default)
    {
        if (!IsConfigured)
            throw new InvalidOperationException("ConnectionStrings:YoutubeSimulationDb is not configured.");
        var connection = new SqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = connection.CreateCommand();
        command.CommandText = """
            SET ANSI_NULLS ON;
            SET QUOTED_IDENTIFIER ON;
            SET ANSI_PADDING ON;
            SET ANSI_WARNINGS ON;
            SET ARITHABORT ON;
            SET CONCAT_NULL_YIELDS_NULL ON;
            SET NUMERIC_ROUNDABORT OFF;
            """;
        await command.ExecuteNonQueryAsync(cancellationToken);
        return connection;
    }

    public async Task CheckReadyAsync(CancellationToken cancellationToken)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = new SqlCommand("""
            SELECT CASE WHEN OBJECT_ID(N'dbo.Users', N'U') IS NOT NULL
                AND OBJECT_ID(N'dbo.Videos', N'U') IS NOT NULL
                AND OBJECT_ID(N'dbo.UserSessions', N'U') IS NOT NULL
                THEN 1 ELSE 0 END;
            """, connection);
        if (Convert.ToInt32(await command.ExecuteScalarAsync(cancellationToken)) != 1)
            throw new SqlExceptionProxy("YoutubeSimulationDb schema is not initialized.");
    }

    public async Task<long?> FindSessionUserAsync(string token, CancellationToken cancellationToken)
    {
        await using var connection = await OpenAsync(cancellationToken);
        await using var command = new SqlCommand("""
            UPDATE s SET LastSeenAt = SYSUTCDATETIME()
            OUTPUT inserted.UserId
            FROM dbo.UserSessions AS s
            INNER JOIN dbo.Users AS u ON u.UserId = s.UserId
            WHERE s.RefreshTokenHash = @TokenHash
              AND s.RevokedAt IS NULL AND s.ExpiresAt > SYSUTCDATETIME()
              AND u.IsActive = 1;
            """, connection);
        command.Parameters.Add("@TokenHash", SqlDbType.Binary, 32).Value = SHA256.HashData(Encoding.UTF8.GetBytes(token));
        var result = await command.ExecuteScalarAsync(cancellationToken);
        return result is null or DBNull ? null : Convert.ToInt64(result);
    }
}

public static class ApiSql
{
    public static long UserId(HttpContext context) => Convert.ToInt64(context.Items[ApiDatabase.UserIdKey]);
    public static long? OptionalUserId(HttpContext context) =>
        context.Items.TryGetValue(ApiDatabase.UserIdKey, out var value) ? Convert.ToInt64(value) : null;

    public static SqlParameter Add(this SqlCommand command, string name, SqlDbType type, object? value, int size = 0)
    {
        var parameter = size == 0 ? command.Parameters.Add(name, type) : command.Parameters.Add(name, type, size);
        parameter.Value = value ?? DBNull.Value;
        return parameter;
    }

    public static async Task<long?> ScalarIdAsync(SqlCommand command, CancellationToken cancellationToken)
    {
        var result = await command.ExecuteScalarAsync(cancellationToken);
        return result is null or DBNull ? null : Convert.ToInt64(result);
    }

    public static async Task<bool> IsVideoViewableAsync(SqlConnection connection, long? userId, long videoId,
        CancellationToken cancellationToken)
    {
        await using var command = new SqlCommand("""
            SELECT CASE WHEN EXISTS (
                SELECT 1 FROM dbo.Videos v
                INNER JOIN dbo.Channels c ON c.ChannelId = v.ChannelId
                WHERE v.VideoId = @VideoId AND v.DeletedAt IS NULL
                  AND v.VideoStatus = 'ready'
                  AND (v.Visibility IN ('public', 'unlisted')
                       OR (@UserId IS NOT NULL AND (c.OwnerUserId = @UserId
                           OR EXISTS (SELECT 1 FROM dbo.ChannelMembers m WHERE m.ChannelId = c.ChannelId
                               AND m.UserId = @UserId AND m.MembershipStatus = 'active'
                               AND m.MemberRole IN ('manager', 'editor')))))
            ) THEN 1 ELSE 0 END;
            """, connection);
        command.Add("@VideoId", SqlDbType.BigInt, videoId);
        command.Add("@UserId", SqlDbType.BigInt, userId);
        return Convert.ToInt32(await command.ExecuteScalarAsync(cancellationToken)) == 1;
    }
}

public static class ApiFiles
{
    private static readonly HashSet<string> AllowedVideoExtensions = new(StringComparer.OrdinalIgnoreCase)
        { ".mp4", ".mov", ".webm", ".m4v", ".avi", ".mkv" };
    private static readonly HashSet<string> AllowedStorageExtensions = new(AllowedVideoExtensions, StringComparer.OrdinalIgnoreCase)
        { ".jpg", ".jpeg", ".png", ".webp" };

    public static bool IsAllowedVideo(IFormFile file) =>
        file.Length > 0 && AllowedVideoFileName(file.FileName);

    public static bool AllowedVideoFileName(string fileName) =>
        !string.IsNullOrWhiteSpace(fileName)
        && fileName.Length <= 260
        && Path.GetFileName(fileName) == fileName
        && fileName.IndexOfAny(Path.GetInvalidFileNameChars()) < 0
        && AllowedVideoExtensions.Contains(Path.GetExtension(fileName));

    public static bool IsStorageKey(string storageKey)
    {
        var extension = Path.GetExtension(storageKey);
        return AllowedStorageExtensions.Contains(extension)
            && Guid.TryParseExact(storageKey[..^extension.Length], "N", out _);
    }

    public static string NewStorageKey(string extension) => $"{Guid.NewGuid():N}{extension.ToLowerInvariant()}";

    public static string GetMimeType(string extension) => extension.ToLowerInvariant() switch
    {
        ".webm" => "video/webm",
        ".mov" => "video/quicktime",
        ".m4v" => "video/x-m4v",
        ".avi" => "video/x-msvideo",
        ".mkv" => "video/x-matroska",
        ".jpg" or ".jpeg" => "image/jpeg",
        ".png" => "image/png",
        ".webp" => "image/webp",
        _ => "video/mp4"
    };

    public static bool IsVideoMimeType(string? mimeType) =>
        mimeType is not null && mimeType.StartsWith("video/", StringComparison.OrdinalIgnoreCase);

    public static bool IsImageMimeType(string? mimeType) =>
        mimeType is not null && mimeType.StartsWith("image/", StringComparison.OrdinalIgnoreCase);

    public static string ToSafeLikePattern(string input)
    {
        var escaped = input.Replace("~", "~~", StringComparison.Ordinal)
            .Replace("%", "~%", StringComparison.Ordinal)
            .Replace("_", "~_", StringComparison.Ordinal)
            .Replace("[", "~[", StringComparison.Ordinal);
        return $"%{escaped}%";
    }
}

public sealed class SqlExceptionProxy(string message) : Exception(message);
