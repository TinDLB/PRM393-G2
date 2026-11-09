// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

import '../models/video_metadata.dart';

Future<VideoMetadata?> extractVideoMetadata(Uri uri) async {
  final video = html.VideoElement()
    ..preload = 'auto'
    ..muted = true;
  final videoReady = video.onLoadedMetadata.first;
  video.src = uri.toString();
  html.document.body?.append(video);

  try {
    await videoReady.timeout(const Duration(seconds: 30));
    if (!video.duration.isFinite || video.duration <= 0) return null;

    final targetTime = video.duration > 1 ? 1.0 : video.duration / 2;
    if (targetTime > 0) {
      final seeked = video.onSeeked.first;
      video.currentTime = targetTime;
      await seeked.timeout(const Duration(seconds: 15));
    }

    final sourceWidth = video.videoWidth;
    final sourceHeight = video.videoHeight;
    if (sourceWidth == 0 || sourceHeight == 0) return null;
    final width = sourceWidth > 640 ? 640 : sourceWidth;
    final height = (sourceHeight * width / sourceWidth).round();
    final canvas = html.CanvasElement(width: width, height: height);
    canvas.context2D.drawImageScaled(video, 0, 0, width, height);
    final blob = await canvas.toBlob('image/jpeg', 0.82);
    if (blob.size == 0) return null;
    final reader = html.FileReader();
    final loaded = reader.onLoad.first;
    reader.readAsArrayBuffer(blob);
    await loaded.timeout(const Duration(seconds: 10));
    final buffer = reader.result;
    if (buffer is! ByteBuffer) return null;
    return VideoMetadata(
      durationSeconds: video.duration.round(),
      thumbnailBytes: buffer.asUint8List(),
      thumbnailMimeType: 'image/jpeg',
    );
  } finally {
    video.pause();
    video.removeAttribute('src');
    video.load();
    video.remove();
  }
}
