import 'package:flutter/material.dart';

import '../../../../core/network/backend_api_client.dart';
import '../../models/youtube_video.dart';
import 'youtube_video_thumbnail.dart';

class YoutubeVideoCard extends StatelessWidget {
  final YoutubeVideo video;
  final VoidCallback onTap;
  final bool isSaved;
  final bool compactLandscape;
  final double thumbnailHeight;
  final VoidCallback onSave;
  final VoidCallback onShare;
  final BackendApiClient? apiClient;

  const YoutubeVideoCard({
    super.key,
    required this.video,
    required this.onTap,
    required this.isSaved,
    required this.onSave,
    required this.onShare,
    this.apiClient,
    this.compactLandscape = false,
    this.thumbnailHeight = 200,
  });

  @override
  Widget build(BuildContext context) {
    if (compactLandscape) {
      return SizedBox(
        height: thumbnailHeight,
        child: Row(
          children: [
            AspectRatio(aspectRatio: 16 / 9, child: _buildThumbnail(context)),
            const SizedBox(width: 14),
            Expanded(child: _buildDetails(context)),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(aspectRatio: 16 / 9, child: _buildThumbnail(context)),
        _buildDetails(context),
      ],
    );
  }

  Widget _buildThumbnail(BuildContext context) {
    return Material(
      key: ValueKey('video-thumbnail-${video.videoId}'),
      color: const Color(0xFF202020),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (video.thumbnailUrl.isEmpty)
              _buildVideoFrameFallback(context)
            else
              Image.network(
                video.thumbnailUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    _buildVideoFrameFallback(context),
              ),
            if (video.duration.isNotEmpty)
              Positioned(
                right: 8,
                bottom: 8,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    child: Text(
                      video.duration,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoFrameFallback(BuildContext context) {
    final apiClient = this.apiClient;
    if (apiClient == null || int.tryParse(video.videoId) == null) {
      return _buildThumbnailFallback(context);
    }
    return YoutubeVideoThumbnail(
      videoId: video.videoId,
      apiClient: apiClient,
      fallback: _buildThumbnailFallback(context),
    );
  }

  Widget _buildThumbnailFallback(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colors.primary.withValues(alpha: 0.72),
            colors.tertiary.withValues(alpha: 0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            right: 16,
            top: 8,
            child: Text(
              video.channel.characters.first.toUpperCase(),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.18),
                fontSize: 112,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Center(
            child: Icon(
              Icons.play_circle_outline,
              color: Colors.white.withValues(alpha: 0.9),
              size: 52,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetails(BuildContext context) {
    if (compactLandscape) {
      return Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: video.avatarColor,
            child: Text(
              video.channel.characters.first.toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: InkWell(
              onTap: onTap,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    video.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${video.channel} · ${video.details}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Tùy chọn video',
            onSelected: (value) => value == 'save' ? onSave() : onShare(),
            itemBuilder: _menuItems,
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(Icons.more_vert, size: 21),
            ),
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 10, 0, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: video.avatarColor,
            child: Text(
              video.channel.characters.first.toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      video.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${video.channel} · ${video.details}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Tùy chọn video',
            onSelected: (value) => value == 'save' ? onSave() : onShare(),
            itemBuilder: _menuItems,
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(Icons.more_vert, size: 21),
            ),
          ),
        ],
      ),
    );
  }

  List<PopupMenuEntry<String>> _menuItems(BuildContext context) => [
    PopupMenuItem(
      value: 'save',
      child: Row(
        children: [
          Icon(isSaved ? Icons.schedule : Icons.watch_later_outlined),
          const SizedBox(width: 12),
          Text(isSaved ? 'Xóa khỏi Xem sau' : 'Lưu vào Xem sau'),
        ],
      ),
    ),
    const PopupMenuItem(
      value: 'share',
      child: Row(
        children: [
          Icon(Icons.share_outlined),
          SizedBox(width: 12),
          Text('Chia sẻ'),
        ],
      ),
    ),
  ];
}
