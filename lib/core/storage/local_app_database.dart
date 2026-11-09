import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sqlite_store.dart';

class LocalAppDatabase {
  LocalAppDatabase._(this._preferences, this._sqlite);

  static const _darkModeKey = 'isDarkMode';
  static const _likedVideoIdsKey = 'likedVideoIds';
  static const _savedVideoIdsKey = 'savedVideoIds';
  static const _subscribedChannelsKey = 'subscribedChannels';
  static const _historyVideoIdsKey = 'historyVideoIds';
  static const _videoCacheKey = 'youtubeVideoCache';

  final SharedPreferences _preferences;
  final SqliteStore? _sqlite;
  bool? _isDarkMode;
  final Map<String, List<String>> _collections = {};
  List<Map<String, Object?>> _cachedVideos = const [];

  static Future<LocalAppDatabase> open() async {
    final preferences = await SharedPreferences.getInstance();
    final sqlite = await SqliteStore.open();
    final database = LocalAppDatabase._(preferences, sqlite);
    await database._load();
    return database;
  }

  bool get isDarkMode => _isDarkMode ?? false;

  List<String> get likedVideoIds => _collections['liked'] ?? const [];
  List<String> get savedVideoIds => _collections['saved'] ?? const [];
  List<String> get subscribedChannels => _collections['subscribed'] ?? const [];
  List<String> get historyVideoIds => _collections['history'] ?? const [];
  List<Map<String, Object?>> get cachedVideos => _cachedVideos;

  Future<void> _load() async {
    if (_sqlite == null) {
      _isDarkMode = _preferences.getBool(_darkModeKey) ?? false;
      _collections['liked'] =
          _preferences.getStringList(_likedVideoIdsKey) ?? const [];
      _collections['saved'] =
          _preferences.getStringList(_savedVideoIdsKey) ?? const [];
      _collections['subscribed'] =
          _preferences.getStringList(_subscribedChannelsKey) ?? const [];
      _collections['history'] =
          _preferences.getStringList(_historyVideoIdsKey) ?? const [];
      _cachedVideos = _decodeVideos(_preferences.getString(_videoCacheKey));
      return;
    }

    _isDarkMode = (await _sqlite.readSetting(_darkModeKey)) == 'true';
    for (final entry in {
      'liked': _likedVideoIdsKey,
      'saved': _savedVideoIdsKey,
      'subscribed': _subscribedChannelsKey,
      'history': _historyVideoIdsKey,
    }.entries) {
      _collections[entry.key] = await _sqlite.readCollection(entry.value);
    }
    _cachedVideos = [
      for (final payload in await _sqlite.readVideoPayloads())
        Map<String, Object?>.from(jsonDecode(payload) as Map),
    ];
  }

  List<Map<String, Object?>> _decodeVideos(String? encoded) {
    if (encoded == null) return const [];
    try {
      return [
        for (final record in jsonDecode(encoded) as List<dynamic>)
          Map<String, Object?>.from(record as Map),
      ];
    } on FormatException catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'local app database',
          context: ErrorDescription('while decoding cached videos'),
        ),
      );
      return const [];
    }
  }

  Future<void> saveTheme(bool isDarkMode) async {
    _isDarkMode = isDarkMode;
    if (_sqlite != null) {
      await _sqlite.writeSetting(_darkModeKey, isDarkMode.toString());
      return;
    }
    if (!await _preferences.setBool(_darkModeKey, isDarkMode)) {
      throw StateError('Could not save theme preference.');
    }
  }

  Future<void> saveLibrary({
    required Iterable<String> likedVideoIds,
    required Iterable<String> savedVideoIds,
    required Iterable<String> subscribedChannels,
    required Iterable<String> historyVideoIds,
    required Iterable<Map<String, Object?>> cachedVideos,
  }) async {
    final collections = {
      'liked': likedVideoIds,
      'saved': savedVideoIds,
      'subscribed': subscribedChannels,
      'history': historyVideoIds,
    };
    _collections
      ..clear()
      ..addAll({
        for (final entry in collections.entries)
          entry.key: entry.value.toList(),
      });
    _cachedVideos = cachedVideos.toList();

    if (_sqlite != null) {
      await _sqlite.replaceLibrary(
        collections: collections,
        videoPayloads: {
          for (final video in _cachedVideos)
            video['videoId']! as String: jsonEncode(video),
        },
      );
      return;
    }
    final writes = [
      _preferences.setStringList(_likedVideoIdsKey, likedVideoIds.toList()),
      _preferences.setStringList(_savedVideoIdsKey, savedVideoIds.toList()),
      _preferences.setStringList(
        _subscribedChannelsKey,
        subscribedChannels.toList(),
      ),
      _preferences.setStringList(_historyVideoIdsKey, historyVideoIds.toList()),
      _preferences.setString(_videoCacheKey, jsonEncode(_cachedVideos)),
    ];
    if (!(await Future.wait(writes)).every((saved) => saved)) {
      throw StateError('Could not save local library data.');
    }
  }
}
