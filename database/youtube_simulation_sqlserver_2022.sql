/*
  YouTube-style simulation database for SQL Server 2022.

  Covers account/password/Google identity, sessions, user preferences, channels
  and staff roles, video metadata/uploads/assets/search, categories/tags,
  video playback/reactions, subscriptions, watch history/later, playlists,
  threaded comments/reactions, notifications, reports and moderation.

  Run this script in SQL Server Management Studio (SSMS) while connected to
  the SQL Server instance. It creates YoutubeSimulationDb if needed and
  initializes its tables. Run it only once against an empty database.

  The application must access this database through a trusted backend API.
  Never connect a Flutter/browser/mobile client directly to SQL Server.
  Store video bytes in file/object storage; MediaStorageKey and
  ThumbnailStorageKey hold their backend-managed locations.
*/

IF DB_ID(N'YoutubeSimulationDb') IS NULL
BEGIN
    CREATE DATABASE [YoutubeSimulationDb];
END;
GO

USE [YoutubeSimulationDb];
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
GO

ALTER DATABASE [YoutubeSimulationDb] SET COMPATIBILITY_LEVEL = 160;
GO

IF OBJECT_ID(N'dbo.Users', N'U') IS NOT NULL
BEGIN
    THROW 51000, 'YoutubeSimulationDb is already initialized. No tables were changed.', 1;
END;
GO

CREATE TABLE dbo.Users
(
    UserId              BIGINT IDENTITY(1,1) NOT NULL,
    Email               NVARCHAR(320) NOT NULL,
    EmailNormalized     AS LOWER(LTRIM(RTRIM(Email))) PERSISTED,
    DisplayName         NVARCHAR(100) NOT NULL,
    AvatarUrl           NVARCHAR(2048) NULL,
    IsActive            BIT NOT NULL CONSTRAINT DF_Users_IsActive DEFAULT (1),
    CreatedAt           DATETIME2(3) NOT NULL CONSTRAINT DF_Users_CreatedAt DEFAULT (SYSUTCDATETIME()),
    UpdatedAt           DATETIME2(3) NOT NULL CONSTRAINT DF_Users_UpdatedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT PK_Users PRIMARY KEY CLUSTERED (UserId),
    CONSTRAINT CK_Users_Email_NotBlank CHECK (LEN(LTRIM(RTRIM(Email))) > 0),
    CONSTRAINT CK_Users_DisplayName_NotBlank CHECK (LEN(LTRIM(RTRIM(DisplayName))) > 0)
);
GO

CREATE UNIQUE INDEX UX_Users_EmailNormalized ON dbo.Users (EmailNormalized);
GO

CREATE TABLE dbo.PasswordCredentials
(
    UserId              BIGINT NOT NULL,
    PasswordHash        VARBINARY(64) NOT NULL,
    PasswordSalt        VARBINARY(32) NOT NULL,
    HashAlgorithm       VARCHAR(32) NOT NULL,
    WorkFactor          INT NOT NULL,
    ChangedAt           DATETIME2(3) NOT NULL CONSTRAINT DF_PasswordCredentials_ChangedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT PK_PasswordCredentials PRIMARY KEY CLUSTERED (UserId),
    CONSTRAINT FK_PasswordCredentials_Users FOREIGN KEY (UserId) REFERENCES dbo.Users (UserId),
    CONSTRAINT CK_PasswordCredentials_HashLength CHECK (DATALENGTH(PasswordHash) >= 32),
    CONSTRAINT CK_PasswordCredentials_SaltLength CHECK (DATALENGTH(PasswordSalt) >= 16),
    CONSTRAINT CK_PasswordCredentials_WorkFactor CHECK (WorkFactor > 0)
);
GO

CREATE TABLE dbo.ExternalLogins
(
    ExternalLoginId     BIGINT IDENTITY(1,1) NOT NULL,
    UserId              BIGINT NOT NULL,
    Provider            VARCHAR(30) NOT NULL,
    ProviderSubject     NVARCHAR(255) NOT NULL,
    ProviderEmail       NVARCHAR(320) NULL,
    CreatedAt           DATETIME2(3) NOT NULL CONSTRAINT DF_ExternalLogins_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT PK_ExternalLogins PRIMARY KEY CLUSTERED (ExternalLoginId),
    CONSTRAINT FK_ExternalLogins_Users FOREIGN KEY (UserId) REFERENCES dbo.Users (UserId),
    CONSTRAINT CK_ExternalLogins_Provider CHECK (Provider IN ('GOOGLE')),
    CONSTRAINT CK_ExternalLogins_Subject_NotBlank CHECK (LEN(LTRIM(RTRIM(ProviderSubject))) > 0)
);
GO

CREATE UNIQUE INDEX UX_ExternalLogins_ProviderSubject
    ON dbo.ExternalLogins (Provider, ProviderSubject);
CREATE INDEX IX_ExternalLogins_UserId ON dbo.ExternalLogins (UserId);
GO

CREATE TABLE dbo.UserAuthTokens
(
    AuthTokenId         BIGINT IDENTITY(1,1) NOT NULL,
    UserId              BIGINT NOT NULL,
    Purpose             VARCHAR(30) NOT NULL,
    TokenHash           BINARY(32) NOT NULL,
    ExpiresAt           DATETIME2(3) NOT NULL,
    ConsumedAt          DATETIME2(3) NULL,
    CreatedAt           DATETIME2(3) NOT NULL CONSTRAINT DF_UserAuthTokens_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT PK_UserAuthTokens PRIMARY KEY CLUSTERED (AuthTokenId),
    CONSTRAINT FK_UserAuthTokens_Users FOREIGN KEY (UserId) REFERENCES dbo.Users (UserId),
    CONSTRAINT CK_UserAuthTokens_Purpose CHECK (Purpose IN ('EMAIL_VERIFICATION', 'PASSWORD_RESET'))
);
GO

CREATE UNIQUE INDEX UX_UserAuthTokens_TokenHash ON dbo.UserAuthTokens (TokenHash);
CREATE INDEX IX_UserAuthTokens_User_Purpose_Expiry
    ON dbo.UserAuthTokens (UserId, Purpose, ExpiresAt)
    INCLUDE (ConsumedAt);
GO

CREATE TABLE dbo.UserSessions
(
    UserSessionId       BIGINT IDENTITY(1,1) NOT NULL,
    UserId              BIGINT NOT NULL,
    RefreshTokenHash    BINARY(32) NOT NULL,
    ExpiresAt           DATETIME2(3) NOT NULL,
    RevokedAt           DATETIME2(3) NULL,
    LastSeenAt          DATETIME2(3) NOT NULL CONSTRAINT DF_UserSessions_LastSeenAt DEFAULT (SYSUTCDATETIME()),
    CreatedAt           DATETIME2(3) NOT NULL CONSTRAINT DF_UserSessions_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT PK_UserSessions PRIMARY KEY CLUSTERED (UserSessionId),
    CONSTRAINT FK_UserSessions_Users FOREIGN KEY (UserId) REFERENCES dbo.Users (UserId)
);
GO

CREATE UNIQUE INDEX UX_UserSessions_RefreshTokenHash ON dbo.UserSessions (RefreshTokenHash);
CREATE INDEX IX_UserSessions_User_Expiry ON dbo.UserSessions (UserId, ExpiresAt, RevokedAt);
GO

CREATE TABLE dbo.UserPreferences
(
    UserId              BIGINT NOT NULL,
    ThemeMode           VARCHAR(10) NOT NULL CONSTRAINT DF_UserPreferences_ThemeMode DEFAULT ('system'),
    LanguageCode        VARCHAR(10) NOT NULL CONSTRAINT DF_UserPreferences_LanguageCode DEFAULT ('vi'),
    UpdatedAt           DATETIME2(3) NOT NULL CONSTRAINT DF_UserPreferences_UpdatedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT PK_UserPreferences PRIMARY KEY CLUSTERED (UserId),
    CONSTRAINT FK_UserPreferences_Users FOREIGN KEY (UserId) REFERENCES dbo.Users (UserId),
    CONSTRAINT CK_UserPreferences_ThemeMode CHECK (ThemeMode IN ('system', 'light', 'dark'))
);
GO

CREATE TABLE dbo.Channels
(
    ChannelId           BIGINT IDENTITY(1,1) NOT NULL,
    OwnerUserId         BIGINT NOT NULL,
    ChannelName         NVARCHAR(100) NOT NULL,
    Handle              NVARCHAR(60) NOT NULL,
    Description         NVARCHAR(2000) NOT NULL CONSTRAINT DF_Channels_Description DEFAULT (N''),
    AvatarStorageKey    NVARCHAR(1024) NULL,
    BannerStorageKey    NVARCHAR(1024) NULL,
    IsActive            BIT NOT NULL CONSTRAINT DF_Channels_IsActive DEFAULT (1),
    CreatedAt           DATETIME2(3) NOT NULL CONSTRAINT DF_Channels_CreatedAt DEFAULT (SYSUTCDATETIME()),
    UpdatedAt           DATETIME2(3) NOT NULL CONSTRAINT DF_Channels_UpdatedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT PK_Channels PRIMARY KEY CLUSTERED (ChannelId),
    CONSTRAINT FK_Channels_Users FOREIGN KEY (OwnerUserId) REFERENCES dbo.Users (UserId),
    CONSTRAINT CK_Channels_Name_NotBlank CHECK (LEN(LTRIM(RTRIM(ChannelName))) > 0),
    CONSTRAINT CK_Channels_Handle_NotBlank CHECK (LEN(LTRIM(RTRIM(Handle))) > 0)
);
GO

CREATE UNIQUE INDEX UX_Channels_Handle ON dbo.Channels (Handle);
CREATE INDEX IX_Channels_OwnerUserId ON dbo.Channels (OwnerUserId, IsActive);
GO

CREATE TABLE dbo.ChannelMembers
(
    ChannelId           BIGINT NOT NULL,
    UserId              BIGINT NOT NULL,
    MemberRole          VARCHAR(12) NOT NULL,
    MembershipStatus    VARCHAR(10) NOT NULL CONSTRAINT DF_ChannelMembers_Status DEFAULT ('active'),
    InvitedByUserId     BIGINT NULL,
    CreatedAt           DATETIME2(3) NOT NULL CONSTRAINT DF_ChannelMembers_CreatedAt DEFAULT (SYSUTCDATETIME()),
    UpdatedAt           DATETIME2(3) NOT NULL CONSTRAINT DF_ChannelMembers_UpdatedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT PK_ChannelMembers PRIMARY KEY CLUSTERED (ChannelId, UserId),
    CONSTRAINT FK_ChannelMembers_Channels FOREIGN KEY (ChannelId) REFERENCES dbo.Channels (ChannelId),
    CONSTRAINT FK_ChannelMembers_Users FOREIGN KEY (UserId) REFERENCES dbo.Users (UserId),
    CONSTRAINT FK_ChannelMembers_InvitedBy FOREIGN KEY (InvitedByUserId) REFERENCES dbo.Users (UserId),
    CONSTRAINT CK_ChannelMembers_Role CHECK (MemberRole IN ('manager', 'editor', 'viewer')),
    CONSTRAINT CK_ChannelMembers_Status CHECK (MembershipStatus IN ('invited', 'active', 'revoked'))
);
GO

CREATE INDEX IX_ChannelMembers_User_Status
    ON dbo.ChannelMembers (UserId, MembershipStatus, ChannelId);
GO

CREATE TABLE dbo.VideoCategories
(
    CategoryId          INT IDENTITY(1,1) NOT NULL,
    CategoryName        NVARCHAR(80) NOT NULL,
    DisplayOrder        INT NOT NULL CONSTRAINT DF_VideoCategories_DisplayOrder DEFAULT (0),
    IsActive            BIT NOT NULL CONSTRAINT DF_VideoCategories_IsActive DEFAULT (1),
    CONSTRAINT PK_VideoCategories PRIMARY KEY CLUSTERED (CategoryId),
    CONSTRAINT UQ_VideoCategories_CategoryName UNIQUE (CategoryName),
    CONSTRAINT CK_VideoCategories_Name_NotBlank CHECK (LEN(LTRIM(RTRIM(CategoryName))) > 0)
);
GO

CREATE TABLE dbo.Videos
(
    VideoId             BIGINT IDENTITY(1,1) NOT NULL,
    ChannelId           BIGINT NOT NULL,
    CategoryId          INT NULL,
    Title               NVARCHAR(200) NOT NULL,
    Description         NVARCHAR(MAX) NOT NULL CONSTRAINT DF_Videos_Description DEFAULT (N''),
    MediaStorageKey     NVARCHAR(1024) NULL,
    ThumbnailStorageKey NVARCHAR(1024) NULL,
    SourceFileName      NVARCHAR(260) NULL,
    MediaType           VARCHAR(100) NULL,
    MediaSizeBytes      BIGINT NULL,
    DurationSeconds     INT NOT NULL CONSTRAINT DF_Videos_DurationSeconds DEFAULT (0),
    Visibility          VARCHAR(12) NOT NULL CONSTRAINT DF_Videos_Visibility DEFAULT ('public'),
    VideoStatus         VARCHAR(12) NOT NULL CONSTRAINT DF_Videos_VideoStatus DEFAULT ('draft'),
    CommentsEnabled     BIT NOT NULL CONSTRAINT DF_Videos_CommentsEnabled DEFAULT (1),
    AllowEmbedding      BIT NOT NULL CONSTRAINT DF_Videos_AllowEmbedding DEFAULT (1),
    IsShort             BIT NOT NULL CONSTRAINT DF_Videos_IsShort DEFAULT (0),
    AgeRestriction      TINYINT NOT NULL CONSTRAINT DF_Videos_AgeRestriction DEFAULT (0),
    ViewCount           BIGINT NOT NULL CONSTRAINT DF_Videos_ViewCount DEFAULT (0),
    PublishedAt         DATETIME2(3) NULL,
    CreatedAt           DATETIME2(3) NOT NULL CONSTRAINT DF_Videos_CreatedAt DEFAULT (SYSUTCDATETIME()),
    UpdatedAt           DATETIME2(3) NOT NULL CONSTRAINT DF_Videos_UpdatedAt DEFAULT (SYSUTCDATETIME()),
    DeletedAt           DATETIME2(3) NULL,
    CONSTRAINT PK_Videos PRIMARY KEY CLUSTERED (VideoId),
    CONSTRAINT UQ_Videos_Video_Channel UNIQUE (VideoId, ChannelId),
    CONSTRAINT FK_Videos_Channels FOREIGN KEY (ChannelId) REFERENCES dbo.Channels (ChannelId),
    CONSTRAINT FK_Videos_VideoCategories FOREIGN KEY (CategoryId) REFERENCES dbo.VideoCategories (CategoryId),
    CONSTRAINT CK_Videos_Title_NotBlank CHECK (LEN(LTRIM(RTRIM(Title))) > 0),
    CONSTRAINT CK_Videos_MediaSize CHECK (MediaSizeBytes IS NULL OR MediaSizeBytes >= 0),
    CONSTRAINT CK_Videos_Duration CHECK (DurationSeconds >= 0),
    CONSTRAINT CK_Videos_ViewCount CHECK (ViewCount >= 0),
    CONSTRAINT CK_Videos_Visibility CHECK (Visibility IN ('public', 'unlisted', 'private')),
    CONSTRAINT CK_Videos_Status CHECK (VideoStatus IN ('draft', 'processing', 'ready', 'failed')),
    CONSTRAINT CK_Videos_AgeRestriction CHECK (AgeRestriction IN (0, 13, 18))
);
GO

CREATE INDEX IX_Videos_PublicFeed
    ON dbo.Videos (Visibility, VideoStatus, DeletedAt, PublishedAt DESC)
    INCLUDE (ChannelId, CategoryId, Title, ThumbnailStorageKey, DurationSeconds, ViewCount);
CREATE INDEX IX_Videos_Channel_Published
    ON dbo.Videos (ChannelId, DeletedAt, CreatedAt DESC);
CREATE INDEX IX_Videos_Category_Published
    ON dbo.Videos (CategoryId, Visibility, VideoStatus, PublishedAt DESC)
    INCLUDE (ChannelId, Title, ThumbnailStorageKey, DurationSeconds, ViewCount);
GO

IF FULLTEXTSERVICEPROPERTY('IsFullTextInstalled') = 1
BEGIN
    IF NOT EXISTS (SELECT 1 FROM sys.fulltext_catalogs WHERE name = N'VideoSearchCatalog')
        CREATE FULLTEXT CATALOG VideoSearchCatalog AS DEFAULT;

    IF NOT EXISTS (SELECT 1 FROM sys.fulltext_indexes WHERE object_id = OBJECT_ID(N'dbo.Videos'))
    BEGIN
        CREATE FULLTEXT INDEX ON dbo.Videos
        (
            Title LANGUAGE 1066,
            Description LANGUAGE 1066
        )
        KEY INDEX PK_Videos
        WITH CHANGE_TRACKING AUTO;
    END;
END
ELSE
BEGIN
    PRINT N'Full-text search is not installed; use parameterized LIKE queries until it is enabled.';
END;
GO

CREATE TABLE dbo.VideoUploadSessions
(
    UploadSessionId     UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_VideoUploadSessions_Id DEFAULT (NEWSEQUENTIALID()),
    VideoId             BIGINT NOT NULL,
    ChannelId           BIGINT NOT NULL,
    CreatedByUserId     BIGINT NOT NULL,
    UploadStatus        VARCHAR(12) NOT NULL CONSTRAINT DF_VideoUploadSessions_Status DEFAULT ('pending'),
    TotalBytes          BIGINT NULL,
    UploadedBytes       BIGINT NOT NULL CONSTRAINT DF_VideoUploadSessions_UploadedBytes DEFAULT (0),
    LastError           NVARCHAR(1000) NULL,
    StartedAt           DATETIME2(3) NULL,
    CompletedAt         DATETIME2(3) NULL,
    CreatedAt           DATETIME2(3) NOT NULL CONSTRAINT DF_VideoUploadSessions_CreatedAt DEFAULT (SYSUTCDATETIME()),
    UpdatedAt           DATETIME2(3) NOT NULL CONSTRAINT DF_VideoUploadSessions_UpdatedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT PK_VideoUploadSessions PRIMARY KEY CLUSTERED (UploadSessionId),
    CONSTRAINT FK_VideoUploadSessions_VideoChannel
        FOREIGN KEY (VideoId, ChannelId) REFERENCES dbo.Videos (VideoId, ChannelId),
    CONSTRAINT FK_VideoUploadSessions_Users FOREIGN KEY (CreatedByUserId) REFERENCES dbo.Users (UserId),
    CONSTRAINT CK_VideoUploadSessions_Status CHECK (UploadStatus IN ('pending', 'uploading', 'processing', 'completed', 'failed', 'cancelled')),
    CONSTRAINT CK_VideoUploadSessions_Bytes CHECK (UploadedBytes >= 0 AND (TotalBytes IS NULL OR TotalBytes >= UploadedBytes))
);
GO

CREATE INDEX IX_VideoUploadSessions_Channel_CreatedAt
    ON dbo.VideoUploadSessions (ChannelId, CreatedAt DESC)
    INCLUDE (VideoId, CreatedByUserId, UploadStatus, UploadedBytes, TotalBytes);
GO

CREATE TABLE dbo.VideoAssets
(
    VideoAssetId        BIGINT IDENTITY(1,1) NOT NULL,
    VideoId             BIGINT NOT NULL,
    AssetType           VARCHAR(12) NOT NULL,
    StorageKey          NVARCHAR(1024) NOT NULL,
    LanguageCode        VARCHAR(10) NULL,
    MimeType            VARCHAR(100) NULL,
    FileSizeBytes       BIGINT NULL,
    WidthPixels         INT NULL,
    HeightPixels        INT NULL,
    CreatedAt           DATETIME2(3) NOT NULL CONSTRAINT DF_VideoAssets_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT PK_VideoAssets PRIMARY KEY CLUSTERED (VideoAssetId),
    CONSTRAINT FK_VideoAssets_Videos FOREIGN KEY (VideoId) REFERENCES dbo.Videos (VideoId),
    CONSTRAINT CK_VideoAssets_Type CHECK (AssetType IN ('thumbnail', 'caption', 'subtitle', 'transcode')),
    CONSTRAINT CK_VideoAssets_StorageKey_NotBlank CHECK (LEN(LTRIM(RTRIM(StorageKey))) > 0),
    CONSTRAINT CK_VideoAssets_FileSize CHECK (FileSizeBytes IS NULL OR FileSizeBytes >= 0),
    CONSTRAINT CK_VideoAssets_Dimensions CHECK (
        (WidthPixels IS NULL OR WidthPixels > 0) AND (HeightPixels IS NULL OR HeightPixels > 0)
    )
);
GO

CREATE INDEX IX_VideoAssets_Video_Type ON dbo.VideoAssets (VideoId, AssetType);
GO

CREATE TABLE dbo.Tags
(
    TagId               BIGINT IDENTITY(1,1) NOT NULL,
    TagName             NVARCHAR(50) NOT NULL,
    CreatedAt           DATETIME2(3) NOT NULL CONSTRAINT DF_Tags_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT PK_Tags PRIMARY KEY CLUSTERED (TagId),
    CONSTRAINT UQ_Tags_TagName UNIQUE (TagName),
    CONSTRAINT CK_Tags_Name_NotBlank CHECK (LEN(LTRIM(RTRIM(TagName))) > 0)
);
GO

CREATE TABLE dbo.VideoTags
(
    VideoId             BIGINT NOT NULL,
    TagId               BIGINT NOT NULL,
    CONSTRAINT PK_VideoTags PRIMARY KEY CLUSTERED (VideoId, TagId),
    CONSTRAINT FK_VideoTags_Videos FOREIGN KEY (VideoId) REFERENCES dbo.Videos (VideoId),
    CONSTRAINT FK_VideoTags_Tags FOREIGN KEY (TagId) REFERENCES dbo.Tags (TagId)
);
GO

CREATE INDEX IX_VideoTags_TagId ON dbo.VideoTags (TagId, VideoId);
GO

CREATE TABLE dbo.VideoReactions
(
    UserId              BIGINT NOT NULL,
    VideoId             BIGINT NOT NULL,
    ReactionType        VARCHAR(8) NOT NULL,
    ReactedAt           DATETIME2(3) NOT NULL CONSTRAINT DF_VideoReactions_ReactedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT PK_VideoReactions PRIMARY KEY CLUSTERED (UserId, VideoId),
    CONSTRAINT FK_VideoReactions_Users FOREIGN KEY (UserId) REFERENCES dbo.Users (UserId),
    CONSTRAINT FK_VideoReactions_Videos FOREIGN KEY (VideoId) REFERENCES dbo.Videos (VideoId),
    CONSTRAINT CK_VideoReactions_Type CHECK (ReactionType IN ('like', 'dislike'))
);
GO

CREATE INDEX IX_VideoReactions_Video_Type
    ON dbo.VideoReactions (VideoId, ReactionType, ReactedAt DESC);
GO

CREATE TABLE dbo.ChannelSubscriptions
(
    SubscriberUserId    BIGINT NOT NULL,
    ChannelId           BIGINT NOT NULL,
    SubscribedAt        DATETIME2(3) NOT NULL CONSTRAINT DF_ChannelSubscriptions_SubscribedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT PK_ChannelSubscriptions PRIMARY KEY CLUSTERED (SubscriberUserId, ChannelId),
    CONSTRAINT FK_ChannelSubscriptions_Users FOREIGN KEY (SubscriberUserId) REFERENCES dbo.Users (UserId),
    CONSTRAINT FK_ChannelSubscriptions_Channels FOREIGN KEY (ChannelId) REFERENCES dbo.Channels (ChannelId)
);
GO

CREATE INDEX IX_ChannelSubscriptions_ChannelId
    ON dbo.ChannelSubscriptions (ChannelId, SubscribedAt DESC);
GO

CREATE TABLE dbo.WatchHistory
(
    WatchHistoryId      BIGINT IDENTITY(1,1) NOT NULL,
    UserId              BIGINT NOT NULL,
    VideoId             BIGINT NOT NULL,
    WatchedAt           DATETIME2(3) NOT NULL CONSTRAINT DF_WatchHistory_WatchedAt DEFAULT (SYSUTCDATETIME()),
    WatchDurationSeconds INT NOT NULL CONSTRAINT DF_WatchHistory_WatchDuration DEFAULT (0),
    LastPositionSeconds INT NOT NULL CONSTRAINT DF_WatchHistory_LastPosition DEFAULT (0),
    CONSTRAINT PK_WatchHistory PRIMARY KEY CLUSTERED (WatchHistoryId),
    CONSTRAINT FK_WatchHistory_Users FOREIGN KEY (UserId) REFERENCES dbo.Users (UserId),
    CONSTRAINT FK_WatchHistory_Videos FOREIGN KEY (VideoId) REFERENCES dbo.Videos (VideoId),
    CONSTRAINT CK_WatchHistory_Duration CHECK (WatchDurationSeconds >= 0),
    CONSTRAINT CK_WatchHistory_Position CHECK (LastPositionSeconds >= 0)
);
GO

CREATE INDEX IX_WatchHistory_User_WatchedAt
    ON dbo.WatchHistory (UserId, WatchedAt DESC)
    INCLUDE (VideoId, WatchDurationSeconds, LastPositionSeconds);
CREATE INDEX IX_WatchHistory_VideoId ON dbo.WatchHistory (VideoId, WatchedAt DESC);
GO

CREATE TABLE dbo.WatchLater
(
    UserId              BIGINT NOT NULL,
    VideoId             BIGINT NOT NULL,
    AddedAt             DATETIME2(3) NOT NULL CONSTRAINT DF_WatchLater_AddedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT PK_WatchLater PRIMARY KEY CLUSTERED (UserId, VideoId),
    CONSTRAINT FK_WatchLater_Users FOREIGN KEY (UserId) REFERENCES dbo.Users (UserId),
    CONSTRAINT FK_WatchLater_Videos FOREIGN KEY (VideoId) REFERENCES dbo.Videos (VideoId)
);
GO

CREATE INDEX IX_WatchLater_VideoId ON dbo.WatchLater (VideoId);
GO

CREATE TABLE dbo.Playlists
(
    PlaylistId          BIGINT IDENTITY(1,1) NOT NULL,
    OwnerUserId         BIGINT NOT NULL,
    PlaylistName        NVARCHAR(120) NOT NULL,
    Description         NVARCHAR(2000) NOT NULL CONSTRAINT DF_Playlists_Description DEFAULT (N''),
    Visibility          VARCHAR(12) NOT NULL CONSTRAINT DF_Playlists_Visibility DEFAULT ('private'),
    CreatedAt           DATETIME2(3) NOT NULL CONSTRAINT DF_Playlists_CreatedAt DEFAULT (SYSUTCDATETIME()),
    UpdatedAt           DATETIME2(3) NOT NULL CONSTRAINT DF_Playlists_UpdatedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT PK_Playlists PRIMARY KEY CLUSTERED (PlaylistId),
    CONSTRAINT FK_Playlists_Users FOREIGN KEY (OwnerUserId) REFERENCES dbo.Users (UserId),
    CONSTRAINT CK_Playlists_Name_NotBlank CHECK (LEN(LTRIM(RTRIM(PlaylistName))) > 0),
    CONSTRAINT CK_Playlists_Visibility CHECK (Visibility IN ('public', 'unlisted', 'private'))
);
GO

CREATE INDEX IX_Playlists_Owner_CreatedAt
    ON dbo.Playlists (OwnerUserId, CreatedAt DESC);
GO

CREATE TABLE dbo.PlaylistVideos
(
    PlaylistId          BIGINT NOT NULL,
    VideoId             BIGINT NOT NULL,
    Position            INT NOT NULL,
    AddedAt             DATETIME2(3) NOT NULL CONSTRAINT DF_PlaylistVideos_AddedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT PK_PlaylistVideos PRIMARY KEY CLUSTERED (PlaylistId, VideoId),
    CONSTRAINT FK_PlaylistVideos_Playlists FOREIGN KEY (PlaylistId) REFERENCES dbo.Playlists (PlaylistId),
    CONSTRAINT FK_PlaylistVideos_Videos FOREIGN KEY (VideoId) REFERENCES dbo.Videos (VideoId),
    CONSTRAINT CK_PlaylistVideos_Position CHECK (Position >= 0)
);
GO

CREATE UNIQUE INDEX UX_PlaylistVideos_Position
    ON dbo.PlaylistVideos (PlaylistId, Position);
CREATE INDEX IX_PlaylistVideos_VideoId ON dbo.PlaylistVideos (VideoId, PlaylistId);
GO

CREATE TABLE dbo.VideoComments
(
    CommentId           BIGINT IDENTITY(1,1) NOT NULL,
    VideoId             BIGINT NOT NULL,
    UserId              BIGINT NOT NULL,
    ParentCommentId     BIGINT NULL,
    CommentText         NVARCHAR(2000) NOT NULL,
    CommentStatus       VARCHAR(10) NOT NULL CONSTRAINT DF_VideoComments_Status DEFAULT ('active'),
    CreatedAt           DATETIME2(3) NOT NULL CONSTRAINT DF_VideoComments_CreatedAt DEFAULT (SYSUTCDATETIME()),
    UpdatedAt           DATETIME2(3) NOT NULL CONSTRAINT DF_VideoComments_UpdatedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT PK_VideoComments PRIMARY KEY CLUSTERED (CommentId),
    CONSTRAINT UQ_VideoComments_CommentVideo UNIQUE (CommentId, VideoId),
    CONSTRAINT FK_VideoComments_Videos FOREIGN KEY (VideoId) REFERENCES dbo.Videos (VideoId),
    CONSTRAINT FK_VideoComments_Users FOREIGN KEY (UserId) REFERENCES dbo.Users (UserId),
    CONSTRAINT FK_VideoComments_ParentInSameVideo
        FOREIGN KEY (ParentCommentId, VideoId)
        REFERENCES dbo.VideoComments (CommentId, VideoId),
    CONSTRAINT CK_VideoComments_Text_NotBlank CHECK (LEN(LTRIM(RTRIM(CommentText))) > 0),
    CONSTRAINT CK_VideoComments_Status CHECK (CommentStatus IN ('active', 'hidden', 'deleted'))
);
GO

CREATE INDEX IX_VideoComments_Video_CreatedAt
    ON dbo.VideoComments (VideoId, CommentStatus, CreatedAt DESC)
    INCLUDE (UserId, ParentCommentId);
CREATE INDEX IX_VideoComments_User_CreatedAt
    ON dbo.VideoComments (UserId, CreatedAt DESC);
GO

CREATE TABLE dbo.CommentReactions
(
    UserId              BIGINT NOT NULL,
    CommentId           BIGINT NOT NULL,
    ReactionType        VARCHAR(8) NOT NULL,
    ReactedAt           DATETIME2(3) NOT NULL CONSTRAINT DF_CommentReactions_ReactedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT PK_CommentReactions PRIMARY KEY CLUSTERED (UserId, CommentId),
    CONSTRAINT FK_CommentReactions_Users FOREIGN KEY (UserId) REFERENCES dbo.Users (UserId),
    CONSTRAINT FK_CommentReactions_Comments FOREIGN KEY (CommentId) REFERENCES dbo.VideoComments (CommentId),
    CONSTRAINT CK_CommentReactions_Type CHECK (ReactionType IN ('like', 'dislike'))
);
GO

CREATE INDEX IX_CommentReactions_Comment_Type
    ON dbo.CommentReactions (CommentId, ReactionType, ReactedAt DESC);
GO

CREATE TABLE dbo.VideoViews
(
    VideoViewId         BIGINT IDENTITY(1,1) NOT NULL,
    VideoId             BIGINT NOT NULL,
    UserId              BIGINT NULL,
    ViewSessionId       UNIQUEIDENTIFIER NOT NULL,
    WatchedSeconds      INT NOT NULL CONSTRAINT DF_VideoViews_WatchedSeconds DEFAULT (0),
    Completed           BIT NOT NULL CONSTRAINT DF_VideoViews_Completed DEFAULT (0),
    ViewedAt            DATETIME2(3) NOT NULL CONSTRAINT DF_VideoViews_ViewedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT PK_VideoViews PRIMARY KEY CLUSTERED (VideoViewId),
    CONSTRAINT FK_VideoViews_Videos FOREIGN KEY (VideoId) REFERENCES dbo.Videos (VideoId),
    CONSTRAINT FK_VideoViews_Users FOREIGN KEY (UserId) REFERENCES dbo.Users (UserId),
    CONSTRAINT UQ_VideoViews_Session UNIQUE (VideoId, ViewSessionId),
    CONSTRAINT CK_VideoViews_WatchedSeconds CHECK (WatchedSeconds >= 0)
);
GO

CREATE INDEX IX_VideoViews_Video_ViewedAt
    ON dbo.VideoViews (VideoId, ViewedAt DESC)
    INCLUDE (UserId, WatchedSeconds, Completed);
CREATE INDEX IX_VideoViews_User_ViewedAt
    ON dbo.VideoViews (UserId, ViewedAt DESC)
    INCLUDE (VideoId, WatchedSeconds, Completed);
GO

CREATE TABLE dbo.ContentReports
(
    ContentReportId     BIGINT IDENTITY(1,1) NOT NULL,
    ReporterUserId      BIGINT NOT NULL,
    VideoId             BIGINT NULL,
    CommentId           BIGINT NULL,
    ChannelId           BIGINT NULL,
    Reason              VARCHAR(24) NOT NULL,
    Details             NVARCHAR(2000) NULL,
    ReportStatus        VARCHAR(12) NOT NULL CONSTRAINT DF_ContentReports_Status DEFAULT ('open'),
    ReviewedByUserId    BIGINT NULL,
    ReviewedAt          DATETIME2(3) NULL,
    CreatedAt           DATETIME2(3) NOT NULL CONSTRAINT DF_ContentReports_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT PK_ContentReports PRIMARY KEY CLUSTERED (ContentReportId),
    CONSTRAINT FK_ContentReports_Reporter FOREIGN KEY (ReporterUserId) REFERENCES dbo.Users (UserId),
    CONSTRAINT FK_ContentReports_Reviewer FOREIGN KEY (ReviewedByUserId) REFERENCES dbo.Users (UserId),
    CONSTRAINT FK_ContentReports_Videos FOREIGN KEY (VideoId) REFERENCES dbo.Videos (VideoId),
    CONSTRAINT FK_ContentReports_Comments FOREIGN KEY (CommentId) REFERENCES dbo.VideoComments (CommentId),
    CONSTRAINT FK_ContentReports_Channels FOREIGN KEY (ChannelId) REFERENCES dbo.Channels (ChannelId),
    CONSTRAINT CK_ContentReports_OneTarget CHECK (
        (CASE WHEN VideoId IS NULL THEN 0 ELSE 1 END) +
        (CASE WHEN CommentId IS NULL THEN 0 ELSE 1 END) +
        (CASE WHEN ChannelId IS NULL THEN 0 ELSE 1 END) = 1
    ),
    CONSTRAINT CK_ContentReports_Reason CHECK (Reason IN ('spam', 'harassment', 'hate', 'violence', 'sexual', 'misinformation', 'copyright', 'other')),
    CONSTRAINT CK_ContentReports_Status CHECK (ReportStatus IN ('open', 'reviewing', 'resolved', 'dismissed'))
);
GO

CREATE INDEX IX_ContentReports_Queue
    ON dbo.ContentReports (ReportStatus, CreatedAt)
    INCLUDE (ReporterUserId, VideoId, CommentId, ChannelId, Reason);
CREATE INDEX IX_ContentReports_Reporter_CreatedAt
    ON dbo.ContentReports (ReporterUserId, CreatedAt DESC);
GO

CREATE TABLE dbo.ModerationActions
(
    ModerationActionId  BIGINT IDENTITY(1,1) NOT NULL,
    ContentReportId     BIGINT NULL,
    ModeratorUserId     BIGINT NULL,
    ActionType          VARCHAR(16) NOT NULL,
    ActionDetails       NVARCHAR(2000) NULL,
    CreatedAt           DATETIME2(3) NOT NULL CONSTRAINT DF_ModerationActions_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT PK_ModerationActions PRIMARY KEY CLUSTERED (ModerationActionId),
    CONSTRAINT FK_ModerationActions_Reports FOREIGN KEY (ContentReportId) REFERENCES dbo.ContentReports (ContentReportId),
    CONSTRAINT FK_ModerationActions_Moderator FOREIGN KEY (ModeratorUserId) REFERENCES dbo.Users (UserId),
    CONSTRAINT CK_ModerationActions_Type CHECK (ActionType IN ('dismiss', 'hide', 'restore', 'remove', 'warn', 'suspend', 'unsuspend'))
);
GO

CREATE INDEX IX_ModerationActions_Report_CreatedAt
    ON dbo.ModerationActions (ContentReportId, CreatedAt DESC);
GO

CREATE TABLE dbo.Notifications
(
    NotificationId      BIGINT IDENTITY(1,1) NOT NULL,
    RecipientUserId     BIGINT NOT NULL,
    ActorUserId         BIGINT NULL,
    NotificationType    VARCHAR(24) NOT NULL,
    VideoId             BIGINT NULL,
    CommentId           BIGINT NULL,
    ChannelId           BIGINT NULL,
    Message             NVARCHAR(500) NOT NULL,
    IsRead              BIT NOT NULL CONSTRAINT DF_Notifications_IsRead DEFAULT (0),
    ReadAt              DATETIME2(3) NULL,
    CreatedAt           DATETIME2(3) NOT NULL CONSTRAINT DF_Notifications_CreatedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT PK_Notifications PRIMARY KEY CLUSTERED (NotificationId),
    CONSTRAINT FK_Notifications_Recipient FOREIGN KEY (RecipientUserId) REFERENCES dbo.Users (UserId),
    CONSTRAINT FK_Notifications_Actor FOREIGN KEY (ActorUserId) REFERENCES dbo.Users (UserId),
    CONSTRAINT FK_Notifications_Videos FOREIGN KEY (VideoId) REFERENCES dbo.Videos (VideoId),
    CONSTRAINT FK_Notifications_Comments FOREIGN KEY (CommentId) REFERENCES dbo.VideoComments (CommentId),
    CONSTRAINT FK_Notifications_Channels FOREIGN KEY (ChannelId) REFERENCES dbo.Channels (ChannelId),
    CONSTRAINT CK_Notifications_Type CHECK (NotificationType IN ('new_video', 'new_subscriber', 'new_comment', 'comment_reply', 'comment_reaction', 'video_reaction', 'system')),
    CONSTRAINT CK_Notifications_ReadState CHECK (
        (IsRead = 0 AND ReadAt IS NULL) OR (IsRead = 1 AND ReadAt IS NOT NULL)
    ),
    CONSTRAINT CK_Notifications_AtMostOneReference CHECK (
        (CASE WHEN VideoId IS NULL THEN 0 ELSE 1 END) +
        (CASE WHEN CommentId IS NULL THEN 0 ELSE 1 END) +
        (CASE WHEN ChannelId IS NULL THEN 0 ELSE 1 END) <= 1
    )
);
GO

CREATE INDEX IX_Notifications_Inbox
    ON dbo.Notifications (RecipientUserId, IsRead, CreatedAt DESC)
    INCLUDE (ActorUserId, NotificationType, VideoId, CommentId, ChannelId, Message);
GO

CREATE TABLE dbo.NotificationPreferences
(
    UserId              BIGINT NOT NULL,
    NotificationType    VARCHAR(24) NOT NULL,
    IsEnabled           BIT NOT NULL CONSTRAINT DF_NotificationPreferences_IsEnabled DEFAULT (1),
    UpdatedAt           DATETIME2(3) NOT NULL CONSTRAINT DF_NotificationPreferences_UpdatedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT PK_NotificationPreferences PRIMARY KEY CLUSTERED (UserId, NotificationType),
    CONSTRAINT FK_NotificationPreferences_Users FOREIGN KEY (UserId) REFERENCES dbo.Users (UserId),
    CONSTRAINT CK_NotificationPreferences_Type CHECK (NotificationType IN ('new_video', 'new_subscriber', 'new_comment', 'comment_reply', 'comment_reaction', 'video_reaction', 'system'))
);
GO

CREATE TABLE dbo.SearchHistory
(
    SearchHistoryId     BIGINT IDENTITY(1,1) NOT NULL,
    UserId              BIGINT NOT NULL,
    SearchQuery         NVARCHAR(200) NOT NULL,
    CategoryId          INT NULL,
    SearchedAt          DATETIME2(3) NOT NULL CONSTRAINT DF_SearchHistory_SearchedAt DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT PK_SearchHistory PRIMARY KEY CLUSTERED (SearchHistoryId),
    CONSTRAINT FK_SearchHistory_Users FOREIGN KEY (UserId) REFERENCES dbo.Users (UserId),
    CONSTRAINT FK_SearchHistory_Categories FOREIGN KEY (CategoryId) REFERENCES dbo.VideoCategories (CategoryId),
    CONSTRAINT CK_SearchHistory_Query_NotBlank CHECK (LEN(LTRIM(RTRIM(SearchQuery))) > 0)
);
GO

CREATE INDEX IX_SearchHistory_User_SearchedAt
    ON dbo.SearchHistory (UserId, SearchedAt DESC)
    INCLUDE (SearchQuery, CategoryId);
GO

INSERT INTO dbo.VideoCategories (CategoryName, DisplayOrder)
VALUES
    (N'Âm nhạc', 1),
    (N'Trò chơi', 2),
    (N'Tin tức', 3),
    (N'Blog / đời sống', 4),
    (N'Trực tiếp', 5);
GO

PRINT N'YoutubeSimulationDb was initialized successfully.';
PRINT N'Create an application/backend login separately and grant only the required database permissions.';
GO
