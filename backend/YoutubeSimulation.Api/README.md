# YouTubeSimulation.Api

ASP.NET Core minimal API for the local YouTube simulation. It only uses the
SQL Server schema in `database/youtube_simulation_sqlserver_2022.sql`; uploaded
video bytes are stored locally, not sent to YouTube.

## Run and configure

Run the schema script once against an empty SQL Server database as directed in
that script. Do not rerun it against an initialized database. Configure the API
with environment variables (no credentials belong in appsettings or source):

```powershell
$env:ConnectionStrings__YoutubeSimulationDb = 'Server=localhost\SQL2022;Database=YoutubeSimulationDb;Integrated Security=True;Encrypt=True;TrustServerCertificate=True'
$env:Email__SmtpHost = 'smtp.example.com'
$env:Email__SmtpPort = '587'
$env:Email__SmtpUsername = 'your-smtp-username'
$env:Email__SmtpPassword = 'your-smtp-password'
$env:Email__FromAddress = 'noreply@example.com'
$env:Email__EnableSsl = 'true'
$env:Media__Root = 'D:\youtube-media'
$env:ASPNETCORE_URLS = 'http://0.0.0.0:5296'
dotnet run --no-launch-profile --project backend\YoutubeSimulation.Api
```

Password-reset email uses `Email:SmtpHost`, `Email:SmtpPort`,
`Email:SmtpUsername`, `Email:SmtpPassword`, `Email:FromAddress`, optional
`Email:FromName`, and `Email:EnableSsl`. Keep SMTP credentials in environment
variables or a secret store. Password reset returns a service-unavailable error
until valid SMTP settings are supplied. Reset tokens are random, stored only as
SHA-256 hashes, expire after 30 minutes, and are single-use; changing a password
revokes active sessions. SQL Server Integrated Security uses the Windows
identity running the API; grant that identity the minimum database permissions
it needs. SQL authentication may instead be supplied through
`ConnectionStrings__YoutubeSimulationDb` from a secret store/environment
variable. `Media__Root` defaults to the project `media` directory;
`Media__MaxUploadBytes` defaults to 2 GiB.

Uploaded video bytes are stored as files under `Media__Root` on the API server
(for example, `D:\youtube-media`). SQL Server stores video metadata and the
media storage key, not the video contents. Back up the media directory
separately from the database.

`GET /health/live` checks process liveness. `GET /health/ready` checks the
connection and required schema objects. For Android Emulator, use
`http://10.0.2.2:5296`; a physical Android device uses the computer's LAN IP,
for example `http://192.168.1.20:5296` (allow the port through the host
firewall). The API must listen on `0.0.0.0` for LAN access.

`GET /api/categories`, `GET /api/videos`, `GET /api/videos/{id}`,
`GET /api/videos/{id}/stream`, and `GET /api/videos/{id}/thumbnail` allow
anonymous access for public/unlisted content; an optional valid bearer adds
user-specific flags. Private content returns 404 unless the bearer belongs to
its owner or an active channel manager/editor. Other `/api` endpoints require
Send the session token in an `Authorization` header with the `Bearer` scheme.
Auth tokens are random opaque values; only
SHA-256 hashes are persisted in `dbo.UserSessions`. Passwords use PBKDF2
SHA-256 with a per-user random salt.

## Flutter-facing JSON/API contract

- `POST /api/auth/register` `{email,password,displayName}` and
  `POST /api/auth/login` `{email,password}` return
  `{token,user:{userId,displayName,email,photoUrl}}`.
- `POST /api/auth/password-reset/request` `{email}` emails a one-time reset
  token if the account exists; its response does not disclose account
  existence. `POST /api/auth/password-reset/complete`
  `{email,token,newPassword}` updates the password and revokes existing sessions.
  `POST /api/auth/logout` revokes the bearer token.
- `GET /api/account/me` returns `{user:{userId,displayName,email,photoUrl},
  theme,preferences:{themeMode}}`. `GET /api/account/me/theme` and
  `PUT /api/account/preferences` `{themeMode:"light"|"dark"|"system"}` sync
  the preference.
- `GET /api/categories` returns `{items:[{categoryId,categoryName}]}`.
  `GET /api/videos?category=&query=` returns `{items:[{videoId,title,channel,
  channelId,details,duration,durationSeconds,category,thumbnailUrl,visibility,
  isLiked,isSaved,isSubscribed}]}`. Category accepts an ID or exact name;
  search is parameterized and wildcard-escaped. `GET /api/videos/{id}` returns the
  same shape after visibility checks. Construct its playable URL as
  `/api/videos/{id}/stream` (byte ranges are enabled for seeking).
- `POST /api/videos/{id}/like` toggles; `PUT` likes and `DELETE` unlikes.
  `/api/videos/{id}/watch-later` and `/api/channels/{id}/subscription`
  support the same POST-toggle/PUT-on/DELETE-off pattern. The equivalent
  explicit subscription routes are `PUT|DELETE /api/subscriptions/{channelId}`.
- `GET /api/library/{liked|watch-later|history|subscriptions}` returns
  `{items:[video...]}`. `POST /api/videos/{id}/views` accepts
  `{watchedSeconds,completed,viewSessionId}` and records history.
- Registration and successful login ensure the account has an owned channel
  named after its display name, with an automatically generated unique handle.
  `POST /api/channels/mine` can create another channel using
  `{name,handle?,description}` (also accepts `channelName` for `name`).
  `GET /api/channels/manage` lists owned/manager channels and
  `GET /api/channels/mine/videos` lists videos the user can manage.
- `POST /api/channels/mine/videos` is multipart form data with `file`, `title`,
  optional `description`, `categoryId`, and `visibility`. Videos are stored
  under the configured local media directory. `PATCH` and `DELETE
  /api/channels/mine/videos/{id}` edit metadata and soft-delete owned/managed
  videos. `GET /api/videos/{id}/stream` serves local bytes with HTTP range
  support; `GET /api/videos/{id}/thumbnail` serves a stored local thumbnail or
  returns 404 if no thumbnail exists. Feed DTOs use the stable thumbnail URL
  only when a thumbnail key is present. Both media routes enforce the same
  video visibility/manager checks as video details.
- `GET /api/notifications` returns `{items:[...],unreadCount}`.
  `POST /api/notifications/{id}/read` marks the current user's notification
  read; `PATCH /api/notifications/read` marks all read.
- Comments: `GET|POST /api/videos/{id}/comments` (reply body includes
  `parentCommentId`), `PUT|DELETE /api/comments/{id}`,
  `POST|PUT|DELETE /api/comments/{id}/reaction`, and `POST /api/reports`.
  Report JSON has exactly one of `videoId`, `commentId`, or `channelId`, plus
  `reason` and optional `details`.

All SQL values are bound parameters; only allowlisted, fixed SQL fragments are
used for library selection. No real YouTube APIs are called.
