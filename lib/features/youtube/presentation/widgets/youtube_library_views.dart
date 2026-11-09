import 'package:flutter/material.dart';

import '../../../../core/network/backend_api_client.dart';
import '../../../account/models/account_user.dart';
import '../../models/youtube_channel.dart';
import '../../models/youtube_video.dart';
import 'youtube_video_card.dart';

class YoutubeSubscriptionsView extends StatelessWidget {
  final List<YoutubeChannel> channels;
  final bool isLoading;
  final ValueChanged<YoutubeChannel> onOpenChannel;

  const YoutubeSubscriptionsView({
    super.key,
    required this.channels,
    required this.isLoading,
    required this.onOpenChannel,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (channels.isEmpty) {
      return const Center(child: Text('Bạn chưa đăng ký kênh nào.'));
    }
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Kênh đăng ký',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        for (final channel in channels)
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 4,
              ),
              leading: CircleAvatar(
                radius: 24,
                foregroundImage: channel.avatarUrl == null
                    ? null
                    : NetworkImage(channel.avatarUrl!),
                child: Text(
                  channel.name.isEmpty
                      ? '?'
                      : channel.name.characters.first.toUpperCase(),
                ),
              ),
              title: Text(channel.name),
              subtitle: Text('${channel.subscriberCount} người đăng ký'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => onOpenChannel(channel),
            ),
          ),
      ],
    );
  }
}

class YoutubePersonalView extends StatelessWidget {
  final AccountUser user;
  final List<YoutubeVideo> videos;
  final List<String> collections;
  final String selectedCollection;
  final ValueChanged<String> onCollectionSelected;
  final Set<String> savedVideoIds;
  final ValueChanged<YoutubeVideo> onOpenVideo;
  final ValueChanged<YoutubeVideo> onSaveVideo;
  final ValueChanged<YoutubeVideo> onShareVideo;
  final BackendApiClient? apiClient;

  const YoutubePersonalView({
    super.key,
    required this.user,
    required this.videos,
    required this.collections,
    required this.selectedCollection,
    required this.onCollectionSelected,
    required this.savedVideoIds,
    required this.onOpenVideo,
    required this.onSaveVideo,
    required this.onShareVideo,
    this.apiClient,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final displayName = user.displayName.isEmpty
        ? user.email
        : user.displayName;
    final initials = displayName.isEmpty
        ? '?'
        : displayName.characters.first.toUpperCase();
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: Color(0xFF376A9E),
                  foregroundImage: user.photoUrl == null
                      ? null
                      : NetworkImage(user.photoUrl!),
                  child: Text(
                    initials,
                    style: const TextStyle(color: Colors.white, fontSize: 22),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Hoạt động trên thiết bị này',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Wrap(
              spacing: 8,
              children: [
                for (final collection in collections)
                  ChoiceChip(
                    label: Text(collection),
                    selected: selectedCollection == collection,
                    onSelected: (_) => onCollectionSelected(collection),
                  ),
              ],
            ),
          ),
        ),
        if (videos.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: Text('Chưa có video trong mục này')),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: MediaQuery.sizeOf(context).width < 600 ? 1 : 3,
                crossAxisSpacing: 18,
                mainAxisSpacing: 18,
                childAspectRatio: 1.12,
              ),
              delegate: SliverChildBuilderDelegate((context, index) {
                final video = videos[index];
                return YoutubeVideoCard(
                  video: video,
                  apiClient: apiClient,
                  onTap: () => onOpenVideo(video),
                  isSaved: savedVideoIds.contains(video.videoId),
                  onSave: () => onSaveVideo(video),
                  onShare: () => onShareVideo(video),
                );
              }, childCount: videos.length),
            ),
          ),
      ],
    );
  }
}
