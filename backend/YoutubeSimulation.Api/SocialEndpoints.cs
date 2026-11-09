using System.Data;
using Microsoft.Data.SqlClient;

public static class SocialEndpoints
{
    public static void Map(RouteGroupBuilder api, ApiDatabase database)
    {
        api.MapPost("/videos/{videoId:long}/like", async (long videoId, HttpContext context, CancellationToken ct) =>
        {
            var userId = ApiSql.UserId(context);
            await using var connection = await database.OpenAsync(ct);
            if (!await ApiSql.IsVideoViewableAsync(connection, userId, videoId, ct))
                return Results.NotFound();
            await using var transaction = (SqlTransaction)await connection.BeginTransactionAsync(ct);
            var isLiked = await ToggleLikeAsync(connection, transaction, userId, videoId, ct);
            await transaction.CommitAsync(ct);
            return Results.Ok(new { videoId, isLiked });
        });
        api.MapPut("/videos/{videoId:long}/like", (long videoId, HttpContext context, CancellationToken ct) =>
            SetLikeAsync(database, videoId, context, true, ct));
        api.MapDelete("/videos/{videoId:long}/like", (long videoId, HttpContext context, CancellationToken ct) =>
            SetLikeAsync(database, videoId, context, false, ct));

        api.MapPost("/videos/{videoId:long}/watch-later", (long videoId, HttpContext context, CancellationToken ct) =>
            ToggleWatchLaterAsync(database, videoId, context, ct));
        api.MapPut("/videos/{videoId:long}/watch-later", (long videoId, HttpContext context, CancellationToken ct) =>
            SetWatchLaterAsync(database, videoId, context, true, ct));
        api.MapDelete("/videos/{videoId:long}/watch-later", (long videoId, HttpContext context, CancellationToken ct) =>
            SetWatchLaterAsync(database, videoId, context, false, ct));

        api.MapPut("/channels/{channelId:long}/subscription", (long channelId, HttpContext context, CancellationToken ct) =>
            SetSubscriptionAsync(database, channelId, context, true, ct));
        api.MapDelete("/channels/{channelId:long}/subscription", (long channelId, HttpContext context, CancellationToken ct) =>
            SetSubscriptionAsync(database, channelId, context, false, ct));
        api.MapPost("/channels/{channelId:long}/subscription", (long channelId, HttpContext context, CancellationToken ct) =>
            ToggleSubscriptionAsync(database, channelId, context, ct));
        api.MapPut("/subscriptions/{channelId:long}", (long channelId, HttpContext context, CancellationToken ct) =>
            SetSubscriptionAsync(database, channelId, context, true, ct));
        api.MapDelete("/subscriptions/{channelId:long}", (long channelId, HttpContext context, CancellationToken ct) =>
            SetSubscriptionAsync(database, channelId, context, false, ct));

        api.MapGet("/subscriptions", async (HttpContext context, CancellationToken ct) =>
        {
            await using var connection = await database.OpenAsync(ct);
            await using var command = new SqlCommand("""
                SELECT c.ChannelId, c.ChannelName, c.Handle, c.AvatarStorageKey
                FROM dbo.ChannelSubscriptions s INNER JOIN dbo.Channels c ON c.ChannelId = s.ChannelId
                WHERE s.SubscriberUserId = @UserId AND c.IsActive = 1
                ORDER BY s.SubscribedAt DESC;
                """, connection);
            command.Add("@UserId", SqlDbType.BigInt, ApiSql.UserId(context));
            await using var reader = await command.ExecuteReaderAsync(ct);
            var items = new List<object>();
            while (await reader.ReadAsync(ct))
                items.Add(new
                {
                    channelId = reader.GetInt64(0), channel = reader.GetString(1), handle = reader.GetString(2),
                    thumbnailUrl = reader.IsDBNull(3) ? "" : $"/api/channels/{reader.GetInt64(0)}/avatar"
                });
            return Results.Ok(new { items });
        });

        api.MapGet("/library/{kind}", async (string kind, HttpContext context, CancellationToken ct) =>
        {
            var condition = kind.ToLowerInvariant() switch
            {
                "liked" => "reaction.ReactionType = 'like'",
                "watch-later" => "saved.VideoId IS NOT NULL",
                "history" => "EXISTS (SELECT 1 FROM dbo.WatchHistory h WHERE h.VideoId = v.VideoId AND h.UserId = @UserId)",
                "subscriptions" => "v.Visibility = 'public' AND EXISTS (SELECT 1 FROM dbo.ChannelSubscriptions s WHERE s.ChannelId = v.ChannelId AND s.SubscriberUserId = @UserId)",
                _ => null
            };
            if (condition is null)
                return Results.NotFound();
            var ordering = kind.Equals("history", StringComparison.OrdinalIgnoreCase)
                ? "(SELECT MAX(h.WatchedAt) FROM dbo.WatchHistory h WHERE h.VideoId = v.VideoId AND h.UserId = @UserId) DESC"
                : "COALESCE(v.PublishedAt, v.CreatedAt) DESC";
            await using var connection = await database.OpenAsync(ct);
            var command = new SqlCommand(VideoEndpoints.VideoSelectForLibrary(condition, ordering), connection);
            command.Add("@UserId", SqlDbType.BigInt, ApiSql.UserId(context));
            return Results.Ok(new { items = await VideoEndpoints.ReadVideosAsync(command, ct) });
        });
    }

    private static async Task<IResult> SetLikeAsync(ApiDatabase database, long videoId, HttpContext context,
        bool isLiked, CancellationToken ct)
    {
        var userId = ApiSql.UserId(context);
        await using var connection = await database.OpenAsync(ct);
        if (!await ApiSql.IsVideoViewableAsync(connection, userId, videoId, ct))
            return Results.NotFound();
        await using var command = new SqlCommand(isLiked
            ? """
              UPDATE dbo.VideoReactions SET ReactionType = 'like', ReactedAt = SYSUTCDATETIME()
              WHERE UserId = @UserId AND VideoId = @VideoId;
              IF @@ROWCOUNT = 0 INSERT dbo.VideoReactions (UserId, VideoId, ReactionType) VALUES (@UserId, @VideoId, 'like');
              """
            : "DELETE dbo.VideoReactions WHERE UserId = @UserId AND VideoId = @VideoId;", connection);
        command.Add("@UserId", SqlDbType.BigInt, userId);
        command.Add("@VideoId", SqlDbType.BigInt, videoId);
        await command.ExecuteNonQueryAsync(ct);
        return Results.Ok(new { videoId, isLiked });
    }

    private static async Task<bool> ToggleLikeAsync(SqlConnection connection, SqlTransaction transaction,
        long userId, long videoId, CancellationToken ct)
    {
        bool wasLiked;
        await using (var find = new SqlCommand("""
            SELECT ReactionType FROM dbo.VideoReactions WITH (UPDLOCK, HOLDLOCK)
            WHERE UserId = @UserId AND VideoId = @VideoId;
            """, connection, transaction))
        {
            find.Add("@UserId", SqlDbType.BigInt, userId);
            find.Add("@VideoId", SqlDbType.BigInt, videoId);
            wasLiked = string.Equals(await find.ExecuteScalarAsync(ct) as string, "like", StringComparison.Ordinal);
        }
        await using var update = new SqlCommand(wasLiked
            ? "DELETE dbo.VideoReactions WHERE UserId = @UserId AND VideoId = @VideoId;"
            : """
              UPDATE dbo.VideoReactions SET ReactionType = 'like', ReactedAt = SYSUTCDATETIME()
              WHERE UserId = @UserId AND VideoId = @VideoId;
              IF @@ROWCOUNT = 0 INSERT dbo.VideoReactions (UserId, VideoId, ReactionType) VALUES (@UserId, @VideoId, 'like');
              """, connection, transaction);
        update.Add("@UserId", SqlDbType.BigInt, userId);
        update.Add("@VideoId", SqlDbType.BigInt, videoId);
        await update.ExecuteNonQueryAsync(ct);
        return !wasLiked;
    }

    private static async Task<IResult> ToggleWatchLaterAsync(ApiDatabase database, long videoId,
        HttpContext context, CancellationToken ct)
    {
        var userId = ApiSql.UserId(context);
        await using var connection = await database.OpenAsync(ct);
        if (!await ApiSql.IsVideoViewableAsync(connection, userId, videoId, ct))
            return Results.NotFound();
        await using var transaction = (SqlTransaction)await connection.BeginTransactionAsync(ct);
        bool exists;
        await using (var find = new SqlCommand("""
            SELECT 1 FROM dbo.WatchLater WITH (UPDLOCK, HOLDLOCK) WHERE UserId = @UserId AND VideoId = @VideoId;
            """, connection, transaction))
        {
            find.Add("@UserId", SqlDbType.BigInt, userId);
            find.Add("@VideoId", SqlDbType.BigInt, videoId);
            exists = await find.ExecuteScalarAsync(ct) is not null;
        }
        await using var update = new SqlCommand(exists
            ? "DELETE dbo.WatchLater WHERE UserId = @UserId AND VideoId = @VideoId;"
            : "INSERT dbo.WatchLater (UserId, VideoId) VALUES (@UserId, @VideoId);", connection, transaction);
        update.Add("@UserId", SqlDbType.BigInt, userId);
        update.Add("@VideoId", SqlDbType.BigInt, videoId);
        await update.ExecuteNonQueryAsync(ct);
        await transaction.CommitAsync(ct);
        return Results.Ok(new { videoId, isSaved = !exists });
    }

    private static async Task<IResult> SetWatchLaterAsync(ApiDatabase database, long videoId,
        HttpContext context, bool isSaved, CancellationToken ct)
    {
        var userId = ApiSql.UserId(context);
        await using var connection = await database.OpenAsync(ct);
        if (!await ApiSql.IsVideoViewableAsync(connection, userId, videoId, ct))
            return Results.NotFound();
        await using var command = new SqlCommand(isSaved
            ? """
              IF NOT EXISTS (SELECT 1 FROM dbo.WatchLater WHERE UserId = @UserId AND VideoId = @VideoId)
                  INSERT dbo.WatchLater (UserId, VideoId) VALUES (@UserId, @VideoId);
              """
            : "DELETE dbo.WatchLater WHERE UserId = @UserId AND VideoId = @VideoId;", connection);
        command.Add("@UserId", SqlDbType.BigInt, userId);
        command.Add("@VideoId", SqlDbType.BigInt, videoId);
        await command.ExecuteNonQueryAsync(ct);
        return Results.Ok(new { videoId, isSaved });
    }

    private static async Task<IResult> ToggleSubscriptionAsync(ApiDatabase database, long channelId,
        HttpContext context, CancellationToken ct)
    {
        var userId = ApiSql.UserId(context);
        await using var connection = await database.OpenAsync(ct);
        await using var transaction = (SqlTransaction)await connection.BeginTransactionAsync(ct);
        bool exists;
        long? ownerId;
        await using (var find = new SqlCommand("""
            SELECT OwnerUserId FROM dbo.Channels WITH (UPDLOCK, HOLDLOCK)
            WHERE ChannelId = @ChannelId AND IsActive = 1;
            """, connection, transaction))
        {
            find.Add("@ChannelId", SqlDbType.BigInt, channelId);
            var result = await find.ExecuteScalarAsync(ct);
            ownerId = result is null or DBNull ? null : Convert.ToInt64(result);
        }
        if (ownerId is null)
            return Results.NotFound();
        if (ownerId.Value == userId)
            return Results.BadRequest(new { error = "You cannot subscribe to your own channel." });
        await using (var findSubscription = new SqlCommand("""
            SELECT 1 FROM dbo.ChannelSubscriptions WITH (UPDLOCK, HOLDLOCK)
            WHERE SubscriberUserId = @UserId AND ChannelId = @ChannelId;
            """, connection, transaction))
        {
            findSubscription.Add("@UserId", SqlDbType.BigInt, userId);
            findSubscription.Add("@ChannelId", SqlDbType.BigInt, channelId);
            exists = await findSubscription.ExecuteScalarAsync(ct) is not null;
        }
        await using (var update = new SqlCommand(exists
            ? "DELETE dbo.ChannelSubscriptions WHERE SubscriberUserId = @UserId AND ChannelId = @ChannelId;"
            : "INSERT dbo.ChannelSubscriptions (SubscriberUserId, ChannelId) VALUES (@UserId, @ChannelId);",
            connection, transaction))
        {
            update.Add("@UserId", SqlDbType.BigInt, userId);
            update.Add("@ChannelId", SqlDbType.BigInt, channelId);
            await update.ExecuteNonQueryAsync(ct);
        }
        if (!exists)
            await InsertSubscriberNotificationAsync(connection, transaction, ownerId.Value, userId, channelId, ct);
        await transaction.CommitAsync(ct);
        return Results.Ok(new { channelId, isSubscribed = !exists });
    }

    private static async Task<IResult> SetSubscriptionAsync(ApiDatabase database, long channelId,
        HttpContext context, bool isSubscribed, CancellationToken ct)
    {
        if (isSubscribed)
            return await ToggleToSubscribeAsync(database, channelId, context, ct);
        var userId = ApiSql.UserId(context);
        await using var connection = await database.OpenAsync(ct);
        await using var command = new SqlCommand("""
            DELETE dbo.ChannelSubscriptions
            WHERE SubscriberUserId = @UserId AND ChannelId = @ChannelId;
            """, connection);
        command.Add("@UserId", SqlDbType.BigInt, userId);
        command.Add("@ChannelId", SqlDbType.BigInt, channelId);
        await command.ExecuteNonQueryAsync(ct);
        return Results.Ok(new { channelId, isSubscribed = false });
    }

    private static async Task<IResult> ToggleToSubscribeAsync(ApiDatabase database, long channelId,
        HttpContext context, CancellationToken ct)
    {
        var userId = ApiSql.UserId(context);
        await using var connection = await database.OpenAsync(ct);
        await using var transaction = (SqlTransaction)await connection.BeginTransactionAsync(ct);
        long? ownerId;
        await using (var find = new SqlCommand("""
            SELECT OwnerUserId FROM dbo.Channels WHERE ChannelId = @ChannelId AND IsActive = 1;
            """, connection, transaction))
        {
            find.Add("@ChannelId", SqlDbType.BigInt, channelId);
            var value = await find.ExecuteScalarAsync(ct);
            ownerId = value is null or DBNull ? null : Convert.ToInt64(value);
        }
        if (ownerId is null)
            return Results.NotFound();
        if (ownerId == userId)
            return Results.BadRequest(new { error = "You cannot subscribe to your own channel." });
        await using var command = new SqlCommand("""
            IF NOT EXISTS (SELECT 1 FROM dbo.ChannelSubscriptions WHERE SubscriberUserId = @UserId AND ChannelId = @ChannelId)
            BEGIN
                INSERT dbo.ChannelSubscriptions (SubscriberUserId, ChannelId) VALUES (@UserId, @ChannelId);
                INSERT dbo.Notifications (RecipientUserId, ActorUserId, NotificationType, ChannelId, Message)
                VALUES (@OwnerId, @UserId, 'new_subscriber', @ChannelId, N'You have a new subscriber.');
            END;
            """, connection, transaction);
        command.Add("@UserId", SqlDbType.BigInt, userId);
        command.Add("@ChannelId", SqlDbType.BigInt, channelId);
        command.Add("@OwnerId", SqlDbType.BigInt, ownerId.Value);
        await command.ExecuteNonQueryAsync(ct);
        await transaction.CommitAsync(ct);
        return Results.Ok(new { channelId, isSubscribed = true });
    }

    private static async Task InsertSubscriberNotificationAsync(SqlConnection connection, SqlTransaction transaction,
        long ownerId, long subscriberId, long channelId, CancellationToken ct)
    {
        await using var command = new SqlCommand("""
            INSERT dbo.Notifications (RecipientUserId, ActorUserId, NotificationType, ChannelId, Message)
            VALUES (@OwnerId, @SubscriberId, 'new_subscriber', @ChannelId, N'You have a new subscriber.');
            """, connection, transaction);
        command.Add("@OwnerId", SqlDbType.BigInt, ownerId);
        command.Add("@SubscriberId", SqlDbType.BigInt, subscriberId);
        command.Add("@ChannelId", SqlDbType.BigInt, channelId);
        await command.ExecuteNonQueryAsync(ct);
    }
}
