class SqliteStore {
  static Future<SqliteStore?> open() async => null;

  Future<String?> readSetting(String key) =>
      throw UnsupportedError('SQLite is unavailable on this platform.');

  Future<List<String>> readCollection(String collection) =>
      throw UnsupportedError('SQLite is unavailable on this platform.');

  Future<List<String>> readVideoPayloads() =>
      throw UnsupportedError('SQLite is unavailable on this platform.');

  Future<void> writeSetting(String key, String value) =>
      throw UnsupportedError('SQLite is unavailable on this platform.');

  Future<void> replaceLibrary({
    required Map<String, Iterable<String>> collections,
    required Map<String, String> videoPayloads,
  }) => throw UnsupportedError('SQLite is unavailable on this platform.');
}
