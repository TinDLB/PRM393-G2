class ManagedYoutubeVideo {
  const ManagedYoutubeVideo({
    required this.id,
    required this.title,
    required this.description,
    required this.privacyStatus,
    required this.categoryId,
    this.thumbnailUrl,
    this.publishedAt,
    this.duration = '',
    this.durationSeconds = 0,
  });

  final String id;
  final String title;
  final String description;
  final String privacyStatus;
  final String categoryId;
  final String? thumbnailUrl;
  final DateTime? publishedAt;
  final String duration;
  final int durationSeconds;
}
