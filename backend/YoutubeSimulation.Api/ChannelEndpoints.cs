using System.Data;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;

public static class ChannelEndpoints
{
    public static void Map(
        RouteGroupBuilder api,
        ApiDatabase database,
        string mediaRoot,
        long maxUploadBytes,
        ChunkedVideoUploadStore chunkedUploads)
    {
        api.MapGet("/channels/manage", async (HttpContext context, CancellationToken ct) =>
        {
            await using var connection = await database.OpenAsync(ct);
            await using var command = new SqlCommand("""
                SELECT c.ChannelId, c.ChannelName, c.Handle, c.Description, c.AvatarStorageKey,
                       CASE WHEN c.OwnerUserId = @UserId THEN 'owner' ELSE m.MemberRole END AS Role,
                       (SELECT COUNT_BIG(*) FROM dbo.ChannelSubscriptions s WHERE s.ChannelId = c.ChannelId)
                FROM dbo.Channels c
                LEFT JOIN dbo.ChannelMembers m ON m.ChannelId = c.ChannelId AND m.UserId = @UserId
                    AND m.MembershipStatus = 'active'
                WHERE c.IsActive = 1 AND (c.OwnerUserId = @UserId OR
                    (m.MemberRole = 'manager' AND m.MembershipStatus = 'active'))
                ORDER BY c.ChannelName;
                """, connection);
            command.Add("@UserId", SqlDbType.BigInt, ApiSql.UserId(context));
            await using var reader = await command.ExecuteReaderAsync(ct);
            var items = new List<object>();
            while (await reader.ReadAsync(ct))
                items.Add(new
                {
                    channelId = reader.GetInt64(0), channelName = reader.GetString(1), handle = reader.GetString(2),
                    description = reader.GetString(3),
                    avatarUrl = reader.IsDBNull(4) ? "" : $"/api/channels/{reader.GetInt64(0)}/avatar",
                    role = reader.GetString(5),
                    subscriberCount = reader.GetInt64(6)
                });
            return Results.Ok(new { items });
        });

        api.MapGet("/channels/mine/videos", async (HttpContext context, CancellationToken ct) =>
        {
            await using var connection = await database.OpenAsync(ct);
            var command = new SqlCommand(VideoEndpoints.VideoSelect + Environment.NewLine + """
                WHERE v.DeletedAt IS NULL AND (c.OwnerUserId = @UserId OR EXISTS
                    (SELECT 1 FROM dbo.ChannelMembers m WHERE m.ChannelId = c.ChannelId AND m.UserId = @UserId
                     AND m.MembershipStatus = 'active' AND m.MemberRole IN ('manager', 'editor')))
                ORDER BY v.CreatedAt DESC OFFSET 0 ROWS FETCH NEXT 100 ROWS ONLY;
                """, connection);
            command.Add("@UserId", SqlDbType.BigInt, ApiSql.UserId(context));
            return Results.Ok(new { items = await VideoEndpoints.ReadVideosAsync(command, ct) });
        });

        api.MapPost("/channels/mine", async (CreateChannelRequest request, HttpContext context, CancellationToken ct) =>
        {
            var name = (request.Name ?? request.ChannelName)?.Trim();
            var handle = string.IsNullOrWhiteSpace(request.Handle)
                ? $"user-{Guid.NewGuid():N}" : request.Handle.Trim().TrimStart('@');
            if (string.IsNullOrWhiteSpace(name) || name.Length > 100)
                return Results.BadRequest(new { error = "name (or channelName) is required and must be at most 100 characters." });
            if (handle.Length is < 3 or > 60 || handle.Any(character =>
                    !char.IsAsciiLetterOrDigit(character) && character is not ('.' or '_' or '-')))
                return Results.BadRequest(new { error = "handle must be 3 to 60 ASCII letters, numbers, dots, underscores, or hyphens." });
            if (request.Description?.Length > 2000)
                return Results.BadRequest(new { error = "description must be at most 2000 characters." });
            await using var connection = await database.OpenAsync(ct);
            await using var command = new SqlCommand("""
                INSERT dbo.Channels (OwnerUserId, ChannelName, Handle, Description)
                OUTPUT inserted.ChannelId VALUES (@UserId, @Name, @Handle, @Description);
                """, connection);
            command.Add("@UserId", SqlDbType.BigInt, ApiSql.UserId(context));
            command.Add("@Name", SqlDbType.NVarChar, name, 100);
            command.Add("@Handle", SqlDbType.NVarChar, handle, 60);
            command.Add("@Description", SqlDbType.NVarChar, request.Description?.Trim() ?? "", 2000);
            try
            {
                var channelId = Convert.ToInt64(await command.ExecuteScalarAsync(ct));
                return Results.Created($"/api/channels/{channelId}", new { channelId, channelName = name, handle });
            }
            catch (SqlException ex) when (ex.Number is 2601 or 2627)
            {
                return Results.Conflict(new { error = "That channel handle is already in use." });
            }
        });

        api.MapGet("/channels/{channelId:long}", async (long channelId, CancellationToken ct) =>
        {
            await using var connection = await database.OpenAsync(ct);
            await using var command = new SqlCommand("""
                SELECT c.ChannelId, c.ChannelName, c.Handle, c.Description, c.AvatarStorageKey,
                    (SELECT COUNT_BIG(*) FROM dbo.ChannelSubscriptions s WHERE s.ChannelId = c.ChannelId) AS SubscriberCount
                FROM dbo.Channels c WHERE c.ChannelId = @ChannelId AND c.IsActive = 1;
                """, connection);
            command.Add("@ChannelId", SqlDbType.BigInt, channelId);
            await using var reader = await command.ExecuteReaderAsync(ct);
            if (!await reader.ReadAsync(ct))
                return Results.NotFound();
            return Results.Ok(new
            {
                channelId = reader.GetInt64(0), channel = reader.GetString(1), handle = reader.GetString(2),
                description = reader.GetString(3),
                thumbnailUrl = reader.IsDBNull(4) ? "" : $"/api/channels/{channelId}/avatar",
                subscriberCount = reader.GetInt64(5)
            });
        });

        api.MapPatch("/channels/{channelId:long}", async (
            long channelId,
            UpdateChannelRequest request,
            HttpContext context,
            CancellationToken ct) =>
        {
            var name = request.ChannelName?.Trim();
            var description = request.Description?.Trim() ?? "";
            if (string.IsNullOrWhiteSpace(name) || name.Length > 100)
                return Results.BadRequest(new { error = "channelName is required and must be at most 100 characters." });
            if (description.Length > 2000)
                return Results.BadRequest(new { error = "description must be at most 2000 characters." });

            var userId = ApiSql.UserId(context);
            await using var connection = await database.OpenAsync(ct);
            await using var command = new SqlCommand("""
                UPDATE c SET ChannelName = @Name, Description = @Description,
                    UpdatedAt = SYSUTCDATETIME()
                FROM dbo.Channels c
                WHERE c.ChannelId = @ChannelId AND c.IsActive = 1
                  AND (c.OwnerUserId = @UserId OR EXISTS (
                      SELECT 1 FROM dbo.ChannelMembers m
                      WHERE m.ChannelId = c.ChannelId AND m.UserId = @UserId
                        AND m.MembershipStatus = 'active' AND m.MemberRole = 'manager'));
                """, connection);
            command.Add("@ChannelId", SqlDbType.BigInt, channelId);
            command.Add("@UserId", SqlDbType.BigInt, userId);
            command.Add("@Name", SqlDbType.NVarChar, name, 100);
            command.Add("@Description", SqlDbType.NVarChar, description, 2000);
            if (await command.ExecuteNonQueryAsync(ct) == 0)
                return Results.NotFound();
            return Results.Ok(new { channelId, channelName = name, description });
        });

        api.MapGet("/channels/{channelId:long}/avatar", async (
            long channelId,
            CancellationToken ct) =>
        {
            await using var connection = await database.OpenAsync(ct);
            await using var command = new SqlCommand("""
                SELECT AvatarStorageKey FROM dbo.Channels
                WHERE ChannelId = @ChannelId AND IsActive = 1;
                """, connection);
            command.Add("@ChannelId", SqlDbType.BigInt, channelId);
            var value = await command.ExecuteScalarAsync(ct);
            if (value is not string key || !ApiFiles.IsStorageKey(key))
                return Results.NotFound();
            var mimeType = ApiFiles.GetMimeType(Path.GetExtension(key));
            if (!ApiFiles.IsImageMimeType(mimeType))
                return Results.NotFound();
            var path = Path.Combine(mediaRoot, key);
            return File.Exists(path)
                ? Results.File(path, mimeType, enableRangeProcessing: true)
                : Results.NotFound();
        });

        api.MapGet("/channels/{channelId:long}/videos", async (long channelId, HttpContext context, CancellationToken ct) =>
        {
            await using var connection = await database.OpenAsync(ct);
            var command = new SqlCommand(VideoEndpoints.VideoSelect + Environment.NewLine + """
                WHERE v.ChannelId = @ChannelId AND v.DeletedAt IS NULL AND v.VideoStatus = 'ready'
                  AND (v.Visibility = 'public' OR c.OwnerUserId = @UserId OR
                       EXISTS (SELECT 1 FROM dbo.ChannelMembers m
                           WHERE m.ChannelId = c.ChannelId AND m.UserId = @UserId
                           AND m.MembershipStatus = 'active' AND m.MemberRole IN ('manager', 'editor')))
                ORDER BY COALESCE(v.PublishedAt, v.CreatedAt) DESC
                OFFSET 0 ROWS FETCH NEXT 100 ROWS ONLY;
                """, connection);
            command.Add("@ChannelId", SqlDbType.BigInt, channelId);
            command.Add("@UserId", SqlDbType.BigInt, ApiSql.UserId(context));
            return Results.Ok(new { items = await VideoEndpoints.ReadVideosAsync(command, ct) });
        });

        api.MapPost("/channels/mine/videos", async (
            [FromForm] IFormFile file,
            [FromForm] string title,
            [FromForm] string? description,
            [FromForm] int? categoryId,
            [FromForm] string? visibility,
            HttpContext context,
            CancellationToken ct) =>
        {
            var userId = ApiSql.UserId(context);
            var trimmedTitle = title?.Trim();
            var normalizedVisibility = string.IsNullOrWhiteSpace(visibility) ? "public" : visibility.Trim().ToLowerInvariant();
            if (string.IsNullOrWhiteSpace(trimmedTitle) || trimmedTitle.Length > 200)
                return Results.BadRequest(new { error = "title is required and must be at most 200 characters." });
            if (description?.Length > 1_000_000)
                return Results.BadRequest(new { error = "description is too long." });
            if (normalizedVisibility is not ("public" or "unlisted" or "private"))
                return Results.BadRequest(new { error = "visibility must be public, unlisted, or private." });
            if (!ApiFiles.IsAllowedVideo(file) || file.Length > maxUploadBytes)
                return Results.BadRequest(new { error = $"file must be a supported video and no larger than {maxUploadBytes} bytes." });

            await using var connection = await database.OpenAsync(ct);
            var channelId = await FindManageableChannelAsync(connection, userId, ct);
            if (channelId is null)
                return Results.Forbid();
            if (categoryId.HasValue)
            {
                await using var checkCategory = new SqlCommand(
                    "SELECT 1 FROM dbo.VideoCategories WHERE CategoryId = @CategoryId AND IsActive = 1;", connection);
                checkCategory.Add("@CategoryId", SqlDbType.Int, categoryId.Value);
                if (await checkCategory.ExecuteScalarAsync(ct) is null)
                    return Results.BadRequest(new { error = "categoryId does not identify an active category." });
            }

            var extension = Path.GetExtension(file.FileName).ToLowerInvariant();
            var storageKey = ApiFiles.NewStorageKey(extension);
            Directory.CreateDirectory(mediaRoot);
            var path = Path.Combine(mediaRoot, storageKey);
            await using (var output = new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.None,
                128 * 1024, FileOptions.Asynchronous | FileOptions.SequentialScan))
                await file.CopyToAsync(output, ct);

            long videoId;
            await using (var insert = new SqlCommand("""
                INSERT dbo.Videos (ChannelId, CategoryId, Title, Description, MediaStorageKey, SourceFileName,
                    MediaType, MediaSizeBytes, Visibility, VideoStatus, PublishedAt)
                OUTPUT inserted.VideoId
                VALUES (@ChannelId, @CategoryId, @Title, @Description, @StorageKey, @SourceFileName,
                    @MediaType, @Size, @Visibility, 'ready',
                    CASE WHEN @Visibility IN ('public', 'unlisted') THEN SYSUTCDATETIME() ELSE NULL END);
                """, connection))
            {
                insert.Add("@ChannelId", SqlDbType.BigInt, channelId.Value);
                insert.Add("@CategoryId", SqlDbType.Int, categoryId);
                insert.Add("@Title", SqlDbType.NVarChar, trimmedTitle, 200);
                insert.Add("@Description", SqlDbType.NVarChar, description?.Trim() ?? "");
                insert.Add("@StorageKey", SqlDbType.NVarChar, storageKey, 1024);
                insert.Add("@SourceFileName", SqlDbType.NVarChar,
                    Path.GetFileName(file.FileName)[..Math.Min(Path.GetFileName(file.FileName).Length, 260)], 260);
                insert.Add("@MediaType", SqlDbType.VarChar, ApiFiles.GetMimeType(extension), 100);
                insert.Add("@Size", SqlDbType.BigInt, file.Length);
                insert.Add("@Visibility", SqlDbType.VarChar, normalizedVisibility, 12);
                videoId = Convert.ToInt64(await insert.ExecuteScalarAsync(ct));
            }

            if (normalizedVisibility == "public")
            {
                await using var notify = new SqlCommand("""
                    INSERT dbo.Notifications (RecipientUserId, ActorUserId, NotificationType, VideoId, Message)
                    SELECT SubscriberUserId, @UserId, 'new_video', @VideoId, @Message
                    FROM dbo.ChannelSubscriptions WHERE ChannelId = @ChannelId AND SubscriberUserId <> @UserId;
                    """, connection);
                notify.Add("@UserId", SqlDbType.BigInt, userId);
                notify.Add("@VideoId", SqlDbType.BigInt, videoId);
                notify.Add("@ChannelId", SqlDbType.BigInt, channelId.Value);
                notify.Add("@Message", SqlDbType.NVarChar, $"New video: {trimmedTitle}", 500);
                await notify.ExecuteNonQueryAsync(ct);
            }
            return Results.Created($"/api/videos/{videoId}", new
            {
                videoId, title = trimmedTitle, storageKey,
                streamUrl = $"/api/videos/{videoId}/stream",
                thumbnailUrl = $"/api/videos/{videoId}/thumbnail", visibility = normalizedVisibility
            });
        }).DisableAntiforgery();

        api.MapPost("/channels/mine/videos/uploads", async (
            BeginVideoUploadRequest request,
            HttpContext context,
            CancellationToken ct) =>
        {
            var fileName = Path.GetFileName((request.FileName ?? "").Replace('\\', '/')).Trim();
            var title = request.Title?.Trim();
            var description = request.Description?.Trim() ?? "";
            var visibility = string.IsNullOrWhiteSpace(request.Visibility)
                ? "public"
                : request.Visibility.Trim().ToLowerInvariant();
            if (string.IsNullOrWhiteSpace(title) || title.Length > 200)
                return Results.BadRequest(new { error = "title is required and must be at most 200 characters." });
            if (description.Length > 1_000_000)
                return Results.BadRequest(new { error = "description is too long." });
            if (visibility is not ("public" or "unlisted" or "private"))
                return Results.BadRequest(new { error = "visibility must be public, unlisted, or private." });
            if (request.FileSize <= 0 || request.FileSize > maxUploadBytes
                || !ApiFiles.AllowedVideoFileName(fileName))
                return Results.BadRequest(new
                {
                    error = $"file must be a supported video and no larger than {maxUploadBytes} bytes."
                });
            if (request.DurationSeconds is < 0 or > 86_400)
                return Results.BadRequest(new { error = "durationSeconds must be between 0 and 86400." });

            var userId = ApiSql.UserId(context);
            await using var connection = await database.OpenAsync(ct);
            var channelId = await FindManageableChannelAsync(connection, userId, ct);
            if (channelId is null)
                return Results.Forbid();
            if (request.CategoryId.HasValue)
            {
                await using var category = new SqlCommand(
                    "SELECT 1 FROM dbo.VideoCategories WHERE CategoryId = @CategoryId AND IsActive = 1;",
                    connection);
                category.Add("@CategoryId", SqlDbType.Int, request.CategoryId.Value);
                if (await category.ExecuteScalarAsync(ct) is null)
                    return Results.BadRequest(new { error = "categoryId does not identify an active category." });
            }

            var upload = await chunkedUploads.CreateAsync(
                userId,
                channelId.Value,
                fileName,
                title,
                description,
                request.CategoryId,
                visibility,
                request.DurationSeconds ?? 0,
                request.FileSize,
                ct);
            return Results.Ok(new
            {
                uploadId = upload.Id,
                chunkSize = ChunkedVideoUploadStore.ChunkSize,
            });
        });

        api.MapPut(
            "/channels/mine/videos/uploads/{uploadId:guid}/thumbnail",
            async (Guid uploadId, HttpContext context, CancellationToken ct) =>
            {
                ChunkedVideoUpload upload;
                try
                {
                    upload = chunkedUploads.Get(uploadId, ApiSql.UserId(context));
                }
                catch (ChunkedVideoUploadException error)
                {
                    return Results.Json(new { error = error.Message }, statusCode: error.StatusCode);
                }

                var mimeType = context.Request.ContentType?.Split(';')[0].Trim().ToLowerInvariant();
                if (mimeType is not ("image/jpeg" or "image/png" or "image/webp")
                    || context.Request.ContentLength is not > 0 or > 5_242_880)
                    return Results.BadRequest(new { error = "thumbnail must be a JPEG, PNG, or WebP image up to 5 MiB." });
                if (!await upload.Gate.WaitAsync(0, ct))
                    return Results.Conflict(new { error = "The upload is currently receiving another file part." });

                try
                {
                    if (upload.BytesReceived != upload.FileSize)
                        return Results.Conflict(new { error = "Upload all video chunks before sending its thumbnail." });

                    await using var output = new FileStream(
                        upload.ThumbnailTemporaryPath,
                        FileMode.Create,
                        FileAccess.Write,
                        FileShare.None,
                        64 * 1024,
                        FileOptions.Asynchronous | FileOptions.SequentialScan);
                    await context.Request.Body.CopyToAsync(output, ct);
                    if (output.Length != context.Request.ContentLength)
                    {
                        output.Close();
                        File.Delete(upload.ThumbnailTemporaryPath);
                        return Results.BadRequest(new { error = "Thumbnail size does not match Content-Length." });
                    }
                    upload.ThumbnailMimeType = mimeType;
                    return Results.Ok(new { uploaded = true });
                }
                finally
                {
                    upload.Gate.Release();
                }
            });

        api.MapPut(
            "/channels/mine/videos/uploads/{uploadId:guid}/chunks/{chunkIndex:int}",
            async (Guid uploadId, int chunkIndex, HttpContext context, CancellationToken ct) =>
            {
                ChunkedVideoUpload upload;
                try
                {
                    upload = chunkedUploads.Get(uploadId, ApiSql.UserId(context));
                }
                catch (ChunkedVideoUploadException error)
                {
                    return Results.Json(new { error = error.Message }, statusCode: error.StatusCode);
                }

                await upload.Gate.WaitAsync(ct);
                try
                {
                    if (chunkIndex != upload.NextChunkIndex)
                        return Results.Conflict(new { error = "Video chunks must be sent in order." });
                    if (upload.BytesReceived >= upload.FileSize)
                        return Results.Conflict(new { error = "All file bytes have already been received." });
                    var expectedLength = (int)Math.Min(
                        ChunkedVideoUploadStore.ChunkSize,
                        upload.FileSize - upload.BytesReceived);
                    if (context.Request.ContentLength != expectedLength)
                        return Results.BadRequest(new
                        {
                            error = $"This chunk must contain exactly {expectedLength} bytes."
                        });

                    await using (var output = new FileStream(
                        upload.TemporaryPath,
                        FileMode.Append,
                        FileAccess.Write,
                        FileShare.None,
                        128 * 1024,
                        FileOptions.Asynchronous | FileOptions.SequentialScan))
                    {
                        await context.Request.Body.CopyToAsync(output, ct);
                    }
                    upload.BytesReceived += expectedLength;
                    upload.NextChunkIndex++;
                    return Results.Ok(new { bytesReceived = upload.BytesReceived });
                }
                finally
                {
                    upload.Gate.Release();
                }
            });

        api.MapPost(
            "/channels/mine/videos/uploads/{uploadId:guid}/complete",
            async (Guid uploadId, HttpContext context, CancellationToken ct) =>
            {
                ChunkedVideoUpload upload;
                try
                {
                    upload = chunkedUploads.Get(uploadId, ApiSql.UserId(context));
                }
                catch (ChunkedVideoUploadException error)
                {
                    return Results.Json(new { error = error.Message }, statusCode: error.StatusCode);
                }

                await upload.Gate.WaitAsync(ct);
                string? finalPath = null;
                string? finalThumbnailPath = null;
                var committed = false;
                try
                {
                    if (upload.BytesReceived != upload.FileSize
                        || new FileInfo(upload.TemporaryPath).Length != upload.FileSize)
                        return Results.Conflict(new
                        {
                            error = $"Upload is incomplete ({upload.BytesReceived} of {upload.FileSize} bytes)."
                        });

                    var userId = ApiSql.UserId(context);
                    await using var connection = await database.OpenAsync(ct);
                    var currentChannelId = await FindManageableChannelAsync(connection, userId, ct);
                    if (currentChannelId != upload.ChannelId)
                        return Results.Forbid();

                    var extension = Path.GetExtension(upload.FileName).ToLowerInvariant();
                    var storageKey = ApiFiles.NewStorageKey(extension);
                    Directory.CreateDirectory(mediaRoot);
                    finalPath = Path.Combine(mediaRoot, storageKey);
                    File.Move(upload.TemporaryPath, finalPath);
                    string? thumbnailStorageKey = null;
                    if (upload.ThumbnailMimeType is { } thumbnailMimeType
                        && File.Exists(upload.ThumbnailTemporaryPath))
                    {
                        var thumbnailExtension = thumbnailMimeType switch
                        {
                            "image/jpeg" => ".jpg",
                            "image/png" => ".png",
                            "image/webp" => ".webp",
                            _ => throw new InvalidOperationException("Unsupported thumbnail content type."),
                        };
                        thumbnailStorageKey = ApiFiles.NewStorageKey(thumbnailExtension);
                        finalThumbnailPath = Path.Combine(mediaRoot, thumbnailStorageKey);
                        File.Move(upload.ThumbnailTemporaryPath, finalThumbnailPath);
                    }

                    long videoId;
                    await using (var transaction = (SqlTransaction)await connection.BeginTransactionAsync(ct))
                    {
                        await using (var insert = new SqlCommand("""
                            INSERT dbo.Videos (ChannelId, CategoryId, Title, Description, MediaStorageKey,
                                ThumbnailStorageKey, SourceFileName, MediaType, MediaSizeBytes, DurationSeconds,
                                Visibility, VideoStatus, PublishedAt)
                            OUTPUT inserted.VideoId
                            VALUES (@ChannelId, @CategoryId, @Title, @Description, @StorageKey,
                                @ThumbnailStorageKey, @SourceFileName, @MediaType, @Size, @DurationSeconds,
                                @Visibility, 'ready',
                                CASE WHEN @Visibility IN ('public', 'unlisted') THEN SYSUTCDATETIME() ELSE NULL END);
                            """, connection, transaction))
                        {
                            insert.Add("@ChannelId", SqlDbType.BigInt, upload.ChannelId);
                            insert.Add("@CategoryId", SqlDbType.Int, upload.CategoryId);
                            insert.Add("@Title", SqlDbType.NVarChar, upload.Title, 200);
                            insert.Add("@Description", SqlDbType.NVarChar, upload.Description);
                            insert.Add("@StorageKey", SqlDbType.NVarChar, storageKey, 1024);
                            insert.Add("@ThumbnailStorageKey", SqlDbType.NVarChar, thumbnailStorageKey, 1024);
                            insert.Add("@SourceFileName", SqlDbType.NVarChar, upload.FileName, 260);
                            insert.Add("@MediaType", SqlDbType.VarChar, ApiFiles.GetMimeType(extension), 100);
                            insert.Add("@Size", SqlDbType.BigInt, upload.FileSize);
                            insert.Add("@DurationSeconds", SqlDbType.Int, upload.DurationSeconds);
                            insert.Add("@Visibility", SqlDbType.VarChar, upload.Visibility, 12);
                            videoId = Convert.ToInt64(await insert.ExecuteScalarAsync(ct));
                        }

                        if (upload.Visibility == "public")
                        {
                            await using var notify = new SqlCommand("""
                                INSERT dbo.Notifications (RecipientUserId, ActorUserId, NotificationType, VideoId, Message)
                                SELECT SubscriberUserId, @UserId, 'new_video', @VideoId, @Message
                                FROM dbo.ChannelSubscriptions
                                WHERE ChannelId = @ChannelId AND SubscriberUserId <> @UserId;
                                """, connection, transaction);
                            notify.Add("@UserId", SqlDbType.BigInt, userId);
                            notify.Add("@VideoId", SqlDbType.BigInt, videoId);
                            notify.Add("@ChannelId", SqlDbType.BigInt, upload.ChannelId);
                            notify.Add("@Message", SqlDbType.NVarChar, $"New video: {upload.Title}", 500);
                            await notify.ExecuteNonQueryAsync(ct);
                        }

                        await transaction.CommitAsync(ct);
                        committed = true;
                    }

                    chunkedUploads.Remove(upload);
                    return Results.Created($"/api/videos/{videoId}", new
                    {
                        videoId,
                        title = upload.Title,
                        storageKey,
                        streamUrl = $"/api/videos/{videoId}/stream",
                        thumbnailUrl = thumbnailStorageKey is null ? "" : $"/api/videos/{videoId}/thumbnail",
                        durationSeconds = upload.DurationSeconds,
                        duration = VideoEndpoints.FormatDuration(upload.DurationSeconds),
                        visibility = upload.Visibility,
                    });
                }
                catch
                {
                    if (!committed && finalPath is not null && File.Exists(finalPath))
                        File.Delete(finalPath);
                    if (!committed && finalThumbnailPath is not null && File.Exists(finalThumbnailPath))
                        File.Delete(finalThumbnailPath);
                    throw;
                }
                finally
                {
                    upload.Gate.Release();
                }
            });

        api.MapDelete(
            "/channels/mine/videos/uploads/{uploadId:guid}",
            (Guid uploadId, HttpContext context) =>
            {
                ChunkedVideoUpload upload;
                try
                {
                    upload = chunkedUploads.Get(uploadId, ApiSql.UserId(context));
                }
                catch (ChunkedVideoUploadException error)
                {
                    return Results.Json(new { error = error.Message }, statusCode: error.StatusCode);
                }
                if (!upload.Gate.Wait(0))
                    return Results.Conflict(new { error = "The upload is currently receiving a chunk." });
                try
                {
                    chunkedUploads.Remove(upload);
                    return Results.NoContent();
                }
                finally
                {
                    upload.Gate.Release();
                }
            });

        api.MapPatch("/channels/mine/videos/{videoId:long}", async (long videoId,
            VideoUpdateRequest request, HttpContext context, CancellationToken ct) =>
        {
            if (request.Title is not null && (string.IsNullOrWhiteSpace(request.Title) || request.Title.Trim().Length > 200))
                return Results.BadRequest(new { error = "title must contain 1 to 200 characters." });
            if (request.Description?.Length > 1_000_000)
                return Results.BadRequest(new { error = "description is too long." });
            var visibility = request.Visibility?.Trim().ToLowerInvariant();
            if (visibility is not null && visibility is not ("public" or "unlisted" or "private"))
                return Results.BadRequest(new { error = "visibility must be public, unlisted, or private." });
            var userId = ApiSql.UserId(context);
            await using var connection = await database.OpenAsync(ct);
            if (!await CanManageVideoAsync(connection, userId, videoId, ct))
                return Results.NotFound();
            if (request.CategoryId.HasValue)
            {
                await using var category = new SqlCommand(
                    "SELECT 1 FROM dbo.VideoCategories WHERE CategoryId = @Id AND IsActive = 1;", connection);
                category.Add("@Id", SqlDbType.Int, request.CategoryId.Value);
                if (await category.ExecuteScalarAsync(ct) is null)
                    return Results.BadRequest(new { error = "categoryId does not identify an active category." });
            }
            await using var command = new SqlCommand("""
                UPDATE dbo.Videos SET
                    Title = COALESCE(@Title, Title),
                    Description = COALESCE(@Description, Description),
                    CategoryId = COALESCE(@CategoryId, CategoryId),
                    Visibility = COALESCE(@Visibility, Visibility),
                    PublishedAt = CASE WHEN @Visibility = 'public' AND PublishedAt IS NULL THEN SYSUTCDATETIME()
                                      WHEN @Visibility = 'private' THEN NULL ELSE PublishedAt END,
                    UpdatedAt = SYSUTCDATETIME()
                WHERE VideoId = @VideoId AND DeletedAt IS NULL;
                """, connection);
            command.Add("@Title", SqlDbType.NVarChar, request.Title?.Trim(), 200);
            command.Add("@Description", SqlDbType.NVarChar, request.Description?.Trim());
            command.Add("@CategoryId", SqlDbType.Int, request.CategoryId);
            command.Add("@Visibility", SqlDbType.VarChar, visibility, 12);
            command.Add("@VideoId", SqlDbType.BigInt, videoId);
            await command.ExecuteNonQueryAsync(ct);
            return Results.Ok(new { videoId, updated = true });
        });

        api.MapDelete("/channels/mine/videos/{videoId:long}", async (long videoId, HttpContext context, CancellationToken ct) =>
        {
            var userId = ApiSql.UserId(context);
            await using var connection = await database.OpenAsync(ct);
            if (!await CanManageVideoAsync(connection, userId, videoId, ct))
                return Results.NotFound();
            await using var command = new SqlCommand("""
                UPDATE dbo.Videos SET DeletedAt = SYSUTCDATETIME(), UpdatedAt = SYSUTCDATETIME()
                WHERE VideoId = @VideoId AND DeletedAt IS NULL;
                """, connection);
            command.Add("@VideoId", SqlDbType.BigInt, videoId);
            await command.ExecuteNonQueryAsync(ct);
            return Results.NoContent();
        });
    }

    private static async Task<long?> FindManageableChannelAsync(SqlConnection connection, long userId, CancellationToken ct)
    {
        await using var command = new SqlCommand("""
            SELECT TOP (1) c.ChannelId FROM dbo.Channels c
            WHERE c.IsActive = 1 AND (c.OwnerUserId = @UserId OR EXISTS
                (SELECT 1 FROM dbo.ChannelMembers m WHERE m.ChannelId = c.ChannelId AND m.UserId = @UserId
                 AND m.MembershipStatus = 'active' AND m.MemberRole IN ('manager', 'editor')))
            ORDER BY CASE WHEN c.OwnerUserId = @UserId THEN 0 ELSE 1 END, c.ChannelId;
            """, connection);
        command.Add("@UserId", SqlDbType.BigInt, userId);
        return await ApiSql.ScalarIdAsync(command, ct);
    }

    private static async Task<bool> CanManageVideoAsync(SqlConnection connection, long userId, long videoId, CancellationToken ct)
    {
        await using var command = new SqlCommand("""
            SELECT CASE WHEN EXISTS (
                SELECT 1 FROM dbo.Videos v INNER JOIN dbo.Channels c ON c.ChannelId = v.ChannelId
                WHERE v.VideoId = @VideoId AND v.DeletedAt IS NULL AND c.IsActive = 1
                  AND (c.OwnerUserId = @UserId OR EXISTS (SELECT 1 FROM dbo.ChannelMembers m
                      WHERE m.ChannelId = c.ChannelId AND m.UserId = @UserId
                        AND m.MembershipStatus = 'active' AND m.MemberRole IN ('manager', 'editor')))
            ) THEN 1 ELSE 0 END;
            """, connection);
        command.Add("@VideoId", SqlDbType.BigInt, videoId);
        command.Add("@UserId", SqlDbType.BigInt, userId);
        return Convert.ToInt32(await command.ExecuteScalarAsync(ct)) == 1;
    }
}

public sealed record CreateChannelRequest(string? Name = null, string? ChannelName = null,
    string? Handle = null, string? Description = null);
public sealed record VideoUpdateRequest(string? Title, string? Description, int? CategoryId, string? Visibility);
public sealed record UpdateChannelRequest(string? ChannelName, string? Description);
