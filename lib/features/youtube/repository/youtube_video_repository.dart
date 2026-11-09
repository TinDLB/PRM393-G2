import '../models/youtube_video.dart';

abstract interface class YoutubeVideoRepository {
  Future<List<YoutubeVideo>> fetchPopular({String? category});

  Future<List<YoutubeVideo>> searchVideos(String query, {String? category});
}
