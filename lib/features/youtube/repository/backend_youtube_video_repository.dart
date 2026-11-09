import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/network/backend_api_client.dart';
import '../../account/models/managed_youtube_video.dart';
import '../models/youtube_channel.dart';
import '../models/youtube_video.dart';
import 'youtube_video_repository.dart';

enum YoutubeLibraryCollection { liked, watchLater, history }

class BackendYoutubeVideo {
  const BackendYoutubeVideo({
    required this.video,
    required this.channelId,
    required this.visibility,
    required this.isLiked,
    required this.isSaved,
    required this.isSubscribed,
  });

  final YoutubeVideo video;
  final String? channelId;
  final String? visibility;
  final bool isLiked;
  final bool isSaved;
  final bool isSubscribed;
}

class BackendYoutubeVideoRepository implements YoutubeVideoRepository {
  BackendYoutubeVideoRepository(this._apiClient);

  static const _avatarColors = [
    Color(0xFFCC2929),
    Color(0xFF2C6B9A),
    Color(0xFFB66E35),
    Color(0xFF438B65),
    Color(0xFF7156A5),
  ];

  final BackendApiClient _apiClient;

  @override
  Future<List<YoutubeVideo>> fetchPopular({String? category}) async =>
      (await fetchVideos(category: category))
          .map((item) => item.video)
          .toList();

  @override
  Future<List<YoutubeVideo>> searchVideos(
    String query, {
    String? category,
  }) async => (await fetchVideos(
    category: category,
    query: query,
  )).map((item) => item.video).toList();

  Future<List<BackendYoutubeVideo>> fetchVideos({
    String? category,
    String query = '',
  }) async {
    final selectedCategory = category == 'Tất cả' ? '' : category ?? '';
    final response = await _apiClient.get(
      '/api/videos',
      queryParameters: {'category': selectedCategory, 'query': query},
      authenticated: _apiClient.isAuthenticated,
    );
    return _parseVideoItems(response);
  }

  Future<List<BackendYoutubeVideo>> fetchLibrary(
    YoutubeLibraryCollection collection,
  ) async {
    final response = await _apiClient.get(
      '/api/library/${collection.name == 'watchLater' ? 'watch-later' : collection.name}',
    );
    return _parseVideoItems(response);
  }

  Future<List<BackendYoutubeVideo>> fetchSubscriptions() async {
    final response = await _apiClient.get('/api/library/subscriptions');
    return _parseVideoItems(response);
  }

  Future<List<YoutubeChannel>> fetchSubscribedChannels() async {
    final response = await _apiClient.get('/api/subscriptions');
    final items = _readItems(response);
    return items.map((item) => _parseChannel(item)).toList(growable: false);
  }

  Future<YoutubeChannel> fetchChannel(String channelId) async {
    final response = await _apiClient.get(
      '/api/channels/${Uri.encodeComponent(channelId)}',
      authenticated: _apiClient.isAuthenticated,
    );
    return _parseChannel(response);
  }

  Future<List<BackendYoutubeVideo>> fetchChannelVideos(String channelId) async {
    final response = await _apiClient.get(
      '/api/channels/${Uri.encodeComponent(channelId)}/videos',
      authenticated: _apiClient.isAuthenticated,
    );
    return _parseVideoItems(response);
  }

  Future<YoutubeChannel> fetchMyChannel() async {
    final response = await _apiClient.get('/api/channels/manage');
    final items = _readItems(response);
    if (items.isEmpty) {
      throw const BackendYoutubeVideoFormatException(
        'The account does not have a manageable channel.',
      );
    }
    return _parseChannel(items.first);
  }

  Future<YoutubeChannel> updateMyChannel({
    required String channelId,
    required String channelName,
    required String description,
  }) async {
    await _apiClient.patch(
      '/api/channels/${Uri.encodeComponent(channelId)}',
      body: {'channelName': channelName, 'description': description},
    );
    final response = await _apiClient.get(
      '/api/channels/${Uri.encodeComponent(channelId)}',
    );
    return _parseChannel(response);
  }

  Future<BackendYoutubeVideo> fetchVideo(String videoId) async {
    final response = await _apiClient.get(
      '/api/videos/${Uri.encodeComponent(videoId)}',
      authenticated: _apiClient.isAuthenticated,
    );
    final item = response['video'] ?? response['item'] ?? response;
    return _parseBackendVideo(_asMap(item, 'video'));
  }

  Future<bool?> toggleLike(String videoId) async {
    final response = await _apiClient.post(_videoPath(videoId, 'like'));
    return _optionalBool(response, const ['isLiked', 'liked']);
  }

  Future<bool?> toggleWatchLater(String videoId) async {
    final response = await _apiClient.post(_videoPath(videoId, 'watch-later'));
    return _optionalBool(response, const [
      'isSaved',
      'isInWatchLater',
      'saved',
    ]);
  }

  Future<bool?> toggleSubscription(String channelId) async {
    final response = await _apiClient.post(
      '/api/channels/${Uri.encodeComponent(channelId)}/subscription',
    );
    return _optionalBool(response, const ['isSubscribed', 'subscribed']);
  }

  Future<void> recordView(String videoId) async {
    await _apiClient.post(
      _videoPath(videoId, 'views'),
      body: {'watchedSeconds': 0, 'completed': false, 'viewSessionId': ''},
    );
  }

  Future<List<ManagedYoutubeVideo>> listMyVideos() async {
    final response = await _apiClient.get('/api/channels/mine/videos');
    final items = _readItems(response);
    return items.map(_parseManagedVideo).toList(growable: false);
  }

  Future<ManagedYoutubeVideo> uploadVideo({
    required Stream<List<int>> fileStream,
    required int fileSize,
    required String fileName,
    required String title,
    required String description,
    required String categoryId,
    required String visibility,
    required int durationSeconds,
    Uint8List? thumbnailBytes,
    String? thumbnailMimeType,
    void Function(double progress)? onProgress,
  }) async {
    final response = await _apiClient.uploadVideo(
      path: '/api/channels/mine/videos',
      fileStream: fileStream,
      fileSize: fileSize,
      fileName: fileName,
      title: title,
      description: description,
      categoryId: categoryId,
      visibility: visibility,
      durationSeconds: durationSeconds,
      thumbnailBytes: thumbnailBytes,
      thumbnailMimeType: thumbnailMimeType,
      onProgress: onProgress,
    );
    return _parseManagedVideo(_unwrapManagedVideo(response));
  }

  Future<ManagedYoutubeVideo> updateVideo({
    required ManagedYoutubeVideo video,
    required String title,
    required String description,
    required String categoryId,
    required String visibility,
  }) async {
    final path = '/api/channels/mine/videos/${Uri.encodeComponent(video.id)}';
    await _apiClient.patch(
      path,
      body: {
        'title': title,
        'description': description,
        'categoryId': categoryId,
        'visibility': visibility,
      },
    );
    return ManagedYoutubeVideo(
      id: video.id,
      title: title,
      description: description,
      privacyStatus: visibility,
      categoryId: categoryId,
      thumbnailUrl: video.thumbnailUrl,
      publishedAt: video.publishedAt,
      duration: video.duration,
    );
  }

  Future<void> deleteVideo(String videoId) async {
    await _apiClient.delete(
      '/api/channels/mine/videos/${Uri.encodeComponent(videoId)}',
    );
  }

  List<BackendYoutubeVideo> _parseVideoItems(Map<String, dynamic> response) =>
      _readItems(response).map(_parseBackendVideo).toList(growable: false);

  List<Map<String, dynamic>> _readItems(Map<String, dynamic> response) {
    final items = response['items'];
    if (items is! List) {
      throw const BackendYoutubeVideoFormatException(
        'The response must contain an items list.',
      );
    }
    return items.map((item) => _asMap(item, 'items[]')).toList(growable: false);
  }

  BackendYoutubeVideo _parseBackendVideo(Map<String, dynamic> item) {
    final videoId = _requiredIdString(item, 'videoId');
    final channel = _optionalString(item, 'channel') ?? 'Kênh mô phỏng';
    final durationSeconds = _optionalInt(item, 'durationSeconds') ?? 0;
    final duration = durationSeconds <= 0
        ? ''
        : _optionalString(item, 'duration') ?? _formatDuration(durationSeconds);
    final visibility = _optionalString(item, 'visibility');
    final video = YoutubeVideo(
      videoId: videoId,
      title: _optionalString(item, 'title') ?? 'Video mô phỏng',
      channel: channel,
      details: _optionalString(item, 'details') ?? '',
      duration: duration,
      category: _optionalString(item, 'category') ?? 'Tất cả',
      avatarColor: _avatarColorFor(channel),
      thumbnailUrlOverride: _resolveMediaUrl(
        _optionalString(item, 'thumbnailUrl'),
      ),
      durationSeconds: durationSeconds,
      isPublicUpload: visibility == 'public',
    );
    return BackendYoutubeVideo(
      video: video,
      channelId: _optionalIdString(item, 'channelId'),
      visibility: visibility,
      isLiked: _optionalBool(item, const ['isLiked']) ?? false,
      isSaved: _optionalBool(item, const ['isSaved']) ?? false,
      isSubscribed: _optionalBool(item, const ['isSubscribed']) ?? false,
    );
  }

  YoutubeChannel _parseChannel(Map<String, dynamic> item) {
    final id = _optionalIdString(item, 'channelId');
    if (id == null || id.isEmpty) {
      throw const BackendYoutubeVideoFormatException(
        'A channel is missing its id.',
      );
    }
    final avatar =
        _optionalString(item, 'avatarUrl') ??
        _optionalString(item, 'thumbnailUrl');
    return YoutubeChannel(
      id: id,
      name:
          _optionalString(item, 'channel') ??
          _optionalString(item, 'channelName') ??
          '',
      handle: _optionalString(item, 'handle') ?? '',
      description: _optionalString(item, 'description') ?? '',
      subscriberCount: _optionalInt(item, 'subscriberCount') ?? 0,
      avatarUrl: _resolveMediaUrl(avatar),
    );
  }

  ManagedYoutubeVideo _parseManagedVideo(Map<String, dynamic> item) {
    final id =
        _optionalIdString(item, 'id') ?? _optionalIdString(item, 'videoId');
    if (id == null || id.isEmpty) {
      throw const BackendYoutubeVideoFormatException(
        'A managed video is missing its id.',
      );
    }
    return ManagedYoutubeVideo(
      id: id,
      title: _optionalString(item, 'title') ?? '',
      description: _optionalString(item, 'description') ?? '',
      privacyStatus:
          _optionalString(item, 'visibility') ??
          _optionalString(item, 'privacyStatus') ??
          'private',
      categoryId: _optionalIdString(item, 'categoryId') ?? '1',
      thumbnailUrl: _resolveMediaUrl(_optionalString(item, 'thumbnailUrl')),
      publishedAt: DateTime.tryParse(
        _optionalString(item, 'publishedAt') ?? '',
      ),
      duration: (_optionalInt(item, 'durationSeconds') ?? 0) <= 0
          ? ''
          : _optionalString(item, 'duration') ?? '',
      durationSeconds: _optionalInt(item, 'durationSeconds') ?? 0,
    );
  }

  Map<String, dynamic> _unwrapManagedVideo(Map<String, dynamic> response) {
    final video = response['video'] ?? response['item'];
    return video == null ? response : _asMap(video, 'video');
  }

  String? _resolveMediaUrl(String? path) {
    if (path == null || path.isEmpty) return null;
    return _apiClient.uriFor(path).toString();
  }

  static Map<String, dynamic> _asMap(Object? value, String field) {
    if (value is Map<String, dynamic>) return value;
    throw BackendYoutubeVideoFormatException(
      'The $field value must be a JSON object.',
    );
  }

  static String _requiredIdString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is String && value.isNotEmpty) return value;
    if (value is int) return value.toString();
    throw BackendYoutubeVideoFormatException('A video is missing its $key.');
  }

  static String? _optionalIdString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is String || value is int) return value.toString();
    throw BackendYoutubeVideoFormatException(
      'The $key value must be a string or integer.',
    );
  }

  static String? _optionalString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is String) return value;
    throw BackendYoutubeVideoFormatException(
      'The $key value must be a string.',
    );
  }

  static int? _optionalInt(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is int) return value;
    throw BackendYoutubeVideoFormatException(
      'The $key value must be an integer.',
    );
  }

  static bool? _optionalBool(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value == null) continue;
      if (value is bool) return value;
      throw BackendYoutubeVideoFormatException(
        'The $key value must be a boolean.',
      );
    }
    return null;
  }

  static Color _avatarColorFor(String channel) {
    var hash = 0;
    for (final codeUnit in channel.codeUnits) {
      hash = (hash * 31 + codeUnit) & 0x7fffffff;
    }
    return _avatarColors[hash % _avatarColors.length];
  }

  static String _videoPath(String videoId, String action) =>
      '/api/videos/${Uri.encodeComponent(videoId)}/$action';

  static String _formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final remainder = seconds % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${remainder.toString().padLeft(2, '0')}';
    }
    return '$minutes:${remainder.toString().padLeft(2, '0')}';
  }
}

class BackendYoutubeVideoFormatException implements Exception {
  const BackendYoutubeVideoFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}
