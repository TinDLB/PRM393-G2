import 'package:flutter/material.dart';

import '../../../../core/network/backend_api_client.dart';
import '../../models/youtube_video.dart';
import 'youtube_video_card.dart';

class YoutubeFeed extends StatelessWidget {
  final List<YoutubeVideo> videos;
  final List<String> categories;
  final String selectedCategory;
  final ValueChanged<String> onCategorySelected;
  final bool showCategories;
  final String? heading;
  final Set<String> savedVideoIds;
  final ValueChanged<YoutubeVideo> onOpenVideo;
  final ValueChanged<YoutubeVideo> onSaveVideo;
  final ValueChanged<YoutubeVideo> onShareVideo;
  final bool isLoading;
  final String? errorMessage;
  final String emptyMessage;
  final VoidCallback? onRetry;
  final BackendApiClient? apiClient;

  const YoutubeFeed({
    super.key,
    required this.videos,
    required this.categories,
    required this.selectedCategory,
    required this.onCategorySelected,
    required this.showCategories,
    required this.savedVideoIds,
    required this.onOpenVideo,
    required this.onSaveVideo,
    required this.onShareVideo,
    this.heading,
    this.isLoading = false,
    this.errorMessage,
    this.emptyMessage = 'Không tìm thấy video.',
    this.onRetry,
    this.apiClient,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final compactLandscape = width >= 700 && constraints.maxHeight < 500;
        final thumbnailHeight =
            (constraints.maxHeight - (showCategories ? 54 : 0) - 40).clamp(
              140.0,
              250.0,
            );
        final columns = compactLandscape
            ? 1
            : width < 600
            ? 1
            : width < 1000
            ? 2
            : width < 1400
            ? 3
            : width < 1800
            ? 4
            : 5;
        return CustomScrollView(
          slivers: [
            if (heading != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
                  child: Text(
                    heading!,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            if (showCategories)
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 54,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    scrollDirection: Axis.horizontal,
                    itemCount: categories.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final category = categories[index];
                      final selected = category == selectedCategory;
                      return ChoiceChip(
                        label: Text(category),
                        selected: selected,
                        showCheckmark: false,
                        onSelected: (_) => onCategorySelected(category),
                        backgroundColor: colors.surfaceContainerHighest,
                        selectedColor: colors.primary,
                        labelStyle: TextStyle(
                          color: selected ? colors.onPrimary : colors.onSurface,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide.none,
                        ),
                      );
                    },
                  ),
                ),
              ),
            if (isLoading && videos.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (errorMessage != null && videos.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.cloud_off_outlined, size: 36),
                        const SizedBox(height: 16),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
                          child: Text(
                            errorMessage!,
                            textAlign: TextAlign.center,
                          ),
                        ),
                        if (onRetry != null) ...[
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: onRetry,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Thử lại'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              )
            else if (videos.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.video_library_outlined,
                          size: 44,
                          color: colors.onSurfaceVariant,
                        ),
                        const SizedBox(height: 12),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 500),
                          child: Text(
                            emptyMessage,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: colors.onSurfaceVariant,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else if (compactLandscape)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                sliver: SliverList(
                  key: const ValueKey('landscape-video-list'),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final video = videos[index];
                    return YoutubeVideoCard(
                      video: video,
                      apiClient: apiClient,
                      compactLandscape: true,
                      thumbnailHeight: thumbnailHeight,
                      onTap: () => onOpenVideo(video),
                      isSaved: savedVideoIds.contains(video.videoId),
                      onSave: () => onSaveVideo(video),
                      onShare: () => onShareVideo(video),
                    );
                  }, childCount: videos.length),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                sliver: SliverGrid(
                  key: ValueKey('video-grid-$columns'),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: 18,
                    mainAxisSpacing: 18,
                    childAspectRatio: columns == 1 ? 0.92 : 1.12,
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
      },
    );
  }
}
