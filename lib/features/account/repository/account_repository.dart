import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/network/backend_api_client.dart';
import '../models/account_user.dart';

abstract interface class AccountRepository implements Listenable {
  AccountUser? get currentUser;
  String? get accessToken;
  bool get isInitialized;
  bool get isSigningIn;
  bool get hasChannelManagerRole;
  String? get errorMessage;
  Future<void> initialize();
  Future<void> signInWithPassword(String email, String password);
  Future<void> register({
    required String email,
    required String password,
    required String displayName,
  });
  Future<void> requestPasswordReset(String email);
  Future<void> resetPassword({
    required String email,
    required String token,
    required String newPassword,
  });
  void setChannelManagerRole(bool isManager);
  Future<void> signOut();
  void dispose();
}

class BackendAccountRepository extends ChangeNotifier
    implements AccountRepository {
  BackendAccountRepository(this._apiClient);

  final BackendApiClient _apiClient;
  AccountUser? _currentUser;
  bool _isInitialized = false;
  bool _isSigningIn = false;
  bool _hasChannelManagerRole = false;
  String? _errorMessage;
  Timer? _errorClearTimer;
  Future<void>? _initialization;

  @override
  AccountUser? get currentUser => _currentUser;

  @override
  String? get accessToken => _apiClient.accessToken;

  @override
  bool get isInitialized => _isInitialized;

  @override
  bool get isSigningIn => _isSigningIn;

  @override
  bool get hasChannelManagerRole => _hasChannelManagerRole;

  @override
  String? get errorMessage => _errorMessage;

  @override
  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    try {
      await _apiClient.initialize();
      if (_apiClient.isAuthenticated) {
        try {
          await _loadCurrentUser();
        } catch (error) {
          _setError(error);
        }
      }
    } catch (error) {
      _setError(error);
    } finally {
      _isInitialized = true;
      notifyListeners();
    }
  }

  Future<void> _loadCurrentUser() async {
    try {
      final response = await _apiClient.get('/api/account/me');
      _setUser(
        _userFromJson(response['user'] as Map<String, dynamic>? ?? response),
      );
    } on BackendApiException catch (error) {
      if (error.statusCode == 401) {
        await _apiClient.clearAccessToken();
        _setUser(null);
        return;
      }
      rethrow;
    }
  }

  AccountUser _userFromJson(Map<String, dynamic> json) => AccountUser(
    id: json['userId']?.toString(),
    displayName: json['displayName'] as String? ?? '',
    email: json['email'] as String? ?? '',
    photoUrl: json['photoUrl'] as String?,
  );

  Future<void> _authenticate(String path, Map<String, Object?> body) async {
    _isSigningIn = true;
    _clearError();
    notifyListeners();
    try {
      final response = await _apiClient.post(
        path,
        body: body,
        authenticated: false,
      );
      final token = response['token'] as String?;
      final user = response['user'];
      if (token == null || user is! Map<String, dynamic>) {
        throw const FormatException(
          'Backend authentication response is incomplete.',
        );
      }
      await _apiClient.saveAccessToken(token);
      _setUser(_userFromJson(user));
    } catch (error) {
      _setError(error);
    } finally {
      _isSigningIn = false;
      notifyListeners();
    }
  }

  Future<void> _sendAuthRequest(String path, Map<String, Object?> body) async {
    _isSigningIn = true;
    _clearError();
    notifyListeners();
    try {
      await _apiClient.post(path, body: body, authenticated: false);
    } catch (error) {
      _setError(error);
    } finally {
      _isSigningIn = false;
      notifyListeners();
    }
  }

  @override
  Future<void> signInWithPassword(String email, String password) =>
      _authenticate('/api/auth/login', {'email': email, 'password': password});

  @override
  Future<void> register({
    required String email,
    required String password,
    required String displayName,
  }) => _sendAuthRequest('/api/auth/register', {
    'email': email,
    'password': password,
    'displayName': displayName,
  });

  @override
  Future<void> requestPasswordReset(String email) =>
      _sendAuthRequest('/api/auth/password-reset/request', {'email': email});

  @override
  Future<void> resetPassword({
    required String email,
    required String token,
    required String newPassword,
  }) async {
    await _sendAuthRequest('/api/auth/password-reset/complete', {
      'email': email,
      'token': token,
      'newPassword': newPassword,
    });
    if (_errorMessage == null) {
      await _apiClient.clearAccessToken();
      _setUser(null);
    }
  }

  @override
  void setChannelManagerRole(bool isManager) {
    _hasChannelManagerRole = isManager && _currentUser != null;
    notifyListeners();
  }

  @override
  Future<void> signOut() async {
    try {
      if (_apiClient.isAuthenticated) {
        await _apiClient.post('/api/auth/logout');
      }
      await _apiClient.clearAccessToken();
      _setUser(null);
    } catch (error) {
      _setError(error);
    }
  }

  void _setUser(AccountUser? user) {
    _currentUser = user;
    if (user == null) _hasChannelManagerRole = false;
    _clearError();
    notifyListeners();
  }

  void _clearError() {
    _errorClearTimer?.cancel();
    _errorClearTimer = null;
    _errorMessage = null;
  }

  void _setError(Object error) {
    final message = error.toString();
    final normalizedMessage = message.toLowerCase();
    _errorMessage =
        normalizedMessage.contains('socketexception') ||
            normalizedMessage.contains('connection refused') ||
            normalizedMessage.contains('failed to fetch') ||
            normalizedMessage.contains('xmlhttprequest error')
        ? 'Không kết nối được máy chủ ở cổng 5296. Hãy chạy run.ps1 hoặc khởi động API, rồi thử lại.'
        : message;
    _errorClearTimer?.cancel();
    _errorClearTimer = Timer(const Duration(seconds: 6), () {
      _errorMessage = null;
      _errorClearTimer = null;
      notifyListeners();
    });
    notifyListeners();
  }

  @override
  void dispose() {
    _errorClearTimer?.cancel();
    super.dispose();
  }
}
