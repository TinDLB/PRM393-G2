using System.Data;
using Microsoft.Data.SqlClient;

public static class VideoEndpoints
{
    internal const string VideoSelect = """
        SELECT v.VideoId, v.Title, c.ChannelName, c.ChannelId, v.Description, v.DurationSeconds,
               COALESCE(cat.CategoryName, N''),
               COALESCE((SELECT TOP (1) a.StorageKey FROM dbo.VideoAssets a
                         WHERE a.VideoId = v.VideoId AND a.AssetType = 'thumbnail' ORDER BY a.VideoAssetId DESC),
                        v.ThumbnailStorageKey), v.Visibility,
               CONVERT(bit, CASE WHEN reaction.ReactionType = 'like' THEN 1 ELSE 0 END) AS IsLiked,
               CONVERT(bit, CASE WHEN saved.VideoId IS NULL THEN 0 ELSE 1 END) AS IsSaved,
               CONVERT(bit, CASE WHEN subscription.ChannelId IS NULL THEN 0 ELSE 1 END) AS IsSubscribed
        FROM dbo.Videos v
        INNER JOIN dbo.Channels c ON c.ChannelId = v.ChannelId AND c.IsActive = 1
        LEFT JOIN dbo.VideoCategories cat ON cat.CategoryId = v.CategoryId
        LEFT JOIN dbo.VideoReactions reaction ON reaction.VideoId = v.VideoId AND reaction.UserId = @UserId
        LEFT JOIN dbo.WatchLater saved ON saved.VideoId = v.VideoId AND saved.UserId = @UserId
        LEFT JOIN dbo.ChannelSubscriptions subscription
          ON subscription.ChannelId = v.ChannelId AND subscription.SubscriberUserId = @UserId
        """;

    public static void Map(RouteGroupBuilder api, RouteGroupBuilder protectedApi, ApiDatabase database, string mediaRoot)
    {
        api.MapGet("/categories", async (CancellationToken ct) =>
        {
            await using var connection = await database.OpenAsync(ct);
            await using var command = new SqlCommand("""
                SELECT CategoryId, CategoryName FROM dbo.VideoCategories WHERE IsActive = 1 ORDER BY DisplayOrder, CategoryName;
                """, connection);
            await using var reader = await command.ExecuteReaderAsync(ct);
            var categories = new List<object>();
            while (await reader.ReadAsync(ct))
                categories.Add(new { categoryId = reader.GetInt32(0), categoryName = reader.GetString(1) });
            return Results.Ok(new { items = categories });
        });

        api.MapGet("/videos", async (string? category, string? query, HttpContext context, CancellationToken ct) =>
        {
            if (category?.Length > 80 || query?.Length > 200)
                return Results.BadRequest(new { error = "category is limited to 80 characters and query to 200 characters." });
            var userId = ApiSql.OptionalUserId(context);
            await using var connection = await database.OpenAsync(ct);
            var sql = VideoSelect + Environment.NewLine + """
                WHERE v.DeletedAt IS NULL AND v.VideoStatus = 'ready' AND v.Visibility = 'public'
                  AND (@Category IS NULL OR TRY_CONVERT(int, @Category) = v.CategoryId OR cat.CategoryName = @Category)
                  AND (@Pattern IS NULL OR v.Title LIKE @Pattern ESCAPE '~' OR v.Description LIKE @Pattern ESCAPE '~'
                       OR c.ChannelName LIKE @Pattern ESCAPE '~')
                ORDER BY COALESCE(v.PublishedAt, v.CreatedAt) DESC, v.VideoId DESC
                OFFSET 0 ROWS FETCH NEXT 100 ROWS ONLY;
                """;
            await using var command = new SqlCommand(sql, connection);
            command.Add("@UserId", SqlDbType.BigInt, userId);
            command.Add("@Category", SqlDbType.NVarChar, string.IsNullOrWhiteSpace(category) ? null : category.Trim(), 80);
            command.Add("@Pattern", SqlDbType.NVarChar, string.IsNullOrWhiteSpace(query) ? null : ApiFiles.ToSafeLikePattern(query.Trim()), 402);
            var items = await ReadVideosAsync(command, ct);
            if (!string.IsNullOrWhiteSpace(query))
            {
                if (userId.HasValue)
                {
                    await using var history = new SqlCommand("""
                    INSERT dbo.SearchHistory (UserId, SearchQuery)
                    VALUES (@UserId, LEFT(@Query, 200));
                    """, connection);
                    history.Add("@UserId", SqlDbType.BigInt, userId.Value);
                    history.Add("@Query", SqlDbType.NVarChar, query.Trim(), 200);
                    await history.ExecuteNonQueryAsync(ct);
                }
            }
            return Results.Ok(new { items });
        });

        api.MapGet("/videos/{videoId:long}", async (long videoId, HttpContext context, CancellationToken ct) =>
        {
            await using var connection = await database.OpenAsync(ct);
            var command = new SqlCommand(VideoSelect + Environment.NewLine + """
                WHERE v.VideoId = @VideoId AND v.DeletedAt IS NULL AND v.VideoStatus = 'ready'
                  AND (v.Visibility IN ('public', 'unlisted')
                       OR c.OwnerUserId = @UserId
                       OR EXISTS (SELECT 1 FROM dbo.ChannelMembers m WHERE m.ChannelId = c.ChannelId
                           AND m.UserId = @UserId AND m.MembershipStatus = 'active'
                           AND m.MemberRole IN ('manager', 'editor')))
                """, connection);
            command.Add("@VideoId", SqlDbType.BigInt, videoId);
            command.Add("@UserId", SqlDbType.BigInt, ApiSql.OptionalUserId(context));
            var items = await ReadVideosAsync(command, ct);
            return items.Count == 0 ? Results.NotFound() : Results.Ok(items[0]);
        });

        api.MapGet("/videos/{videoId:long}/stream", async (long videoId, HttpContext context, CancellationToken ct) =>
        {
            var userId = ApiSql.OptionalUserId(context);
            await using var connection = await database.OpenAsync(ct);
            if (!await ApiSql.IsVideoViewableAsync(connection, userId, videoId, ct))
                return Results.NotFound();
            await using var command = new SqlCommand("""
                SELECT MediaStorageKey, MediaType FROM dbo.Videos
                WHERE VideoId = @VideoId AND DeletedAt IS NULL AND VideoStatus = 'ready';
                """, connection);
            command.Add("@VideoId", SqlDbType.BigInt, videoId);
            await using var reader = await command.ExecuteReaderAsync(ct);
            if (!await reader.ReadAsync(ct) || reader.IsDBNull(0))
                return Results.NotFound();
            var key = reader.GetString(0);
            var mimeType = reader.IsDBNull(1) ? null : reader.GetString(1);
            await reader.DisposeAsync();
            if (!ApiFiles.IsStorageKey(key))
                return Results.NotFound();
            var path = Path.Combine(mediaRoot, key);
            if (!File.Exists(path))
                return Results.NotFound();
            return Results.File(path, ApiFiles.IsVideoMimeType(mimeType) ? mimeType : ApiFiles.GetMimeType(Path.GetExtension(key)),
                enableRangeProcessing: true);
        });

        api.MapGet("/videos/{videoId:long}/thumbnail", async (long videoId, HttpContext context, CancellationToken ct) =>
        {
            var userId = ApiSql.OptionalUserId(context);
            await using var connection = await database.OpenAsync(ct);
            if (!await ApiSql.IsVideoViewableAsync(connection, userId, videoId, ct))
                return Results.NotFound();
            await using var command = new SqlCommand("""
                SELECT TOP (1) candidate.StorageKey, candidate.MimeType
                FROM dbo.Videos v
                OUTER APPLY (
                    SELECT TOP (1) a.StorageKey, a.MimeType
                    FROM dbo.VideoAssets a
                    WHERE a.VideoId = v.VideoId AND a.AssetType = 'thumbnail'
                    ORDER BY a.VideoAssetId DESC
                ) asset
                CROSS APPLY (SELECT COALESCE(asset.StorageKey, v.ThumbnailStorageKey) AS StorageKey,
                                    asset.MimeType AS MimeType) candidate
                WHERE v.VideoId = @VideoId AND v.DeletedAt IS NULL AND v.VideoStatus = 'ready'
                  AND candidate.StorageKey IS NOT NULL;
                """, connection);
            command.Add("@VideoId", SqlDbType.BigInt, videoId);
            await using var reader = await command.ExecuteReaderAsync(ct);
            if (!await reader.ReadAsync(ct))
                return Results.NotFound();
            var key = reader.GetString(0);
            var mimeType = reader.IsDBNull(1) ? null : reader.GetString(1);
            await reader.DisposeAsync();
            if (!ApiFiles.IsStorageKey(key))
                return Results.NotFound();
            var path = Path.Combine(mediaRoot, key);
            if (!File.Exists(path))
                return Results.NotFound();
            return Results.File(path, ApiFiles.IsImageMimeType(mimeType) ? mimeType : ApiFiles.GetMimeType(Path.GetExtension(key)),
                enableRangeProcessing: true);
        });

        protectedApi.MapPost("/videos/{videoId:long}/views", async (long videoId, ViewsRequest request,
            HttpContext context, CancellationToken ct) =>
        {
            if (request.WatchedSeconds < 0 || request.WatchedSeconds > 86_400)
                return Results.BadRequest(new { error = "watchedSeconds must be between 0 and 86400." });
            var userId = ApiSql.UserId(context);
            await using var connection = await database.OpenAsync(ct);
            if (!await ApiSql.IsVideoViewableAsync(connection, userId, videoId, ct))
                return Results.NotFound();
            var viewSessionId = Guid.TryParse(request.ViewSessionId, out var parsed) ? parsed : Guid.NewGuid();
            await using var transaction = (SqlTransaction)await connection.BeginTransactionAsync(ct);
            await using (var view = new SqlCommand("""
                IF NOT EXISTS (SELECT 1 FROM dbo.VideoViews WITH (UPDLOCK, HOLDLOCK)
                    WHERE VideoId = @VideoId AND ViewSessionId = @ViewSessionId)
                BEGIN
                    INSERT dbo.VideoViews (VideoId, UserId, ViewSessionId, WatchedSeconds, Completed)
                    VALUES (@VideoId, @UserId, @ViewSessionId, @WatchedSeconds, @Completed);
                    UPDATE dbo.Videos SET ViewCount = ViewCount + 1
                    WHERE VideoId = @VideoId AND DeletedAt IS NULL;
                END;
                """, connection, transaction))
            {
                view.Add("@VideoId", SqlDbType.BigInt, videoId);
                view.Add("@UserId", SqlDbType.BigInt, userId);
                view.Add("@ViewSessionId", SqlDbType.UniqueIdentifier, viewSessionId);
                view.Add("@WatchedSeconds", SqlDbType.Int, request.WatchedSeconds);
                view.Add("@Completed", SqlDbType.Bit, request.Completed);
                await view.ExecuteNonQueryAsync(ct);
            }
            await using (var history = new SqlCommand("""
                INSERT dbo.WatchHistory (UserId, VideoId, WatchDurationSeconds, LastPositionSeconds)
                VALUES (@UserId, @VideoId, @Seconds, @Seconds);
                """, connection, transaction))
            {
                history.Add("@UserId", SqlDbType.BigInt, userId);
                history.Add("@VideoId", SqlDbType.BigInt, videoId);
                history.Add("@Seconds", SqlDbType.Int, request.WatchedSeconds);
                await history.ExecuteNonQueryAsync(ct);
            }
            await transaction.CommitAsync(ct);
            return Results.Ok(new { videoId, viewSessionId });
        });
    }

    public static async Task<List<VideoDto>> ReadVideosAsync(SqlCommand command, CancellationToken ct)
    {
        var result = new List<VideoDto>();
        await using var reader = await command.ExecuteReaderAsync(ct);
        while (await reader.ReadAsync(ct))
        {
            var seconds = reader.GetInt32(5);
            result.Add(new VideoDto(
                reader.GetInt64(0), reader.GetString(1), reader.GetString(2), reader.GetInt64(3),
                reader.GetString(4), FormatDuration(seconds), seconds, reader.GetString(6),
                reader.IsDBNull(7) ? "" : $"/api/videos/{reader.GetInt64(0)}/thumbnail", reader.GetString(8),
                reader.GetBoolean(9), reader.GetBoolean(10), reader.GetBoolean(11)));
        }
        return result;
    }

    internal static string VideoSelectForLibrary(string condition, string orderBy) => VideoSelect + Environment.NewLine + $"""
        WHERE v.DeletedAt IS NULL AND v.VideoStatus = 'ready'
          AND (v.Visibility IN ('public', 'unlisted')
               OR c.OwnerUserId = @UserId
               OR EXISTS (SELECT 1 FROM dbo.ChannelMembers m WHERE m.ChannelId = c.ChannelId
                   AND m.UserId = @UserId AND m.MembershipStatus = 'active'
                   AND m.MemberRole IN ('manager', 'editor')))
          AND {condition}
        ORDER BY {orderBy}
        OFFSET 0 ROWS FETCH NEXT 100 ROWS ONLY;
        """;

    internal static string FormatDuration(int seconds)
    {
        var time = TimeSpan.FromSeconds(Math.Max(0, seconds));
        return time.TotalHours >= 1 ? time.ToString(@"h\:mm\:ss") : time.ToString(@"m\:ss");
    }
}

public sealed record VideoDto(long VideoId, string Title, string Channel, long ChannelId, string Details,
    string Duration, int DurationSeconds, string Category, string ThumbnailUrl, string Visibility,
    bool IsLiked, bool IsSaved, bool IsSubscribed);
public sealed record ViewsRequest(int WatchedSeconds = 0, bool Completed = false, string? ViewSessionId = null);
