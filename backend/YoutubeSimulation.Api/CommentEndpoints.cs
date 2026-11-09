using System.Data;
using Microsoft.Data.SqlClient;

public static class CommentEndpoints
{
    private static readonly HashSet<string> ReportReasons = new(StringComparer.Ordinal)
        { "spam", "harassment", "hate", "violence", "sexual", "misinformation", "copyright", "other" };

    public static void Map(RouteGroupBuilder api, ApiDatabase database)
    {
        api.MapGet("/videos/{videoId:long}/comments", async (long videoId, long? parentCommentId,
            HttpContext context, CancellationToken ct) =>
        {
            var userId = ApiSql.UserId(context);
            await using var connection = await database.OpenAsync(ct);
            if (!await ApiSql.IsVideoViewableAsync(connection, userId, videoId, ct))
                return Results.NotFound();
            await using var command = new SqlCommand("""
                SELECT TOP (100) c.CommentId, c.VideoId, c.UserId, u.DisplayName, c.ParentCommentId,
                       c.CommentText, c.CreatedAt,
                       (SELECT COUNT_BIG(*) FROM dbo.CommentReactions r WHERE r.CommentId = c.CommentId AND r.ReactionType = 'like'),
                       (SELECT COUNT_BIG(*) FROM dbo.CommentReactions r WHERE r.CommentId = c.CommentId AND r.ReactionType = 'dislike'),
                       CONVERT(bit, CASE WHEN mine.ReactionType = 'like' THEN 1 ELSE 0 END)
                FROM dbo.VideoComments c
                INNER JOIN dbo.Users u ON u.UserId = c.UserId
                LEFT JOIN dbo.CommentReactions mine ON mine.CommentId = c.CommentId AND mine.UserId = @UserId
                WHERE c.VideoId = @VideoId AND c.CommentStatus = 'active'
                  AND (@ParentId IS NULL OR c.ParentCommentId = @ParentId)
                ORDER BY c.CreatedAt, c.CommentId;
                """, connection);
            command.Add("@UserId", SqlDbType.BigInt, userId);
            command.Add("@VideoId", SqlDbType.BigInt, videoId);
            command.Add("@ParentId", SqlDbType.BigInt, parentCommentId);
            await using var reader = await command.ExecuteReaderAsync(ct);
            var items = new List<object>();
            while (await reader.ReadAsync(ct))
                items.Add(new
                {
                    commentId = reader.GetInt64(0), videoId = reader.GetInt64(1), userId = reader.GetInt64(2),
                    displayName = reader.GetString(3), parentCommentId = reader.IsDBNull(4) ? (long?)null : reader.GetInt64(4),
                    text = reader.GetString(5), createdAt = reader.GetDateTime(6), likeCount = reader.GetInt64(7),
                    dislikeCount = reader.GetInt64(8), isLiked = reader.GetBoolean(9)
                });
            return Results.Ok(new { items });
        });

        api.MapPost("/videos/{videoId:long}/comments", async (long videoId, CommentCreateRequest request,
            HttpContext context, CancellationToken ct) =>
        {
            var text = request.Text?.Trim();
            if (string.IsNullOrWhiteSpace(text) || text.Length > 2000)
                return Results.BadRequest(new { error = "text is required and must be at most 2000 characters." });
            var userId = ApiSql.UserId(context);
            await using var connection = await database.OpenAsync(ct);
            if (!await ApiSql.IsVideoViewableAsync(connection, userId, videoId, ct))
                return Results.NotFound();
            long channelOwner;
            bool commentsEnabled;
            await using (var video = new SqlCommand("""
                SELECT c.OwnerUserId, v.CommentsEnabled FROM dbo.Videos v
                INNER JOIN dbo.Channels c ON c.ChannelId = v.ChannelId
                WHERE v.VideoId = @VideoId AND v.DeletedAt IS NULL;
                """, connection))
            {
                video.Add("@VideoId", SqlDbType.BigInt, videoId);
                await using var reader = await video.ExecuteReaderAsync(ct);
                if (!await reader.ReadAsync(ct))
                    return Results.NotFound();
                channelOwner = reader.GetInt64(0);
                commentsEnabled = reader.GetBoolean(1);
            }
            if (!commentsEnabled)
                return Results.BadRequest(new { error = "Comments are disabled for this video." });

            long? parentUserId = null;
            if (request.ParentCommentId.HasValue)
            {
                await using var parent = new SqlCommand("""
                    SELECT UserId FROM dbo.VideoComments
                    WHERE CommentId = @ParentId AND VideoId = @VideoId AND CommentStatus = 'active';
                    """, connection);
                parent.Add("@ParentId", SqlDbType.BigInt, request.ParentCommentId.Value);
                parent.Add("@VideoId", SqlDbType.BigInt, videoId);
                var result = await parent.ExecuteScalarAsync(ct);
                if (result is null or DBNull)
                    return Results.BadRequest(new { error = "parentCommentId is not an active comment on this video." });
                parentUserId = Convert.ToInt64(result);
            }

            await using var transaction = (SqlTransaction)await connection.BeginTransactionAsync(ct);
            long commentId;
            await using (var insert = new SqlCommand("""
                INSERT dbo.VideoComments (VideoId, UserId, ParentCommentId, CommentText)
                OUTPUT inserted.CommentId VALUES (@VideoId, @UserId, @ParentId, @Text);
                """, connection, transaction))
            {
                insert.Add("@VideoId", SqlDbType.BigInt, videoId);
                insert.Add("@UserId", SqlDbType.BigInt, userId);
                insert.Add("@ParentId", SqlDbType.BigInt, request.ParentCommentId);
                insert.Add("@Text", SqlDbType.NVarChar, text, 2000);
                commentId = Convert.ToInt64(await insert.ExecuteScalarAsync(ct));
            }
            if (parentUserId.HasValue && parentUserId.Value != userId)
            {
                await using var notify = new SqlCommand("""
                    INSERT dbo.Notifications (RecipientUserId, ActorUserId, NotificationType, CommentId, Message)
                    VALUES (@RecipientId, @UserId, 'comment_reply', @CommentId, N'You received a reply to your comment.');
                    """, connection, transaction);
                notify.Add("@RecipientId", SqlDbType.BigInt, parentUserId.Value);
                notify.Add("@UserId", SqlDbType.BigInt, userId);
                notify.Add("@CommentId", SqlDbType.BigInt, commentId);
                await notify.ExecuteNonQueryAsync(ct);
            }
            else if (!request.ParentCommentId.HasValue && channelOwner != userId)
            {
                await using var notify = new SqlCommand("""
                    INSERT dbo.Notifications (RecipientUserId, ActorUserId, NotificationType, VideoId, Message)
                    VALUES (@OwnerId, @UserId, 'new_comment', @VideoId, N'Your video received a new comment.');
                    """, connection, transaction);
                notify.Add("@OwnerId", SqlDbType.BigInt, channelOwner);
                notify.Add("@UserId", SqlDbType.BigInt, userId);
                notify.Add("@VideoId", SqlDbType.BigInt, videoId);
                await notify.ExecuteNonQueryAsync(ct);
            }
            await transaction.CommitAsync(ct);
            return Results.Created($"/api/videos/{videoId}/comments", new { commentId, videoId, userId, parentCommentId = request.ParentCommentId, text });
        });

        api.MapPut("/comments/{commentId:long}", async (long commentId, CommentUpdateRequest request,
            HttpContext context, CancellationToken ct) =>
        {
            var text = request.Text?.Trim();
            if (string.IsNullOrWhiteSpace(text) || text.Length > 2000)
                return Results.BadRequest(new { error = "text is required and must be at most 2000 characters." });
            await using var connection = await database.OpenAsync(ct);
            await using var command = new SqlCommand("""
                UPDATE dbo.VideoComments SET CommentText = @Text, UpdatedAt = SYSUTCDATETIME()
                WHERE CommentId = @CommentId AND UserId = @UserId AND CommentStatus = 'active';
                """, connection);
            command.Add("@Text", SqlDbType.NVarChar, text, 2000);
            command.Add("@CommentId", SqlDbType.BigInt, commentId);
            command.Add("@UserId", SqlDbType.BigInt, ApiSql.UserId(context));
            var rows = await command.ExecuteNonQueryAsync(ct);
            return rows == 0 ? Results.NotFound() : Results.Ok(new { commentId, text });
        });

        api.MapDelete("/comments/{commentId:long}", async (long commentId, HttpContext context, CancellationToken ct) =>
        {
            var userId = ApiSql.UserId(context);
            await using var connection = await database.OpenAsync(ct);
            await using var command = new SqlCommand("""
                UPDATE comment SET CommentStatus = 'deleted', UpdatedAt = SYSUTCDATETIME()
                FROM dbo.VideoComments comment
                INNER JOIN dbo.Videos v ON v.VideoId = comment.VideoId
                INNER JOIN dbo.Channels c ON c.ChannelId = v.ChannelId
                WHERE comment.CommentId = @CommentId AND comment.CommentStatus = 'active'
                  AND (comment.UserId = @UserId OR c.OwnerUserId = @UserId OR EXISTS
                       (SELECT 1 FROM dbo.ChannelMembers m WHERE m.ChannelId = c.ChannelId AND m.UserId = @UserId
                        AND m.MembershipStatus = 'active' AND m.MemberRole = 'manager'));
                """, connection);
            command.Add("@CommentId", SqlDbType.BigInt, commentId);
            command.Add("@UserId", SqlDbType.BigInt, userId);
            var rows = await command.ExecuteNonQueryAsync(ct);
            return rows == 0 ? Results.NotFound() : Results.NoContent();
        });

        api.MapPost("/comments/{commentId:long}/reaction", async (long commentId, HttpContext context, CancellationToken ct) =>
            await ToggleCommentReactionAsync(database, commentId, context, ct));
        api.MapPut("/comments/{commentId:long}/reaction", async (long commentId,
            CommentReactionRequest request, HttpContext context, CancellationToken ct) =>
        {
            var reaction = request.ReactionType?.Trim().ToLowerInvariant();
            if (reaction is not ("like" or "dislike"))
                return Results.BadRequest(new { error = "reactionType must be like or dislike." });
            return await SetCommentReactionAsync(database, commentId, context, reaction, ct);
        });
        api.MapDelete("/comments/{commentId:long}/reaction", async (long commentId, HttpContext context, CancellationToken ct) =>
        {
            var userId = ApiSql.UserId(context);
            await using var connection = await database.OpenAsync(ct);
            if (await GetCommentVideoIdAsync(connection, commentId, userId, ct) is null)
                return Results.NotFound();
            await using var command = new SqlCommand(
                "DELETE dbo.CommentReactions WHERE UserId = @UserId AND CommentId = @CommentId;", connection);
            command.Add("@UserId", SqlDbType.BigInt, userId);
            command.Add("@CommentId", SqlDbType.BigInt, commentId);
            await command.ExecuteNonQueryAsync(ct);
            return Results.Ok(new { commentId, reactionType = (string?)null });
        });

        api.MapPost("/reports", async (ContentReportRequest request, HttpContext context, CancellationToken ct) =>
        {
            var targets = (request.VideoId.HasValue ? 1 : 0) + (request.CommentId.HasValue ? 1 : 0)
                + (request.ChannelId.HasValue ? 1 : 0);
            var reason = request.Reason?.Trim().ToLowerInvariant();
            if (targets != 1 || reason is null || !ReportReasons.Contains(reason)
                || request.Details?.Length > 2000)
                return Results.BadRequest(new { error = "Provide exactly one target, a supported reason, and at most 2000 detail characters." });
            var userId = ApiSql.UserId(context);
            await using var connection = await database.OpenAsync(ct);
            if (request.VideoId.HasValue &&
                !await ApiSql.IsVideoViewableAsync(connection, userId, request.VideoId.Value, ct))
                return Results.NotFound();
            if (request.CommentId.HasValue &&
                await GetCommentVideoIdAsync(connection, request.CommentId.Value, userId, ct) is null)
                return Results.NotFound();
            if (request.ChannelId.HasValue)
            {
                await using var channel = new SqlCommand(
                    "SELECT 1 FROM dbo.Channels WHERE ChannelId = @Id AND IsActive = 1;", connection);
                channel.Add("@Id", SqlDbType.BigInt, request.ChannelId.Value);
                if (await channel.ExecuteScalarAsync(ct) is null)
                    return Results.NotFound();
            }
            await using var command = new SqlCommand("""
                INSERT dbo.ContentReports (ReporterUserId, VideoId, CommentId, ChannelId, Reason, Details)
                OUTPUT inserted.ContentReportId
                VALUES (@UserId, @VideoId, @CommentId, @ChannelId, @Reason, @Details);
                """, connection);
            command.Add("@UserId", SqlDbType.BigInt, userId);
            command.Add("@VideoId", SqlDbType.BigInt, request.VideoId);
            command.Add("@CommentId", SqlDbType.BigInt, request.CommentId);
            command.Add("@ChannelId", SqlDbType.BigInt, request.ChannelId);
            command.Add("@Reason", SqlDbType.VarChar, reason, 24);
            command.Add("@Details", SqlDbType.NVarChar, request.Details?.Trim(), 2000);
            var reportId = Convert.ToInt64(await command.ExecuteScalarAsync(ct));
            return Results.Created($"/api/reports/{reportId}", new { reportId, reportStatus = "open" });
        });
    }

    private static async Task<IResult> ToggleCommentReactionAsync(ApiDatabase database, long commentId,
        HttpContext context, CancellationToken ct)
    {
        var userId = ApiSql.UserId(context);
        await using var connection = await database.OpenAsync(ct);
        if (await GetCommentVideoIdAsync(connection, commentId, userId, ct) is null)
            return Results.NotFound();
        await using var transaction = (SqlTransaction)await connection.BeginTransactionAsync(ct);
        string? existing;
        await using (var find = new SqlCommand("""
            SELECT ReactionType FROM dbo.CommentReactions WITH (UPDLOCK, HOLDLOCK)
            WHERE UserId = @UserId AND CommentId = @CommentId;
            """, connection, transaction))
        {
            find.Add("@UserId", SqlDbType.BigInt, userId);
            find.Add("@CommentId", SqlDbType.BigInt, commentId);
            existing = await find.ExecuteScalarAsync(ct) as string;
        }
        var target = existing == "like" ? null : "like";
        await using (var command = new SqlCommand(target is null
            ? "DELETE dbo.CommentReactions WHERE UserId = @UserId AND CommentId = @CommentId;"
            : """
              UPDATE dbo.CommentReactions SET ReactionType = @Reaction, ReactedAt = SYSUTCDATETIME()
              WHERE UserId = @UserId AND CommentId = @CommentId;
              IF @@ROWCOUNT = 0 INSERT dbo.CommentReactions (UserId, CommentId, ReactionType)
                  VALUES (@UserId, @CommentId, @Reaction);
              """, connection, transaction))
        {
            command.Add("@UserId", SqlDbType.BigInt, userId);
            command.Add("@CommentId", SqlDbType.BigInt, commentId);
            if (target is not null)
                command.Add("@Reaction", SqlDbType.VarChar, target, 8);
            await command.ExecuteNonQueryAsync(ct);
        }
        await transaction.CommitAsync(ct);
        return Results.Ok(new { commentId, reactionType = target });
    }

    private static async Task<IResult> SetCommentReactionAsync(ApiDatabase database, long commentId,
        HttpContext context, string reactionType, CancellationToken ct)
    {
        var userId = ApiSql.UserId(context);
        await using var connection = await database.OpenAsync(ct);
        if (await GetCommentVideoIdAsync(connection, commentId, userId, ct) is null)
            return Results.NotFound();
        await using var command = new SqlCommand("""
            UPDATE dbo.CommentReactions SET ReactionType = @Reaction, ReactedAt = SYSUTCDATETIME()
            WHERE UserId = @UserId AND CommentId = @CommentId;
            IF @@ROWCOUNT = 0 INSERT dbo.CommentReactions (UserId, CommentId, ReactionType)
                VALUES (@UserId, @CommentId, @Reaction);
            """, connection);
        command.Add("@UserId", SqlDbType.BigInt, userId);
        command.Add("@CommentId", SqlDbType.BigInt, commentId);
        command.Add("@Reaction", SqlDbType.VarChar, reactionType, 8);
        await command.ExecuteNonQueryAsync(ct);
        return Results.Ok(new { commentId, reactionType });
    }

    private static async Task<long?> GetCommentVideoIdAsync(SqlConnection connection, long commentId,
        long userId, CancellationToken ct)
    {
        await using var command = new SqlCommand("""
            SELECT c.VideoId FROM dbo.VideoComments c
            WHERE c.CommentId = @CommentId AND c.CommentStatus = 'active'
              AND EXISTS (SELECT 1 FROM dbo.Videos v INNER JOIN dbo.Channels ch ON ch.ChannelId = v.ChannelId
                  WHERE v.VideoId = c.VideoId AND v.DeletedAt IS NULL AND v.VideoStatus = 'ready'
                    AND (v.Visibility IN ('public', 'unlisted') OR ch.OwnerUserId = @UserId OR EXISTS
                         (SELECT 1 FROM dbo.ChannelMembers m WHERE m.ChannelId = ch.ChannelId AND m.UserId = @UserId
                          AND m.MembershipStatus = 'active' AND m.MemberRole IN ('manager', 'editor'))));
            """, connection);
        command.Add("@CommentId", SqlDbType.BigInt, commentId);
        command.Add("@UserId", SqlDbType.BigInt, userId);
        return await ApiSql.ScalarIdAsync(command, ct);
    }
}

public sealed record CommentCreateRequest(string? Text, long? ParentCommentId);
public sealed record CommentUpdateRequest(string? Text);
public sealed record CommentReactionRequest(string? ReactionType);
public sealed record ContentReportRequest(long? VideoId, long? CommentId, long? ChannelId, string? Reason, string? Details);
