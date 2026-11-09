import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:youtube/core/network/backend_api_client.dart';
import 'package:youtube/features/account/models/managed_youtube_video.dart';
import 'package:youtube/features/youtube/repository/backend_youtube_video_repository.dart';

void main() {
  test(
    'feed parses SQL Server identity values and simulation metadata',
    () async {
      final apiClient = BackendApiClient(
        baseUri: Uri.parse('http://localhost:5296'),
        client: MockClient((request) async {
          expect(request.url.path, '/api/videos');
          expect(request.url.queryParameters['category'], 'Âm nhạc');
          expect(request.headers['authorization'], 'Bearer session-token');
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'items': [
                  {
                    'videoId': 42,
                    'channelId': 7,
                    'channel': 'Kênh thử nghiệm',
                    'title': 'Video thử nghiệm',
                    'details': '12 lượt xem',
                    'durationSeconds': 95,
                    'category': 'Âm nhạc',
                    'thumbnailUrl':
                        'http://localhost:5296/api/videos/42/thumbnail',
                    'visibility': 'public',
                    'isLiked': true,
                    'isSaved': false,
                    'isSubscribed': true,
                  },
                ],
              }),
            ),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      )..setAccessToken('session-token');
      final repository = BackendYoutubeVideoRepository(apiClient);

      final videos = await repository.fetchVideos(category: 'Âm nhạc');

      expect(videos, hasLength(1));
      expect(videos.single.video.videoId, '42');
      expect(videos.single.channelId, '7');
      expect(videos.single.video.title, 'Video thử nghiệm');
      expect(videos.single.video.duration, '1:35');
      expect(videos.single.isLiked, isTrue);
      expect(videos.single.isSubscribed, isTrue);
    },
  );

  test('all category does not filter the backend feed', () async {
    late http.Request captured;
    final apiClient = BackendApiClient(
      baseUri: Uri.parse('http://localhost:5296'),
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({'items': []}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final repository = BackendYoutubeVideoRepository(apiClient);

    await repository.fetchVideos(category: 'Tất cả');

    expect(captured.url.queryParameters['category'], isEmpty);
  });

  test('recording a video view sends the required request fields', () async {
    late http.Request captured;
    final apiClient = BackendApiClient(
      baseUri: Uri.parse('http://localhost:5296'),
      client: MockClient((request) async {
        captured = request;
        return http.Response('{}', 200);
      }),
    )..setAccessToken('session-token');
    addTearDown(apiClient.close);
    final repository = BackendYoutubeVideoRepository(apiClient);

    await repository.recordView('42');

    expect(captured.method, 'POST');
    expect(captured.url.path, '/api/videos/42/views');
    expect(jsonDecode(captured.body), {
      'watchedSeconds': 0,
      'completed': false,
      'viewSessionId': '',
    });
  });

  test(
    'subscriptions parse channels and channel pages load their details/videos',
    () async {
      final apiClient = BackendApiClient(
        baseUri: Uri.parse('http://localhost:5296'),
        client: MockClient((request) async {
          switch (request.url.path) {
            case '/api/subscriptions':
              return http.Response.bytes(
                utf8.encode(
                  jsonEncode({
                    'items': [
                      {
                        'channelId': 8,
                        'channel': 'Kênh đã đăng ký',
                        'handle': 'kenh-thu',
                        'thumbnailUrl': '/api/channels/8/avatar',
                      },
                    ],
                  }),
                ),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              );
            case '/api/channels/8':
              return http.Response.bytes(
                utf8.encode(
                  jsonEncode({
                    'channelId': 8,
                    'channel': 'Kênh đã đăng ký',
                    'handle': 'kenh-thu',
                    'description': 'Mô tả kênh',
                    'subscriberCount': 14,
                    'thumbnailUrl': '',
                  }),
                ),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              );
            case '/api/channels/8/videos':
              return http.Response.bytes(
                utf8.encode(
                  jsonEncode({
                    'items': [
                      {
                        'videoId': 32,
                        'channelId': 8,
                        'channel': 'Kênh đã đăng ký',
                        'title': 'Video mới',
                        'durationSeconds': 84,
                        'duration': '1:24',
                        'thumbnailUrl': '/api/videos/32/thumbnail',
                        'visibility': 'public',
                      },
                    ],
                  }),
                ),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              );
            default:
              fail('Unexpected API request: ${request.url}');
          }
        }),
      )..setAccessToken('session-token');
      addTearDown(apiClient.close);
      final repository = BackendYoutubeVideoRepository(apiClient);

      final channels = await repository.fetchSubscribedChannels();
      final channel = await repository.fetchChannel(channels.single.id);
      final videos = await repository.fetchChannelVideos(channel.id);

      expect(channels.single.name, 'Kênh đã đăng ký');
      expect(
        channels.single.avatarUrl,
        'http://localhost:5296/api/channels/8/avatar',
      );
      expect(channel.description, 'Mô tả kênh');
      expect(channel.subscriberCount, 14);
      expect(videos.single.video.duration, '1:24');
      expect(
        videos.single.video.thumbnailUrl,
        'http://localhost:5296/api/videos/32/thumbnail',
      );
    },
  );

  test(
    'large video uploads are sent as bounded authenticated chunks',
    () async {
      const chunkSize = 4 * 1024 * 1024;
      final bytes = List<int>.generate(chunkSize + 7, (index) => index % 251);
      final chunkSizes = <int>[];
      final progress = <double>[];
      final apiClient = BackendApiClient(
        baseUri: Uri.parse('http://localhost:5296'),
        client: MockClient((request) async {
          expect(request.headers['authorization'], 'Bearer session-token');
          if (request.url.path == '/api/channels/mine/videos/uploads') {
            expect(request.method, 'POST');
            expect(jsonDecode(request.body), {
              'fileName': 'large.mp4',
              'title': 'Large video',
              'description': '',
              'categoryId': 2,
              'visibility': 'public',
              'fileSize': bytes.length,
              'durationSeconds': 12,
            });
            return http.Response(
              jsonEncode({'uploadId': 'upload-1', 'chunkSize': chunkSize}),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path.endsWith('/thumbnail')) {
            expect(request.method, 'PUT');
            expect(request.headers['content-type'], 'image/jpeg');
            expect(request.bodyBytes, [1, 2, 3]);
            return http.Response('{"uploaded":true}', 200);
          }
          if (request.url.path.endsWith('/complete')) {
            expect(request.method, 'POST');
            return http.Response(
              jsonEncode({'videoId': 12, 'title': 'Large video'}),
              201,
              headers: {'content-type': 'application/json'},
            );
          }

          expect(request.method, 'PUT');
          expect(request.headers['content-type'], 'application/octet-stream');
          chunkSizes.add(request.bodyBytes.length);
          return http.Response(
            jsonEncode({
              'bytesReceived': chunkSizes.fold<int>(0, (a, b) => a + b),
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      )..setAccessToken('session-token');
      addTearDown(apiClient.close);

      final result = await apiClient.uploadVideo(
        path: '/api/channels/mine/videos',
        fileStream: Stream<List<int>>.fromIterable([
          bytes.sublist(0, 1_000_000),
          bytes.sublist(1_000_000),
        ]),
        fileSize: bytes.length,
        fileName: 'large.mp4',
        title: 'Large video',
        description: '',
        categoryId: '2',
        visibility: 'public',
        durationSeconds: 12,
        thumbnailBytes: Uint8List.fromList([1, 2, 3]),
        thumbnailMimeType: 'image/jpeg',
        onProgress: progress.add,
      );

      expect(chunkSizes, [chunkSize, 7]);
      expect(progress, [chunkSize / bytes.length, 1]);
      expect(result['videoId'], 12);
    },
  );

  test('update sends a typed PATCH request with edited metadata', () async {
    late http.Request captured;
    final apiClient = BackendApiClient(
      baseUri: Uri.parse('http://localhost:5296'),
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({'videoId': 12, 'updated': true}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    )..setAccessToken('session-token');
    final repository = BackendYoutubeVideoRepository(apiClient);

    final updated = await repository.updateVideo(
      video: ManagedYoutubeVideo(
        id: '12',
        title: 'Cũ',
        description: '',
        privacyStatus: 'public',
        categoryId: '1',
        thumbnailUrl: 'https://example.com/thumbnail.jpg',
        publishedAt: DateTime.utc(2026, 11, 3),
      ),
      title: 'Đã sửa',
      description: 'Mô tả mới',
      categoryId: '4',
      visibility: 'private',
    );

    expect(captured.method, 'PATCH');
    expect(captured.url.path, '/api/channels/mine/videos/12');
    expect(jsonDecode(captured.body), {
      'title': 'Đã sửa',
      'description': 'Mô tả mới',
      'categoryId': '4',
      'visibility': 'private',
    });
    expect(updated.title, 'Đã sửa');
    expect(updated.description, 'Mô tả mới');
    expect(updated.categoryId, '4');
    expect(updated.privacyStatus, 'private');
    expect(updated.thumbnailUrl, 'https://example.com/thumbnail.jpg');
    expect(updated.publishedAt, DateTime.utc(2026, 11, 3));
  });
}
