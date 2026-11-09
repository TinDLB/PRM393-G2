# YouTube-style simulation

Flutter web app for Chrome with an ASP.NET Core API and SQL Server 2022. The
app does not call YouTube APIs. Accounts, channels, video metadata, activity,
and preferences are stored in the project's SQL Server database. Uploaded
media is stored on the backend host's disk; the database stores its storage
key.

## Prepare SQL Server

In SQL Server Management Studio, run
[`database/youtube_simulation_sqlserver_2022.sql`](database/youtube_simulation_sqlserver_2022.sql)
once against the SQL Server instance. Do not run it again after it reports
success. The backend's Windows identity needs access to `YoutubeSimulationDb`.

## Run in Chrome

Open a PowerShell terminal in the project root and run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\run.ps1"
```

The script checks for Chrome, builds and starts the API if it is not already
ready, then runs the Flutter web app at `http://localhost:7357`. The steps are
sequential to avoid competing builds. It uses `localhost\SQL2022`,
`YoutubeSimulationDb`, and `D:\youtube-media` by default. When you quit Flutter,
the script stops only the API process it started.

The same app can be started from VS Code with the **Video Simulation - Chrome**
launch configuration, but the API must already be running. To run Flutter
directly, start the API separately and use:

```powershell
flutter run -d chrome --web-hostname=localhost --web-port=7357 --dart-define=API_BASE_URL=http://localhost:5296
```

The browser sends API requests to `http://localhost:5296`; local development
HTTP is allowed from localhost on any Flutter web port. Running
`flutter run -d chrome` by itself starts only the browser app, not the API; if
the API is not already running, the feed and account requests will fail. Use
`run.ps1` to start both. Do not expose this configuration to the public
internet. Configure HTTPS and production CORS origins before deployment.

The app's browser database uses SharedPreferences; the native SQLite store is
not used on web. Video uploads are sent to the API in sequential 4 MiB chunks,
so Chrome only buffers a small part of a selected video at a time. The API
assembles the file on disk and saves its metadata in SQL Server.

### Upload videos from `D:\Video`

Sign in to the account that should own the upload, open **Quản lý kênh**, and
choose **Chọn tệp video**. Select a video from `D:\Video`; uploads are sent in
sequential 4 MiB chunks and saved under the currently signed-in account. Repeat
with other accounts to distribute videos among them. The original files in
`D:\Video` are not modified.

Account creation and login use email and password. Password reset sends a
single-use token to that email; it expires after 30 minutes. SMTP must be
configured for reset emails to be delivered. Supply `Email__SmtpHost`,
`Email__SmtpPort`, `Email__SmtpUsername`, `Email__SmtpPassword`,
`Email__FromAddress`, and `Email__EnableSsl` through environment variables or a
secret store; do not commit credentials.

Check backend readiness at `http://localhost:5296/health/ready`. More API and
configuration details are in
[`backend/YoutubeSimulation.Api/README.md`](backend/YoutubeSimulation.Api/README.md).

## Features

- Email/password registration and login, with one-time email password reset.
- Public video feed, category/search, browser video playback, and video upload
  to the backend.
- Per-account likes, watch-later, subscriptions, viewing history, and
  notifications.
- Create/manage channels and upload, edit, or delete videos without sending
  media or metadata to YouTube.
- Account-synced light/dark theme.

## Current limitations

- The database starts with categories but no demo accounts or videos. The feed
  stays empty until users upload public videos. Only videos marked `public`
  and ready for playback appear in the home feed.
- Password reset email requires valid SMTP settings on the backend. Login and
  registration work without SMTP configuration.
- The backend has comment/reply/reaction and report endpoints, but the Flutter
  app does not yet expose those controls. Playlists and moderation workflows
  are also not wired to the app or implemented as API routes.
- Upload stores the original video but does not generate a thumbnail or extract
  its duration; videos without metadata can show a generic thumbnail and
  `0:00` duration.
