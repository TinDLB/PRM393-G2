using System.Collections.Concurrent;

public sealed class ChunkedVideoUploadStore
{
    public const int ChunkSize = 4 * 1024 * 1024;
    private static readonly TimeSpan SessionLifetime = TimeSpan.FromHours(24);
    private readonly string _uploadRoot;
    private readonly ConcurrentDictionary<Guid, ChunkedVideoUpload> _uploads = new();

    public ChunkedVideoUploadStore(string mediaRoot)
    {
        _uploadRoot = Path.Combine(mediaRoot, ".uploads");
        Directory.CreateDirectory(_uploadRoot);
        foreach (var path in Directory.EnumerateFiles(_uploadRoot, "*.uploading*"))
        {
            if (File.GetLastWriteTimeUtc(path) < DateTime.UtcNow - SessionLifetime)
                File.Delete(path);
        }
    }

    public async Task<ChunkedVideoUpload> CreateAsync(
        long userId,
        long channelId,
        string fileName,
        string title,
        string description,
        int? categoryId,
        string visibility,
        int durationSeconds,
        long fileSize,
        CancellationToken cancellationToken)
    {
        var id = Guid.NewGuid();
        var path = Path.Combine(_uploadRoot, $"{id:N}.uploading");
        await using var output = new FileStream(
            path,
            FileMode.CreateNew,
            FileAccess.Write,
            FileShare.None,
            1,
            FileOptions.Asynchronous | FileOptions.SequentialScan);
        await output.FlushAsync(cancellationToken);

        var upload = new ChunkedVideoUpload(
            id,
            userId,
            channelId,
            fileName,
            title,
            description,
            categoryId,
            visibility,
            durationSeconds,
            fileSize,
            path);
        if (!_uploads.TryAdd(id, upload))
        {
            File.Delete(path);
            throw new InvalidOperationException("A video upload ID was duplicated.");
        }
        return upload;
    }

    public ChunkedVideoUpload Get(Guid id, long userId)
    {
        if (!_uploads.TryGetValue(id, out var upload) || upload.UserId != userId)
            throw new ChunkedVideoUploadException(
                StatusCodes.Status404NotFound,
                "The upload session was not found or has expired.");
        if (DateTime.UtcNow - upload.LastActivityUtc > SessionLifetime)
        {
            _uploads.TryRemove(id, out _);
            File.Delete(upload.TemporaryPath);
            throw new ChunkedVideoUploadException(
                StatusCodes.Status410Gone,
                "The upload session expired. Start the upload again.");
        }
        upload.LastActivityUtc = DateTime.UtcNow;
        return upload;
    }

    public void Remove(ChunkedVideoUpload upload)
    {
        _uploads.TryRemove(upload.Id, out _);
        if (File.Exists(upload.TemporaryPath))
            File.Delete(upload.TemporaryPath);
        if (File.Exists(upload.ThumbnailTemporaryPath))
            File.Delete(upload.ThumbnailTemporaryPath);
    }
}

public sealed class ChunkedVideoUpload(
    Guid id,
    long userId,
    long channelId,
    string fileName,
    string title,
    string description,
    int? categoryId,
    string visibility,
    int durationSeconds,
    long fileSize,
    string temporaryPath)
{
    public Guid Id { get; } = id;
    public long UserId { get; } = userId;
    public long ChannelId { get; } = channelId;
    public string FileName { get; } = fileName;
    public string Title { get; } = title;
    public string Description { get; } = description;
    public int? CategoryId { get; } = categoryId;
    public string Visibility { get; } = visibility;
    public int DurationSeconds { get; } = durationSeconds;
    public long FileSize { get; } = fileSize;
    public string TemporaryPath { get; } = temporaryPath;
    public string ThumbnailTemporaryPath { get; } = $"{temporaryPath}.thumbnail";
    public string? ThumbnailMimeType { get; set; }
    public long BytesReceived { get; set; }
    public int NextChunkIndex { get; set; }
    public DateTime LastActivityUtc { get; set; } = DateTime.UtcNow;
    public SemaphoreSlim Gate { get; } = new(1, 1);
}

public sealed class ChunkedVideoUploadException(int statusCode, string message)
    : Exception(message)
{
    public int StatusCode { get; } = statusCode;
}

public sealed record BeginVideoUploadRequest(
    string? FileName,
    string? Title,
    string? Description,
    int? CategoryId,
    string? Visibility,
    long FileSize,
    int? DurationSeconds = null);
