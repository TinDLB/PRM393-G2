import 'dart:typed_data';

class VideoMetadata {
  const VideoMetadata({
    required this.durationSeconds,
    required this.thumbnailBytes,
    required this.thumbnailMimeType,
  });

  final int durationSeconds;
  final Uint8List thumbnailBytes;
  final String thumbnailMimeType;
}
