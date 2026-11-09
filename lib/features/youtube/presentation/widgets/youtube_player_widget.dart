import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/network/backend_api_client.dart';

class YoutubePlayerWidget extends StatefulWidget {
  const YoutubePlayerWidget({
    super.key,
    required this.videoId,
    required this.apiClient,
  });

  final String videoId;
  final BackendApiClient apiClient;

  @override
  State<YoutubePlayerWidget> createState() => _YoutubePlayerWidgetState();
}

class _YoutubePlayerWidgetState extends State<YoutubePlayerWidget> {
  VideoPlayerController? _controller;
  Object? _error;
  Timer? _controlsTimer;
  bool _showPlaybackIcon = true;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void didUpdateWidget(covariant YoutubePlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoId != widget.videoId ||
        oldWidget.apiClient != widget.apiClient) {
      _controlsTimer?.cancel();
      _showPlaybackIcon = true;
      _initialize();
    }
  }

  void _togglePlayback(VideoPlayerController controller) {
    final wasPlaying = controller.value.isPlaying;
    if (!wasPlaying) {
      controller.play();
    } else {
      controller.pause();
    }

    _controlsTimer?.cancel();
    setState(() => _showPlaybackIcon = true);
    _controlsTimer = Timer(const Duration(seconds: 1), () {
      if (mounted) setState(() => _showPlaybackIcon = false);
    });
  }

  Future<void> _initialize() async {
    final oldController = _controller;
    _controller = null;
    _error = null;
    await oldController?.dispose();
    final controller = VideoPlayerController.networkUrl(
      widget.apiClient.uriFor(
        '/api/videos/${Uri.encodeComponent(widget.videoId)}/stream',
      ),
      httpHeaders: widget.apiClient.authenticatedHeaders,
    );
    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (error) {
      await controller.dispose();
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  void dispose() {
    _controlsTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ColoredBox(
        color: Colors.black,
        child: Center(
          child: _error != null
              ? const Text(
                  'Không thể phát video từ máy chủ.',
                  style: TextStyle(color: Colors.white),
                )
              : controller == null || !controller.value.isInitialized
              ? const CircularProgressIndicator()
              : AspectRatio(
                  aspectRatio: 16 / 9,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final aspectRatio = controller.value.aspectRatio;
                      var width = constraints.maxWidth;
                      var height = width / aspectRatio;
                      if (height > constraints.maxHeight) {
                        height = constraints.maxHeight;
                        width = height * aspectRatio;
                      }
                      return Stack(
                        alignment: Alignment.bottomCenter,
                        children: [
                          Center(
                            child: SizedBox(
                              width: width,
                              height: height,
                              child: VideoPlayer(controller),
                            ),
                          ),
                          Positioned.fill(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => _togglePlayback(controller),
                            ),
                          ),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            height: 24,
                            child: VideoProgressIndicator(
                              controller,
                              allowScrubbing: true,
                              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                            ),
                          ),
                          Positioned(
                            left: 12,
                            right: 12,
                            bottom: 26,
                            child: IgnorePointer(
                              child: ValueListenableBuilder<VideoPlayerValue>(
                                valueListenable: controller,
                                builder: (context, value, child) => Text(
                                  '${_formatDuration(value.position)} / ${_formatDuration(value.duration)}',
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    shadows: [
                                      Shadow(
                                        color: Colors.black87,
                                        blurRadius: 4,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (_showPlaybackIcon)
                            Center(
                              child: IconButton.filledTonal(
                                tooltip: controller.value.isPlaying
                                    ? 'Tạm dừng'
                                    : 'Phát',
                                onPressed: () => _togglePlayback(controller),
                                icon: Icon(
                                  controller.value.isPlaying
                                      ? Icons.pause
                                      : Icons.play_arrow,
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final seconds = duration.inSeconds;
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final remainingSeconds = seconds % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }
}
