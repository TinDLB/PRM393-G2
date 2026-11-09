import 'dart:async';

import 'package:flutter/material.dart';

import 'core/network/backend_api_client.dart';
import 'core/storage/local_app_database.dart';
import 'core/storage/local_app_database_factory.dart';
import 'core/storage/theme_preferences.dart';
import 'features/account/repository/account_repository.dart';
import 'features/youtube/presentation/screens/youtube_screen.dart';
import 'features/youtube/repository/backend_youtube_video_repository.dart';
import 'features/youtube/repository/youtube_video_repository.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  final YoutubeVideoRepository? repository;
  final AccountRepository? accountRepository;
  final LocalAppDatabase? database;

  const MyApp({
    super.key,
    this.repository,
    this.accountRepository,
    this.database,
  });

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _isDarkMode = false;
  late final BackendApiClient _apiClient = BackendApiClient();
  late final Future<LocalAppDatabase> _databaseFuture = widget.database == null
      ? openLocalAppDatabase()
      : Future.value(widget.database);
  late final AccountRepository _accountRepository =
      widget.accountRepository ?? BackendAccountRepository(_apiClient);
  late final YoutubeVideoRepository _videoRepository =
      widget.repository ?? BackendYoutubeVideoRepository(_apiClient);

  @override
  void initState() {
    super.initState();
    _accountRepository.addListener(_onAccountChanged);
    unawaited(_accountRepository.initialize());
    unawaited(_loadThemePreference());
  }

  void _onAccountChanged() {
    if (_apiClient.isAuthenticated) {
      unawaited(_loadRemoteThemePreference());
    }
  }

  @override
  void dispose() {
    _accountRepository.removeListener(_onAccountChanged);
    if (widget.accountRepository == null) {
      _accountRepository.dispose();
      _apiClient.close();
    }
    super.dispose();
  }

  Future<void> _loadThemePreference() async {
    try {
      final database = await _databaseFuture;
      if (mounted) {
        setState(() => _isDarkMode = database.isDarkMode);
      }
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'application theme',
          context: ErrorDescription('while loading the saved theme'),
        ),
      );
    }
  }

  void _toggleTheme() {
    final isDarkMode = !_isDarkMode;
    setState(() => _isDarkMode = isDarkMode);
    unawaited(_saveThemePreference(isDarkMode));
  }

  Future<void> _saveThemePreference(bool isDarkMode) async {
    try {
      final database = await _databaseFuture;
      await ThemePreferences(database).saveDarkMode(isDarkMode);
      if (_accountRepository.currentUser != null) {
        await _apiClient.put(
          '/api/account/preferences',
          body: {'themeMode': isDarkMode ? 'dark' : 'light'},
        );
      }
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'application theme',
          context: ErrorDescription('while saving the selected theme'),
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không thể lưu chế độ giao diện.')),
        );
      }
    }
  }

  Future<void> _loadRemoteThemePreference() async {
    if (!_apiClient.isAuthenticated) return;
    try {
      final response = await _apiClient.get('/api/account/me');
      final user = response['user'];
      final preferences = response['preferences'];
      if (!mounted || user is! Map || preferences is! Map) return;
      final mode = preferences['themeMode'];
      if (mode != 'light' && mode != 'dark') return;
      final isDarkMode = mode == 'dark';
      setState(() => _isDarkMode = isDarkMode);
      final database = await _databaseFuture;
      await ThemePreferences(database).saveDarkMode(isDarkMode);
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'application theme',
          context: ErrorDescription('while loading the account theme'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: _isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: FutureBuilder<LocalAppDatabase>(
        future: _databaseFuture,
        builder: (context, snapshot) {
          final database = snapshot.data;
          if (database == null) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return YoutubeScreen(
            repository: _videoRepository,
            accountRepository: _accountRepository,
            database: database,
            apiClient: _apiClient,
            isDarkMode: _isDarkMode,
            onToggleTheme: _toggleTheme,
          );
        },
      ),
    );
  }
}
