using System.Data;
using System.Security.Cryptography;
using System.Text;
using Microsoft.Data.SqlClient;

public static class AuthEndpoints
{
    private const int Iterations = 210_000;

    public static void Map(RouteGroupBuilder api, ApiDatabase database,
        PasswordResetEmailSender emailSender, int sessionDays, ILogger logger)
    {
        api.MapPost("/auth/register", async (RegisterRequest request, CancellationToken ct) =>
        {
            if (!ValidEmail(request.Email) || string.IsNullOrWhiteSpace(request.DisplayName)
                || request.DisplayName.Trim().Length > 100 || !ValidPassword(request.Password))
                return Results.ValidationProblem(new Dictionary<string, string[]>
                {
                    ["request"] = ["Provide a valid email, a password of at least 8 characters, and a display name up to 100 characters."]
                });
            try
            {
                var user = await CreatePasswordUserAsync(database, request.Email!.Trim(), request.Password!,
                    request.DisplayName!.Trim(), null, ct);
                return Results.Created("/api/account/me", user);
            }
            catch (SqlException ex) when (ex.Number is 2601 or 2627)
            {
                return Results.Conflict(new { error = "An account with this email already exists." });
            }
        });

        api.MapPost("/auth/login", async (LoginRequest request, CancellationToken ct) =>
        {
            if (!ValidEmail(request.Email) || string.IsNullOrEmpty(request.Password))
                return Results.Unauthorized();
            await using var connection = await database.OpenAsync(ct);
            await using var command = new SqlCommand("""
                SELECT u.UserId, u.DisplayName, u.Email, u.AvatarUrl,
                       p.PasswordHash, p.PasswordSalt, p.HashAlgorithm, p.WorkFactor
                FROM dbo.Users u
                INNER JOIN dbo.PasswordCredentials p ON p.UserId = u.UserId
                WHERE u.EmailNormalized = LOWER(LTRIM(RTRIM(@Email))) AND u.IsActive = 1;
                """, connection);
            command.Add("@Email", SqlDbType.NVarChar, request.Email!.Trim(), 320);
            await using var reader = await command.ExecuteReaderAsync(ct);
            if (!await reader.ReadAsync(ct))
                return Results.Unauthorized();
            var userId = reader.GetInt64(0);
            var user = new UserDto(userId, reader.GetString(1), reader.GetString(2),
                reader.IsDBNull(3) ? null : reader.GetString(3));
            var expected = (byte[])reader[4];
            var salt = (byte[])reader[5];
            var algorithm = reader.GetString(6);
            var workFactor = reader.GetInt32(7);
            await reader.DisposeAsync();
            if (!string.Equals(algorithm, "PBKDF2-SHA256", StringComparison.Ordinal)
                || workFactor is < 100_000 or > 2_000_000
                || !CryptographicOperations.FixedTimeEquals(expected,
                    Rfc2898DeriveBytes.Pbkdf2(request.Password!, salt, workFactor, HashAlgorithmName.SHA256, expected.Length)))
                return Results.Unauthorized();
            await using var transaction = (SqlTransaction)await connection.BeginTransactionAsync(ct);
            await EnsureChannelAsync(connection, transaction, userId, user.DisplayName, ct);
            var token = await CreateSessionAsync(connection, transaction, userId, sessionDays, ct);
            await transaction.CommitAsync(ct);
            return Results.Ok(new AuthResponse(token, user));
        });

        api.MapPost("/auth/password-reset/request", async (
            PasswordResetRequest request, CancellationToken ct) =>
        {
            if (!ValidEmail(request.Email))
                return Results.ValidationProblem(new Dictionary<string, string[]>
                {
                    ["email"] = ["Provide a valid email address."]
                });
            if (!emailSender.IsConfigured)
                return Results.Problem(statusCode: StatusCodes.Status503ServiceUnavailable,
                    title: "Password reset email is not configured.",
                    detail: "Configure the Email SMTP settings before requesting a password reset.");

            var email = request.Email!.Trim();
            var token = NewToken();
            long? userId = null;
            await using (var connection = await database.OpenAsync(ct))
            await using (var transaction = (SqlTransaction)await connection.BeginTransactionAsync(ct))
            {
                await using (var findUser = new SqlCommand("""
                    SELECT TOP (1) UserId FROM dbo.Users WITH (UPDLOCK, HOLDLOCK)
                    WHERE EmailNormalized = LOWER(LTRIM(RTRIM(@Email))) AND IsActive = 1;
                    """, connection, transaction))
                {
                    findUser.Add("@Email", SqlDbType.NVarChar, email, 320);
                    var result = await findUser.ExecuteScalarAsync(ct);
                    if (result is not null and not DBNull)
                        userId = Convert.ToInt64(result);
                }

                if (userId.HasValue)
                {
                    await using var recentRequest = new SqlCommand("""
                        SELECT COUNT_BIG(*) FROM dbo.UserAuthTokens
                        WHERE UserId = @UserId AND Purpose = 'PASSWORD_RESET'
                          AND CreatedAt > DATEADD(minute, -5, SYSUTCDATETIME());
                        """, connection, transaction);
                    recentRequest.Add("@UserId", SqlDbType.BigInt, userId.Value);
                    if (Convert.ToInt64(await recentRequest.ExecuteScalarAsync(ct)) == 0)
                    {
                        await using var replace = new SqlCommand("""
                            UPDATE dbo.UserAuthTokens SET ConsumedAt = SYSUTCDATETIME()
                            WHERE UserId = @UserId AND Purpose = 'PASSWORD_RESET'
                              AND ConsumedAt IS NULL;
                            INSERT dbo.UserAuthTokens (UserId, Purpose, TokenHash, ExpiresAt)
                            VALUES (@UserId, 'PASSWORD_RESET', @TokenHash,
                                DATEADD(minute, 30, SYSUTCDATETIME()));
                            """, connection, transaction);
                        replace.Add("@UserId", SqlDbType.BigInt, userId.Value);
                        replace.Add("@TokenHash", SqlDbType.Binary, HashToken(token), 32);
                        await replace.ExecuteNonQueryAsync(ct);
                    }
                    else
                    {
                        userId = null;
                    }
                }
                await transaction.CommitAsync(ct);
            }

            if (userId.HasValue)
            {
                try
                {
                    await emailSender.SendPasswordResetAsync(email, token, ct);
                }
                catch (Exception ex) when (!ct.IsCancellationRequested)
                {
                    logger.LogError(ex, "Unable to deliver password-reset email.");
                    await using var connection = await database.OpenAsync(ct);
                    await using var invalidate = new SqlCommand("""
                        UPDATE dbo.UserAuthTokens SET ConsumedAt = SYSUTCDATETIME()
                        WHERE TokenHash = @TokenHash AND Purpose = 'PASSWORD_RESET'
                          AND ConsumedAt IS NULL;
                        """, connection);
                    invalidate.Add("@TokenHash", SqlDbType.Binary, HashToken(token), 32);
                    await invalidate.ExecuteNonQueryAsync(ct);
                    return Results.Problem(statusCode: StatusCodes.Status503ServiceUnavailable,
                        title: "Password reset email could not be delivered.",
                        detail: "Check the email server settings and try again later.");
                }
            }
            return Results.Ok(new { message = "If the account exists, a reset code has been emailed." });
        });

        api.MapPost("/auth/password-reset/complete", async (
            CompletePasswordResetRequest request, CancellationToken ct) =>
        {
            if (!ValidEmail(request.Email) || string.IsNullOrWhiteSpace(request.Token)
                || request.Token.Length > 128 || !ValidPassword(request.NewPassword))
                return Results.ValidationProblem(new Dictionary<string, string[]>
                {
                    ["request"] = ["Provide a valid email, reset code, and a password of at least 8 characters."]
                });

            await using var connection = await database.OpenAsync(ct);
            await using var transaction = (SqlTransaction)await connection.BeginTransactionAsync(ct);
            long userId;
            long authTokenId;
            await using (var findToken = new SqlCommand("""
                SELECT TOP (1) u.UserId, t.AuthTokenId
                FROM dbo.UserAuthTokens t WITH (UPDLOCK, ROWLOCK)
                INNER JOIN dbo.Users u ON u.UserId = t.UserId
                INNER JOIN dbo.PasswordCredentials p ON p.UserId = u.UserId
                WHERE u.EmailNormalized = LOWER(LTRIM(RTRIM(@Email)))
                  AND u.IsActive = 1 AND t.Purpose = 'PASSWORD_RESET'
                  AND t.TokenHash = @TokenHash AND t.ConsumedAt IS NULL
                  AND t.ExpiresAt > SYSUTCDATETIME();
                """, connection, transaction))
            {
                findToken.Add("@Email", SqlDbType.NVarChar, request.Email!.Trim(), 320);
                findToken.Add("@TokenHash", SqlDbType.Binary, HashToken(request.Token!), 32);
                await using var reader = await findToken.ExecuteReaderAsync(ct);
                if (!await reader.ReadAsync(ct))
                    return Results.BadRequest(new { error = "The reset code is invalid or expired." });
                userId = reader.GetInt64(0);
                authTokenId = reader.GetInt64(1);
            }

            var salt = RandomNumberGenerator.GetBytes(32);
            var hash = Rfc2898DeriveBytes.Pbkdf2(request.NewPassword!, salt, Iterations,
                HashAlgorithmName.SHA256, 32);
            await using (var updateCredential = new SqlCommand("""
                UPDATE dbo.PasswordCredentials
                SET PasswordHash = @Hash, PasswordSalt = @Salt,
                    HashAlgorithm = 'PBKDF2-SHA256', WorkFactor = @WorkFactor,
                    ChangedAt = SYSUTCDATETIME()
                WHERE UserId = @UserId;
                UPDATE dbo.UserAuthTokens SET ConsumedAt = SYSUTCDATETIME()
                WHERE AuthTokenId = @AuthTokenId AND ConsumedAt IS NULL;
                UPDATE dbo.UserSessions SET RevokedAt = SYSUTCDATETIME()
                WHERE UserId = @UserId AND RevokedAt IS NULL;
                """, connection, transaction))
            {
                updateCredential.Add("@Hash", SqlDbType.VarBinary, hash, 32);
                updateCredential.Add("@Salt", SqlDbType.VarBinary, salt, 32);
                updateCredential.Add("@WorkFactor", SqlDbType.Int, Iterations);
                updateCredential.Add("@UserId", SqlDbType.BigInt, userId);
                updateCredential.Add("@AuthTokenId", SqlDbType.BigInt, authTokenId);
                await updateCredential.ExecuteNonQueryAsync(ct);
            }
            await transaction.CommitAsync(ct);
            return Results.Ok(new { message = "Password updated successfully." });
        });

        api.MapPost("/auth/logout", async (HttpContext context, CancellationToken ct) =>
        {
            var token = ReadBearer(context.Request);
            if (token is null)
                return Results.Unauthorized();
            await using var connection = await database.OpenAsync(ct);
            await using var command = new SqlCommand("""
                UPDATE dbo.UserSessions SET RevokedAt = SYSUTCDATETIME()
                WHERE RefreshTokenHash = @TokenHash AND RevokedAt IS NULL;
                """, connection);
            command.Add("@TokenHash", SqlDbType.Binary, SHA256.HashData(Encoding.UTF8.GetBytes(token)));
            await command.ExecuteNonQueryAsync(ct);
            return Results.NoContent();
        });
    }

    private static async Task<UserDto> CreatePasswordUserAsync(ApiDatabase database, string email,
        string password, string displayName, string? photoUrl, CancellationToken ct)
    {
        await using var connection = await database.OpenAsync(ct);
        await using var transaction = (SqlTransaction)await connection.BeginTransactionAsync(ct);
        var salt = RandomNumberGenerator.GetBytes(32);
        var hash = Rfc2898DeriveBytes.Pbkdf2(password, salt, Iterations, HashAlgorithmName.SHA256, 32);
        long userId;
        await using (var userCommand = new SqlCommand("""
            INSERT dbo.Users (Email, DisplayName, AvatarUrl)
            OUTPUT inserted.UserId VALUES (@Email, @DisplayName, @AvatarUrl);
            """, connection, transaction))
        {
            userCommand.Add("@Email", SqlDbType.NVarChar, email, 320);
            userCommand.Add("@DisplayName", SqlDbType.NVarChar, displayName, 100);
            userCommand.Add("@AvatarUrl", SqlDbType.NVarChar, photoUrl, 2048);
            userId = Convert.ToInt64(await userCommand.ExecuteScalarAsync(ct));
        }
        await using (var credential = new SqlCommand("""
            INSERT dbo.PasswordCredentials (UserId, PasswordHash, PasswordSalt, HashAlgorithm, WorkFactor)
            VALUES (@UserId, @Hash, @Salt, 'PBKDF2-SHA256', @WorkFactor);
            INSERT dbo.UserPreferences (UserId) VALUES (@UserId);
            """, connection, transaction))
        {
            credential.Add("@UserId", SqlDbType.BigInt, userId);
            credential.Add("@Hash", SqlDbType.VarBinary, hash, 32);
            credential.Add("@Salt", SqlDbType.VarBinary, salt, 32);
            credential.Add("@WorkFactor", SqlDbType.Int, Iterations);
            await credential.ExecuteNonQueryAsync(ct);
        }
        await EnsureChannelAsync(connection, transaction, userId, displayName, ct);
        await transaction.CommitAsync(ct);
        return new UserDto(userId, displayName, email, photoUrl);
    }

    private static async Task EnsureChannelAsync(SqlConnection connection, SqlTransaction transaction,
        long userId, string name, CancellationToken ct)
    {
        await using var command = new SqlCommand("""
            IF NOT EXISTS (SELECT 1 FROM dbo.Channels WITH (UPDLOCK, HOLDLOCK)
                WHERE OwnerUserId = @UserId AND IsActive = 1)
            BEGIN
                INSERT dbo.Channels (OwnerUserId, ChannelName, Handle)
                VALUES (@UserId, @Name, CONCAT(N'user-', CONVERT(nvarchar(36), NEWID())));
            END;
            """, connection, transaction);
        command.Add("@UserId", SqlDbType.BigInt, userId);
        command.Add("@Name", SqlDbType.NVarChar, name, 100);
        await command.ExecuteNonQueryAsync(ct);
    }

    private static async Task<string> CreateSessionAsync(SqlConnection connection, SqlTransaction transaction,
        long userId, int sessionDays, CancellationToken ct)
    {
        var token = NewToken();
        await using var command = new SqlCommand("""
            INSERT dbo.UserSessions (UserId, RefreshTokenHash, ExpiresAt)
            VALUES (@UserId, @Hash, DATEADD(day, @Days, SYSUTCDATETIME()));
            """, connection, transaction);
        command.Add("@UserId", SqlDbType.BigInt, userId);
        command.Add("@Hash", SqlDbType.Binary, HashToken(token), 32);
        command.Add("@Days", SqlDbType.Int, sessionDays);
        await command.ExecuteNonQueryAsync(ct);
        return token;
    }

    private static string NewToken() => Convert.ToBase64String(RandomNumberGenerator.GetBytes(32))
        .TrimEnd('=').Replace('+', '-').Replace('/', '_');
    private static byte[] HashToken(string token) => SHA256.HashData(Encoding.UTF8.GetBytes(token));
    private static string? ReadBearer(HttpRequest request)
    {
        var header = request.Headers.Authorization.ToString();
        return header.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase)
            ? header["Bearer ".Length..].Trim() : null;
    }
    private static bool ValidEmail(string? email) => !string.IsNullOrWhiteSpace(email)
        && email.Length <= 320 && System.Net.Mail.MailAddress.TryCreate(email.Trim(), out var parsed)
        && string.Equals(parsed.Address, email.Trim(), StringComparison.OrdinalIgnoreCase);
    private static bool ValidPassword(string? password) => password is not null && password.Length is >= 8 and <= 256;
}

public sealed record RegisterRequest(string? Email, string? Password, string? DisplayName);
public sealed record LoginRequest(string? Email, string? Password);
public sealed record PasswordResetRequest(string? Email);
public sealed record CompletePasswordResetRequest(string? Email, string? Token, string? NewPassword);
public sealed record UserDto(long UserId, string DisplayName, string Email, string? PhotoUrl);
public sealed record AuthResponse(string Token, UserDto User);
