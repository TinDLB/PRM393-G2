import 'package:flutter/material.dart';

import '../../../../core/network/backend_api_client.dart';
import '../../models/youtube_channel.dart';
import '../../models/youtube_video.dart';
import '../../repository/backend_youtube_video_repository.dart';
import '../widgets/youtube_feed.dart';

class YoutubeChannelScreen extends StatefulWidget {
  const YoutubeChannelScreen({
    super.key,
    required this.initialChannel,
    required this.repository,
    required this.apiClient,
    required this.isSubscribed,
    required this.onToggleSubscription,
    required this.savedVideoIds,
    required this.onOpenVideo,
    required this.onSaveVideo,
    required this.onShareVideo,
  });

  final YoutubeChannel initialChannel;
  final BackendYoutubeVideoRepository repository;
  final BackendApiClient apiClient;
  final bool isSubscribed;
  final VoidCallback onToggleSubscription;
  final Set<String> savedVideoIds;
  final ValueChanged<YoutubeVideo> onOpenVideo;
  final ValueChanged<YoutubeVideo> onSaveVideo;
  final ValueChanged<YoutubeVideo> onShareVideo;

  @override
  State<YoutubeChannelScreen> createState() => _YoutubeChannelScreenState();
}

class _YoutubeChannelScreenState extends State<YoutubeChannelScreen> {
  late YoutubeChannel _channel = widget.initialChannel;
  List<YoutubeVideo> _videos = [];
  bool _isLoading = true;
  String? _errorMessage;
  late bool _isSubscribed = widget.isSubscribed;

  @override
  void initState() {
    super.initState();
    _loadChannel();
  }

  Future<void> _loadChannel() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final channel = await widget.repository.fetchChannel(_channel.id);
      final videos = await widget.repository.fetchChannelVideos(_channel.id);
      if (!mounted) return;
      setState(() {
        _channel = channel;
        _videos = videos.map((item) => item.video).toList(growable: false);
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final channel = _channel;
    final error = _errorMessage;
    return Scaffold(
      appBar: AppBar(title: Text(channel.name)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 34,
                  backgroundColor: colors.primary,
                  foregroundImage: channel.avatarUrl == null
                      ? null
                      : NetworkImage(channel.avatarUrl!),
                  child: Text(
                    channel.name.isEmpty
                        ? '?'
                        : channel.name.characters.first.toUpperCase(),
                    style: TextStyle(color: colors.onPrimary, fontSize: 24),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        channel.name,
                        style: Theme.of(context).textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '${channel.subscriberCount} người đăng ký',
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                      if (channel.description.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(channel.description),
                      ],
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () {
                          setState(() => _isSubscribed = !_isSubscribed);
                          widget.onToggleSubscription();
                        },
                        child: Text(_isSubscribed ? 'Đã đăng ký' : 'Đăng ký'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(error, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: _loadChannel,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Thử lại'),
                        ),
                      ],
                    ),
                  )
                : YoutubeFeed(
                    apiClient: widget.apiClient,
                    videos: _videos,
                    categories: const [],
                    selectedCategory: '',
                    onCategorySelected: (_) {},
                    showCategories: false,
                    heading: null,
                    savedVideoIds: widget.savedVideoIds,
                    onOpenVideo: widget.onOpenVideo,
                    onSaveVideo: widget.onSaveVideo,
                    onShareVideo: widget.onShareVideo,
                    isLoading: _isLoading,
                    emptyMessage: 'Kênh này chưa đăng video công khai.',
                    onRetry: _loadChannel,
                  ),
          ),
        ],
      ),
    );
  }
}
