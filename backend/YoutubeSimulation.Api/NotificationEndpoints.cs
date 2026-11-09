using System.Data;
using Microsoft.Data.SqlClient;

public static class NotificationEndpoints
{
    public static void Map(RouteGroupBuilder api, ApiDatabase database)
    {
        api.MapGet("/notifications", async (HttpContext context, CancellationToken ct) =>
        {
            var userId = ApiSql.UserId(context);
            await using var connection = await database.OpenAsync(ct);
            await using var command = new SqlCommand("""
                SELECT TOP (100) n.NotificationId, n.NotificationType, n.Message, n.IsRead, n.CreatedAt,
                       n.VideoId, n.ChannelId, actor.DisplayName
                FROM dbo.Notifications n
                LEFT JOIN dbo.Users actor ON actor.UserId = n.ActorUserId
                WHERE n.RecipientUserId = @UserId
                ORDER BY n.CreatedAt DESC, n.NotificationId DESC;
                """, connection);
            command.Add("@UserId", SqlDbType.BigInt, userId);
            await using var reader = await command.ExecuteReaderAsync(ct);
            var items = new List<object>();
            while (await reader.ReadAsync(ct))
                items.Add(new
                {
                    notificationId = reader.GetInt64(0), type = reader.GetString(1), message = reader.GetString(2),
                    isRead = reader.GetBoolean(3), createdAt = reader.GetDateTime(4),
                    videoId = reader.IsDBNull(5) ? (long?)null : reader.GetInt64(5),
                    channelId = reader.IsDBNull(6) ? (long?)null : reader.GetInt64(6),
                    actorDisplayName = reader.IsDBNull(7) ? null : reader.GetString(7)
                });
            await reader.DisposeAsync();
            await using var unread = new SqlCommand("""
                SELECT COUNT_BIG(*) FROM dbo.Notifications WHERE RecipientUserId = @UserId AND IsRead = 0;
                """, connection);
            unread.Add("@UserId", SqlDbType.BigInt, userId);
            return Results.Ok(new { items, unreadCount = Convert.ToInt64(await unread.ExecuteScalarAsync(ct)) });
        });

        async Task<IResult> MarkReadAsync(long notificationId, HttpContext context, CancellationToken ct)
        {
            await using var connection = await database.OpenAsync(ct);
            await using var command = new SqlCommand("""
                UPDATE dbo.Notifications SET IsRead = 1, ReadAt = SYSUTCDATETIME()
                WHERE NotificationId = @NotificationId AND RecipientUserId = @UserId AND IsRead = 0;
                """, connection);
            command.Add("@NotificationId", SqlDbType.BigInt, notificationId);
            command.Add("@UserId", SqlDbType.BigInt, ApiSql.UserId(context));
            await command.ExecuteNonQueryAsync(ct);
            return Results.NoContent();
        }
        api.MapPost("/notifications/{notificationId:long}/read", MarkReadAsync);
        api.MapPatch("/notifications/{notificationId:long}/read", MarkReadAsync);

        api.MapPatch("/notifications/read", async (HttpContext context, CancellationToken ct) =>
        {
            await using var connection = await database.OpenAsync(ct);
            await using var command = new SqlCommand("""
                UPDATE dbo.Notifications SET IsRead = 1, ReadAt = SYSUTCDATETIME()
                WHERE RecipientUserId = @UserId AND IsRead = 0;
                """, connection);
            command.Add("@UserId", SqlDbType.BigInt, ApiSql.UserId(context));
            var count = await command.ExecuteNonQueryAsync(ct);
            return Results.Ok(new { updatedCount = count });
        });
    }
}
