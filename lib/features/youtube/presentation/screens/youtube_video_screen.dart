import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/network/backend_api_client.dart';
import '../../../account/repository/account_repository.dart';
import '../../../../theme/app_radii.dart';
import '../../../../theme/app_spacing.dart';
import '../../../../theme/app_text_styles.dart';
import '../../models/youtube_video.dart';
import '../widgets/youtube_player_widget.dart';
import '../widgets/youtube_video_card.dart';

class YoutubeVideoScreen extends StatefulWidget {
  final YoutubeVideo video;
  final String? videoUrl;
  final List<YoutubeVideo> recommendations;
  final bool isLiked;
  final bool isSaved;
  final bool isSubscribed;
  final AccountRepository accountRepository;
  final BackendApiClient apiClient;
  final VoidCallback onRequireSignIn;
  final VoidCallback onLikeChanged;
  final VoidCallback onSavedChanged;
  final VoidCallback onSubscribeChanged;
  final ValueChanged<YoutubeVideo> onOpenVideo;

  const YoutubeVideoScreen({
    super.key,
    required this.video,
    this.videoUrl,
    required this.recommendations,
    required this.isLiked,
    required this.isSaved,
    required this.isSubscribed,
    required this.accountRepository,
    required this.apiClient,
    required this.onRequireSignIn,
    required this.onLikeChanged,
    required this.onSavedChanged,
    required this.onSubscribeChanged,
    required this.onOpenVideo,
  });

  @override
  State<YoutubeVideoScreen> createState() => _YoutubeVideoScreenState();
}

class _YoutubeVideoScreenState extends State<YoutubeVideoScreen> {
  late bool _isLiked = widget.isLiked;
  late bool _isSaved = widget.isSaved;
  late bool _isSubscribed = widget.isSubscribed;

  @override
  void initState() {
    super.initState();
    widget.accountRepository.addListener(_onAccountChanged);
  }

  @override
  void dispose() {
    widget.accountRepository.removeListener(_onAccountChanged);
    super.dispose();
  }

  void _onAccountChanged() {
    if (mounted) setState(() {});
  }

  bool _ensureSignedIn() {
    if (widget.accountRepository.currentUser != null) return true;
    widget.onRequireSignIn();
    return false;
  }

  String get _videoUrl => widget.videoUrl ?? widget.video.url;

  Widget _buildPlayer() => ClipRRect(
    borderRadius: BorderRadius.circular(14),
    child: YoutubePlayerWidget(
      videoId: widget.video.videoId,
      apiClient: widget.apiClient,
    ),
  );

  Widget _buildVideoInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.large),
        Text(widget.video.title, style: AppTextStyles.videoTitle),
        const SizedBox(height: AppSpacing.medium),
        Row(
          children: [
            CircleAvatar(
              backgroundColor: widget.video.avatarColor,
              child: Text(
                widget.video.channel.characters.first.toUpperCase(),
                style: AppTextStyles.channelInitial,
              ),
            ),
            const SizedBox(width: AppSpacing.small),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.video.channel, style: AppTextStyles.channelName),
                  if (widget.video.details.isNotEmpty)
                    Text(
                      widget.video.details,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: AppTextStyles.videoDetails.fontSize,
                      ),
                    ),
                ],
              ),
            ),
            FilledButton(
              onPressed: () {
                if (!_ensureSignedIn()) return;
                setState(() => _isSubscribed = !_isSubscribed);
                widget.onSubscribeChanged();
              },
              child: Text(_isSubscribed ? 'Đã đăng ký' : 'Đăng ký'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.large),
        Wrap(
          spacing: AppSpacing.xSmall,
          runSpacing: AppSpacing.xSmall,
          children: [
            FilledButton.tonalIcon(
              onPressed: () {
                if (!_ensureSignedIn()) return;
                setState(() => _isLiked = !_isLiked);
                widget.onLikeChanged();
              },
              icon: Icon(_isLiked ? Icons.thumb_up : Icons.thumb_up_outlined),
              label: const Text('Thích'),
            ),
            FilledButton.tonalIcon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: _videoUrl));
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Đã sao chép đường liên kết')),
                  );
                }
              },
              icon: const Icon(Icons.share_outlined),
              label: const Text('Chia sẻ'),
            ),
            FilledButton.tonalIcon(
              onPressed: () {
                if (!_ensureSignedIn()) return;
                setState(() => _isSaved = !_isSaved);
                widget.onSavedChanged();
              },
              icon: Icon(
                _isSaved ? Icons.schedule : Icons.watch_later_outlined,
              ),
              label: Text(_isSaved ? 'Đã lưu' : 'Xem sau'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xLarge),
        Container(
          width: double.infinity,
          padding: AppSpacing.cardContent,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: AppRadii.card,
          ),
          child: Text(
            widget.video.details.isEmpty
                ? 'Video YouTube'
                : widget.video.details,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('YouTube', style: AppTextStyles.appBarTitle),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final contentWidth = constraints.maxWidth.clamp(0.0, 1500.0);
          final wide = constraints.maxWidth >= 1050;
          return SingleChildScrollView(
            padding: AppSpacing.page,
            child: Center(
              child: SizedBox(
                width: contentWidth,
                child: wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 7,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [_buildPlayer(), _buildVideoInfo()],
                            ),
                          ),
                          const SizedBox(width: AppSpacing.screenColumn),
                          Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Video đề xuất',
                                  style: AppTextStyles.titleMedium,
                                ),
                                const SizedBox(height: AppSpacing.medium),
                                if (widget.recommendations.isEmpty)
                                  Text(
                                    'Chưa có video nào khác để gợi ý.',
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                                  ),
                                for (final video in widget.recommendations)
                                  YoutubeVideoCard(
                                    video: video,
                                    apiClient: widget.apiClient,
                                    onTap: () => widget.onOpenVideo(video),
                                    isSaved: false,
                                    onSave: () {},
                                    onShare: () {},
                                  ),
                              ],
                            ),
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildPlayer(),
                          _buildVideoInfo(),
                          if (widget.recommendations.isNotEmpty) ...[
                            const Padding(
                              padding: AppSpacing.section,
                              child: Text(
                                'Video đề xuất',
                                style: AppTextStyles.titleMedium,
                              ),
                            ),
                            for (final video in widget.recommendations)
                              YoutubeVideoCard(
                                video: video,
                                apiClient: widget.apiClient,
                                onTap: () => widget.onOpenVideo(video),
                                isSaved: false,
                                onSave: () {},
                                onShare: () {},
                              ),
                          ],
                        ],
                      ),
              ),
            ),
          );
        },
      ),
    );
  }
}
