import '../models/video_metadata.dart';
import 'video_metadata_extractor_stub.dart'
    if (dart.library.html) 'video_metadata_extractor_web.dart'
    as platform;

Future<VideoMetadata?> extractVideoMetadata(Uri uri) =>
    platform.extractVideoMetadata(uri);
