import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:youtube/core/network/backend_api_client.dart';
import 'package:youtube/features/account/presentation/widgets/account_credentials_dialog.dart';
import 'package:youtube/features/account/repository/account_repository.dart';

void main() {
  test('registration creates account without signing the user in', () async {
    final apiClient = BackendApiClient(
      baseUri: Uri.parse('http://localhost:5296'),
      client: MockClient((request) async {
        expect(request.url.path, '/api/auth/register');
        expect(request.headers.containsKey('authorization'), isFalse);
        return http.Response(
          jsonEncode({
            'userId': 1,
            'displayName': 'Người xem',
            'email': 'new@example.com',
          }),
          201,
          headers: {
            'content-type': 'application/json; charset=utf-8',
            'location': '/api/account/me',
          },
        );
      }),
    );
    final repository = BackendAccountRepository(apiClient);
    addTearDown(() {
      repository.dispose();
      apiClient.close();
    });

    await repository.register(
      email: 'new@example.com',
      password: 'password123',
      displayName: 'Người xem',
    );

    expect(repository.currentUser, isNull);
    expect(repository.accessToken, isNull);
    expect(repository.errorMessage, isNull);
  });

  testWidgets('network login errors are actionable and self-dismiss', (
    tester,
  ) async {
    final apiClient = BackendApiClient(
      baseUri: Uri.parse('http://localhost:5296'),
      client: MockClient((request) async {
        throw http.ClientException('XMLHttpRequest error.', request.url);
      }),
    );
    final repository = BackendAccountRepository(apiClient);
    addTearDown(() {
      repository.dispose();
      apiClient.close();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: AccountCredentialsDialog(
          repository: repository,
          fullScreen: true,
        ),
      ),
    );
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'person@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'password123');
    await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
    await tester.pumpAndSettle();

    const errorMessage =
        'Không kết nối được máy chủ ở cổng 5296. Hãy chạy run.ps1 hoặc khởi động API, rồi thử lại.';
    expect(find.text(errorMessage), findsOneWidget);

    await tester.pump(const Duration(seconds: 6));
    await tester.pump();

    expect(find.text(errorMessage), findsNothing);
  });
}
