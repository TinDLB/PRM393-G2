import 'local_app_database.dart';

class ThemePreferences {
  const ThemePreferences(this._database);

  final LocalAppDatabase _database;

  bool get isDarkMode => _database.isDarkMode;

  Future<void> saveDarkMode(bool isDarkMode) => _database.saveTheme(isDarkMode);
}
