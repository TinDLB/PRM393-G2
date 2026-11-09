class YoutubeChannel {
  const YoutubeChannel({
    required this.id,
    required this.name,
    required this.handle,
    required this.description,
    required this.subscriberCount,
    this.avatarUrl,
  });

  final String id;
  final String name;
  final String handle;
  final String description;
  final int subscriberCount;
  final String? avatarUrl;
}
