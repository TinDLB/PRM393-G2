import 'dart:io';

import 'package:sqflite/sqflite.dart';

class SqliteStore {
  SqliteStore._(this._database);

  final Database _database;

  static Future<SqliteStore?> open() async {
    if (!Platform.isAndroid) return null;

    final database = await openDatabase(
      'youtube_review.db',
      version: 1,
      onCreate: (database, version) async {
        await database.execute(
          'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
        );
        await database.execute(
          'CREATE TABLE collections '
          '(collection TEXT NOT NULL, item_id TEXT NOT NULL, '
          'PRIMARY KEY (collection, item_id))',
        );
        await database.execute(
          'CREATE TABLE videos (video_id TEXT PRIMARY KEY, payload TEXT NOT NULL)',
        );
      },
    );
    return SqliteStore._(database);
  }

  Future<String?> readSetting(String key) async {
    final rows = await _database.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<List<String>> readCollection(String collection) async {
    final rows = await _database.query(
      'collections',
      columns: ['item_id'],
      where: 'collection = ?',
      whereArgs: [collection],
    );
    return [for (final row in rows) row['item_id'] as String];
  }

  Future<List<String>> readVideoPayloads() async {
    final rows = await _database.query('videos', columns: ['payload']);
    return [for (final row in rows) row['payload'] as String];
  }

  Future<void> writeSetting(String key, String value) async {
    await _database.insert('settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> replaceLibrary({
    required Map<String, Iterable<String>> collections,
    required Map<String, String> videoPayloads,
  }) async {
    await _database.transaction((transaction) async {
      for (final entry in collections.entries) {
        await transaction.delete(
          'collections',
          where: 'collection = ?',
          whereArgs: [entry.key],
        );
        for (final itemId in entry.value) {
          await transaction.insert('collections', {
            'collection': entry.key,
            'item_id': itemId,
          });
        }
      }
      await transaction.delete('videos');
      for (final entry in videoPayloads.entries) {
        await transaction.insert('videos', {
          'video_id': entry.key,
          'payload': entry.value,
        });
      }
    });
  }
}
