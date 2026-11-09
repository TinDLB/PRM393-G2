import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/network/backend_api_client.dart';
import '../../models/account_user.dart';
import '../../models/managed_youtube_video.dart';
import '../../repository/account_repository.dart';
import '../widgets/account_credentials_dialog.dart';
import 'channel_management_screen.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({
    super.key,
    required this.repository,
    required this.apiClient,
    this.onManagedVideoAvailable,
    this.onVideosLoaded,
    this.onVideoDeleted,
  });

  final AccountRepository repository;
  final BackendApiClient apiClient;
  final void Function(ManagedYoutubeVideo video, String channel)?
  onManagedVideoAvailable;
  final void Function(List<ManagedYoutubeVideo> videos, String channel)?
  onVideosLoaded;
  final ValueChanged<String>? onVideoDeleted;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: repository,
      builder: (context, _) {
        final user = repository.currentUser;
        if (user == null) {
          if (!repository.isInitialized && repository.errorMessage == null) {
            return Scaffold(
              appBar: AppBar(title: Text('Tài khoản')),
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return AccountCredentialsDialog(
            repository: repository,
            fullScreen: true,
          );
        }
        return _buildPage(context, user);
      },
    );
  }

  Widget _buildPage(BuildContext context, AccountUser? user) {
    final colors = Theme.of(context).colorScheme;
    final isSignedIn = user != null;
    final supportsChannelManagement =
        kIsWeb || defaultTargetPlatform == TargetPlatform.android;

    Future<void> openChannelManager() async {
      if (repository.currentUser == null) {
        await showDialog<void>(
          context: context,
          builder: (context) =>
              AccountCredentialsDialog(repository: repository),
        );
        if (repository.currentUser == null || !context.mounted) return;
      }
      if (!context.mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => ChannelManagementScreen(
            accountRepository: repository,
            apiClient: apiClient,
            onManagedVideoAvailable: onManagedVideoAvailable,
            onVideosLoaded: onVideosLoaded,
            onVideoDeleted: onVideoDeleted,
          ),
        ),
      );
    }

    Future<void> openCredentials({bool createAccount = false}) async {
      await showDialog<void>(
        context: context,
        builder: (context) => AccountCredentialsDialog(
          repository: repository,
          createAccount: createAccount,
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Tài khoản')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (isSignedIn)
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          _AccountAvatar(user: user, radius: 48),
                          const SizedBox(height: 16),
                          Text(
                            user.displayName.isEmpty
                                ? user.email
                                : user.displayName,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            user.email,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: colors.onSurfaceVariant),
                          ),
                          const SizedBox(height: 20),
                          const Divider(),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              backgroundColor: colors.primaryContainer,
                              child: Icon(
                                Icons.play_arrow_rounded,
                                color: colors.primary,
                              ),
                            ),
                            title: const Text(
                              'Kênh của tôi',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            subtitle: const Text(
                              'Thông tin kênh, mô tả và video đã đăng',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: supportsChannelManagement
                                ? openChannelManager
                                : null,
                          ),
                          if (supportsChannelManagement)
                            Align(
                              alignment: Alignment.centerRight,
                              child: FilledButton.tonalIcon(
                                onPressed: openChannelManager,
                                icon: const Icon(Icons.open_in_new),
                                label: const Text('Xem kênh'),
                              ),
                            ),
                        ],
                      ),
                    ),
                  )
                else ...[
                  const SizedBox(height: 48),
                  Center(
                    child: Column(
                      children: [
                        _AccountAvatar(user: user, radius: 44),
                        const SizedBox(height: 20),
                        Text(
                          'Bạn chưa đăng nhập',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Đăng nhập bằng email và mật khẩu để xem thông tin tài khoản.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                        const SizedBox(height: 24),
                        if (!repository.isInitialized &&
                            repository.errorMessage == null)
                          const CircularProgressIndicator()
                        else if (repository.isInitialized) ...[
                          FilledButton.icon(
                            onPressed: repository.isSigningIn
                                ? null
                                : () => openCredentials(),
                            icon: const Icon(Icons.login),
                            label: const Text('Đăng nhập bằng email'),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: repository.isSigningIn
                                ? null
                                : () => openCredentials(createAccount: true),
                            icon: const Icon(Icons.person_add_alt_1),
                            label: const Text('Tạo tài khoản'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                if (repository.errorMessage case final error?) ...[
                  const SizedBox(height: 16),
                  Text(
                    error,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.error),
                  ),
                ],
                if (isSignedIn) ...[
                  const SizedBox(height: 20),
                  Text(
                    'Tài khoản và thư viện được đồng bộ qua máy chủ ứng dụng.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await repository.signOut();
                      if (repository.currentUser == null &&
                          context.mounted &&
                          Navigator.of(context).canPop()) {
                        Navigator.of(context).pop();
                      }
                    },
                    icon: const Icon(Icons.logout),
                    label: const Text('Đăng xuất'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AccountAvatar extends StatelessWidget {
  const _AccountAvatar({required this.user, required this.radius});

  final AccountUser? user;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final name = user?.displayName;
    final initial = name == null || name.isEmpty ? 'Y' : name[0].toUpperCase();
    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFF376A9E),
      foregroundImage: user?.photoUrl == null
          ? null
          : NetworkImage(user!.photoUrl!),
      child: Text(
        initial,
        style: TextStyle(color: Colors.white, fontSize: radius * 0.65),
      ),
    );
  }
}
