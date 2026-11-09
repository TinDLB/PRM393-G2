import 'dart:math' as math;
import 'dart:typed_data';

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class BackendApiException implements Exception {
  const BackendApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class BackendApiClient {
  static const _uploadChunkSize = 4 * 1024 * 1024;

  BackendApiClient({
    http.Client? client,
    FlutterSecureStorage? secureStorage,
    Uri? baseUri,
  }) : _client = client ?? http.Client(),
       _secureStorage = secureStorage ?? const FlutterSecureStorage(),
       _baseUri =
           baseUri ??
           Uri.parse(
             const String.fromEnvironment(
               'API_BASE_URL',
               defaultValue: 'http://localhost:5296',
             ),
           );

  static const _tokenKey = 'backend_access_token';

  final http.Client _client;
  final FlutterSecureStorage _secureStorage;
  final Uri _baseUri;
  String? _accessToken;

  Future<void> initialize() async {
    _accessToken = await _secureStorage.read(key: _tokenKey);
  }

  bool get isAuthenticated => _accessToken != null;
  String? get accessToken => _accessToken;
  Uri uriFor(String path) => _uri(path);

  Map<String, String> get authenticatedHeaders => {
    if (_accessToken case final token?) 'Authorization': 'Bearer $token',
  };

  void setAccessToken(String token) {
    _accessToken = token;
  }

  Future<void> saveAccessToken(String token) async {
    _accessToken = token;
    await _secureStorage.write(key: _tokenKey, value: token);
  }

  Future<void> clearAccessToken() async {
    _accessToken = null;
    await _secureStorage.delete(key: _tokenKey);
  }

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? queryParameters,
    bool authenticated = true,
  }) => _send(
    'GET',
    path,
    queryParameters: queryParameters,
    authenticated: authenticated,
  );

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, Object?>? body,
    bool authenticated = true,
  }) => _send('POST', path, body: body, authenticated: authenticated);

  Future<Map<String, dynamic>> put(String path, {Map<String, Object?>? body}) =>
      _send('PUT', path, body: body);

  Future<Map<String, dynamic>> patch(
    String path, {
    Map<String, Object?>? body,
  }) => _send('PATCH', path, body: body);

  Future<Map<String, dynamic>> delete(String path) => _send('DELETE', path);

  Future<Map<String, dynamic>> uploadVideo({
    required String path,
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
    if (fileSize <= 0) {
      throw const BackendApiException('Tệp video không được để trống.');
    }
    final headers = await _headers(authenticated: true);
    final started = await _client.post(
      _uri('$path/uploads'),
      headers: {...headers, 'Content-Type': 'application/json'},
      body: jsonEncode({
        'fileName': fileName,
        'title': title,
        'description': description,
        'categoryId': int.tryParse(categoryId),
        'visibility': visibility,
        'fileSize': fileSize,
        'durationSeconds': durationSeconds,
      }),
    );
    final uploadId = _decode(started)['uploadId'];
    if (uploadId is! String || uploadId.isEmpty) {
      throw const BackendApiException(
        'Máy chủ không tạo được phiên tải video.',
      );
    }

    var bytesSent = 0;
    var chunkIndex = 0;
    try {
      await for (final chunk in _splitIntoChunks(
        fileStream,
        _uploadChunkSize,
      )) {
        final response = await _client.put(
          _uri('$path/uploads/$uploadId/chunks/$chunkIndex'),
          headers: {...headers, 'Content-Type': 'application/octet-stream'},
          body: chunk,
        );
        _decode(response);
        bytesSent += chunk.length;
        chunkIndex++;
        onProgress?.call(bytesSent / fileSize);
      }
      if (bytesSent != fileSize) {
        throw BackendApiException(
          'Dữ liệu video đọc được ($bytesSent byte) không khớp kích thước tệp ($fileSize byte).',
        );
      }
      if (thumbnailBytes != null && thumbnailMimeType != null) {
        final thumbnail = await _client.put(
          _uri('$path/uploads/$uploadId/thumbnail'),
          headers: {...headers, 'Content-Type': thumbnailMimeType},
          body: thumbnailBytes,
        );
        _decode(thumbnail);
      }
      final completed = await _client.post(
        _uri('$path/uploads/$uploadId/complete'),
        headers: headers,
      );
      return _decode(completed);
    } catch (error, stackTrace) {
      try {
        await _client.delete(_uri('$path/uploads/$uploadId'), headers: headers);
      } catch (cleanupError, cleanupStackTrace) {
        Error.throwWithStackTrace(
          BackendApiException(
            'Tải video thất bại: $error. Không thể xóa phiên tải dở: $cleanupError',
          ),
          cleanupStackTrace,
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Stream<Uint8List> _splitIntoChunks(
    Stream<List<int>> source,
    int chunkSize,
  ) async* {
    var buffer = BytesBuilder(copy: false);
    await for (final data in source) {
      var offset = 0;
      while (offset < data.length) {
        final remaining = chunkSize - buffer.length;
        final length = math.min(remaining, data.length - offset);
        buffer.add(data.sublist(offset, offset + length));
        offset += length;
        if (buffer.length == chunkSize) {
          yield buffer.takeBytes();
          buffer = BytesBuilder(copy: false);
        }
      }
    }
    if (buffer.isNotEmpty) yield buffer.takeBytes();
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, String>? queryParameters,
    Map<String, Object?>? body,
    bool authenticated = true,
  }) async {
    final uri = _uri(path, queryParameters);
    final headers = await _headers(authenticated: authenticated);
    if (body != null) headers['Content-Type'] = 'application/json';
    final encodedBody = body == null ? null : jsonEncode(body);
    final response = switch (method) {
      'GET' => await _client.get(uri, headers: headers),
      'POST' => await _client.post(uri, headers: headers, body: encodedBody),
      'PUT' => await _client.put(uri, headers: headers, body: encodedBody),
      'PATCH' => await _client.patch(uri, headers: headers, body: encodedBody),
      'DELETE' => await _client.delete(uri, headers: headers),
      _ => throw ArgumentError.value(method, 'method'),
    };
    return _decode(response);
  }

  Uri _uri(String path, [Map<String, String>? queryParameters]) {
    final relative = Uri.parse(path);
    return _baseUri.resolveUri(
      relative.replace(queryParameters: queryParameters),
    );
  }

  Future<Map<String, String>> _headers({required bool authenticated}) async {
    final headers = <String, String>{'Accept': 'application/json'};
    if (authenticated) {
      final token = _accessToken;
      if (token == null || token.isEmpty) {
        throw const BackendApiException('Bạn cần đăng nhập để tiếp tục.');
      }
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic> data = const {};
    if (response.body.isNotEmpty) {
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) data = decoded;
      } on FormatException {
        throw BackendApiException(
          'Máy chủ trả về dữ liệu không hợp lệ (HTTP ${response.statusCode}).',
          statusCode: response.statusCode,
        );
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message =
          data['error'] as String? ??
          data['message'] as String? ??
          data['detail'] as String? ??
          data['title'] as String? ??
          'Máy chủ báo lỗi HTTP ${response.statusCode}.';
      throw BackendApiException(message, statusCode: response.statusCode);
    }
    return data;
  }

  void close() => _client.close();
}
