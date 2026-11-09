import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/network/backend_api_client.dart';

class YoutubeVideoThumbnail extends StatefulWidget {
  const YoutubeVideoThumbnail({
    super.key,
    required this.videoId,
    required this.apiClient,
    required this.fallback,
  });

  final String videoId;
  final BackendApiClient apiClient;
  final Widget fallback;

  @override
  State<YoutubeVideoThumbnail> createState() => _YoutubeVideoThumbnailState();
}

class _YoutubeVideoThumbnailState extends State<YoutubeVideoThumbnail> {
  VideoPlayerController? _controller;
  VideoPlayerController? _pendingController;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _loadFrame();
  }

  @override
  void didUpdateWidget(covariant YoutubeVideoThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoId != widget.videoId ||
        oldWidget.apiClient != widget.apiClient) {
      _loadFrame();
    }
  }

  Future<void> _loadFrame() async {
    final generation = ++_loadGeneration;
    final oldController = _controller;
    _controller = null;
    await oldController?.dispose();

    final controller = VideoPlayerController.networkUrl(
      widget.apiClient.uriFor(
        '/api/videos/${Uri.encodeComponent(widget.videoId)}/stream',
      ),
      httpHeaders: widget.apiClient.authenticatedHeaders,
    );
    _pendingController = controller;
    try {
      await controller.initialize();
      if (controller.value.duration > const Duration(milliseconds: 800)) {
        await controller.seekTo(const Duration(milliseconds: 800));
      }
      await controller.pause();
      if (!mounted || generation != _loadGeneration) {
        await controller.dispose();
        return;
      }
      _pendingController = null;
      setState(() => _controller = controller);
    } catch (_) {
      await controller.dispose();
      if (identical(_pendingController, controller)) {
        _pendingController = null;
      }
    }
  }

  @override
  void dispose() {
    _loadGeneration++;
    _controller?.dispose();
    _pendingController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return widget.fallback;
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final videoWidth = controller.value.size.width;
        final videoHeight = controller.value.size.height;
        if (videoWidth <= 0 || videoHeight <= 0) return widget.fallback;

        final videoAspectRatio = videoWidth / videoHeight;
        final boxAspectRatio = constraints.maxWidth / constraints.maxHeight;
        final width = videoAspectRatio > boxAspectRatio
            ? constraints.maxHeight * videoAspectRatio
            : constraints.maxWidth;
        final height = videoAspectRatio > boxAspectRatio
            ? constraints.maxHeight
            : constraints.maxWidth / videoAspectRatio;

        return ClipRect(
          child: Center(
            child: SizedBox(
              width: width,
              height: height,
              child: VideoPlayer(controller),
            ),
          ),
        );
      },
    );
  }
}
