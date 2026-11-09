import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../../core/network/backend_api_client.dart';
import '../../../youtube/repository/backend_youtube_video_repository.dart';
import '../../../youtube/models/youtube_channel.dart';
import '../../../youtube/presentation/widgets/youtube_video_thumbnail.dart';
import '../../models/managed_youtube_video.dart';
import '../../models/video_metadata.dart';
import '../../repository/account_repository.dart';
import '../../services/video_metadata_extractor.dart';

class ChannelManagementScreen extends StatefulWidget {
  const ChannelManagementScreen({
    super.key,
    required this.accountRepository,
    required this.apiClient,
    this.onManagedVideoAvailable,
    this.onVideosLoaded,
    this.onVideoDeleted,
  });

  final AccountRepository accountRepository;
  final BackendApiClient apiClient;
  final void Function(ManagedYoutubeVideo video, String channel)?
  onManagedVideoAvailable;
  final void Function(List<ManagedYoutubeVideo> videos, String channel)?
  onVideosLoaded;
  final ValueChanged<String>? onVideoDeleted;

  @override
  State<ChannelManagementScreen> createState() =>
      _ChannelManagementScreenState();
}

class _ChannelManagementScreenState extends State<ChannelManagementScreen> {
  late final BackendYoutubeVideoRepository _repository =
      BackendYoutubeVideoRepository(widget.apiClient);
  List<ManagedYoutubeVideo> _videos = [];
  YoutubeChannel? _channel;
  String? _errorMessage;
  bool _isLoading = true;
  bool _isWorking = false;
  double? _uploadProgress;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (!widget.apiClient.isAuthenticated) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Đăng nhập để quản lý video của bạn.';
        });
      }
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final channel = await _repository.fetchMyChannel();
      final videos = await _repository.listMyVideos();
      if (!mounted) return;
      widget.accountRepository.setChannelManagerRole(true);
      widget.onVideosLoaded?.call(videos, 'Kênh của tôi');
      setState(() {
        _channel = channel;
        _videos = videos;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      widget.accountRepository.setChannelManagerRole(false);
      setState(() {
        _errorMessage = _messageFor(error);
        _isLoading = false;
      });
    }
  }

  Future<void> _upload() async {
    final result = await showDialog<_VideoEditorResult>(
      context: context,
      builder: (context) => const _VideoEditorDialog(requireFile: true),
    );
    if (result == null || result.videoFile == null) return;
    setState(() {
      _isWorking = true;
      _errorMessage = null;
    });
    try {
      final fileSize = await result.videoFile!.length();
      if (fileSize == null) {
        throw const BackendApiException(
          'Không thể xác định kích thước tệp video.',
        );
      }
      final uploaded = await _repository.uploadVideo(
        fileStream: result.videoFile!.readAsByteStream(),
        fileSize: fileSize,
        fileName: result.videoFile!.name,
        title: result.title.trim(),
        description: result.description.trim(),
        categoryId: result.categoryId,
        visibility: result.visibility,
        durationSeconds: result.videoMetadata?.durationSeconds ?? 0,
        thumbnailBytes: result.videoMetadata?.thumbnailBytes,
        thumbnailMimeType: result.videoMetadata?.thumbnailMimeType,
        onProgress: (progress) {
          if (mounted) setState(() => _uploadProgress = progress);
        },
      );
      widget.onManagedVideoAvailable?.call(uploaded, 'Kênh của tôi');
      await _refresh();
      if (mounted) _showMessage('Đã tải video lên.');
    } catch (error) {
      if (mounted) setState(() => _errorMessage = _messageFor(error));
    } finally {
      if (mounted) {
        setState(() {
          _isWorking = false;
          _uploadProgress = null;
        });
      }
    }
  }

  Future<void> _edit(ManagedYoutubeVideo video) async {
    final result = await showDialog<_VideoEditorResult>(
      context: context,
      builder: (context) => _VideoEditorDialog(video: video),
    );
    if (result == null) return;
    setState(() {
      _isWorking = true;
      _errorMessage = null;
    });
    try {
      final updated = await _repository.updateVideo(
        video: video,
        title: result.title.trim(),
        description: result.description.trim(),
        categoryId: result.categoryId,
        visibility: result.visibility,
      );
      widget.onManagedVideoAvailable?.call(updated, 'Kênh của tôi');
      if (mounted) {
        setState(() {
          _videos = [
            for (final item in _videos)
              if (item.id == updated.id) updated else item,
          ];
        });
        _showMessage('Đã cập nhật thông tin video.');
      }
    } catch (error) {
      if (mounted) setState(() => _errorMessage = _messageFor(error));
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  Future<void> _editChannel(YoutubeChannel channel) async {
    final nameController = TextEditingController(text: channel.name);
    final descriptionController = TextEditingController(
      text: channel.description,
    );
    final formKey = GlobalKey<FormState>();
    try {
      final result = await showDialog<(String, String)>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Thông tin kênh'),
          content: SizedBox(
            width: 440,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameController,
                    maxLength: 100,
                    decoration: const InputDecoration(
                      labelText: 'Tên kênh',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Nhập tên kênh.'
                        : null,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: descriptionController,
                    maxLength: 2000,
                    maxLines: 4,
                    textAlignVertical: TextAlignVertical.top,
                    decoration: const InputDecoration(
                      labelText: 'Mô tả',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () {
                if (!formKey.currentState!.validate()) return;
                Navigator.pop(context, (
                  nameController.text.trim(),
                  descriptionController.text.trim(),
                ));
              },
              child: const Text('Lưu'),
            ),
          ],
        ),
      );
      if (result == null) return;
      setState(() {
        _isWorking = true;
        _errorMessage = null;
      });
      final updated = await _repository.updateMyChannel(
        channelId: channel.id,
        channelName: result.$1,
        description: result.$2,
      );
      if (!mounted) return;
      setState(() => _channel = updated);
      _showMessage('Đã cập nhật thông tin kênh.');
    } catch (error) {
      if (mounted) setState(() => _errorMessage = _messageFor(error));
    } finally {
      nameController.dispose();
      descriptionController.dispose();
      if (mounted) setState(() => _isWorking = false);
    }
  }

  Future<void> _delete(ManagedYoutubeVideo video) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa video?'),
        content: Text('Video "${video.title}" sẽ bị xóa khỏi ứng dụng.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xóa video'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _isWorking = true;
      _errorMessage = null;
    });
    try {
      await _repository.deleteVideo(video.id);
      widget.onVideoDeleted?.call(video.id);
      if (mounted) {
        setState(() => _videos.removeWhere((item) => item.id == video.id));
        _showMessage('Đã xóa video.');
      }
    } catch (error) {
      if (mounted) setState(() => _errorMessage = _messageFor(error));
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  String _messageFor(Object error) {
    if (error is BackendApiException) return error.message;
    return 'Không thể hoàn tất thao tác. Kiểm tra kết nối máy chủ rồi thử lại.';
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Kênh của tôi')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_channel case final channel?)
              Card(
                clipBehavior: Clip.antiAlias,
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        colors.primaryContainer,
                        colors.surfaceContainerHighest,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 32,
                            backgroundColor: colors.primary,
                            foregroundImage: channel.avatarUrl == null
                                ? null
                                : NetworkImage(channel.avatarUrl!),
                            child: Text(
                              channel.name.isEmpty
                                  ? '?'
                                  : channel.name.characters.first.toUpperCase(),
                              style: TextStyle(
                                color: colors.onPrimary,
                                fontSize: 24,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  channel.name,
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  '${channel.subscriberCount} người đăng ký',
                                  style: TextStyle(
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (channel.description.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(channel.description),
                      ],
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _isWorking
                            ? null
                            : () => _editChannel(channel),
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Chỉnh sửa thông tin kênh'),
                      ),
                    ],
                  ),
                ),
              ),
            if (_errorMessage case final error?) ...[
              const SizedBox(height: 12),
              MaterialBanner(
                content: Text(error),
                leading: Icon(Icons.error_outline, color: colors.error),
                actions: [
                  TextButton(
                    onPressed: _isLoading ? null : _refresh,
                    child: const Text('Thử lại'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Video của tôi',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Tải lại danh sách',
                  onPressed: _isLoading ? null : _refresh,
                  icon: const Icon(Icons.refresh),
                ),
                FilledButton.icon(
                  onPressed: _isWorking || _isLoading ? null : _upload,
                  icon: const Icon(Icons.upload),
                  label: const Text('Đăng video'),
                ),
              ],
            ),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_videos.isEmpty && _errorMessage == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: Text('Bạn chưa đăng video nào.')),
              )
            else
              Card(
                clipBehavior: Clip.antiAlias,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Video')),
                      DataColumn(label: Text('Trạng thái')),
                      DataColumn(label: Text('Thao tác')),
                    ],
                    rows: [
                      for (final video in _videos)
                        DataRow(
                          cells: [
                            DataCell(
                              SizedBox(
                                width: 280,
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 64,
                                      height: 48,
                                      child: video.thumbnailUrl == null
                                          ? YoutubeVideoThumbnail(
                                              videoId: video.id,
                                              apiClient: widget.apiClient,
                                              fallback: const Icon(
                                                Icons.video_library_outlined,
                                              ),
                                            )
                                          : Image.network(
                                              video.thumbnailUrl!,
                                              fit: BoxFit.cover,
                                              errorBuilder:
                                                  (
                                                    context,
                                                    error,
                                                    stackTrace,
                                                  ) => YoutubeVideoThumbnail(
                                                    videoId: video.id,
                                                    apiClient: widget.apiClient,
                                                    fallback: const Icon(
                                                      Icons
                                                          .video_library_outlined,
                                                    ),
                                                  ),
                                            ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            video.title,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          if (video.duration.isNotEmpty)
                                            Text(
                                              video.duration,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall,
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            DataCell(
                              Chip(
                                label: Text(
                                  _visibilityLabel(video.privacyStatus),
                                ),
                              ),
                            ),
                            DataCell(
                              PopupMenuButton<String>(
                                enabled: !_isWorking,
                                tooltip: 'Thao tác với video',
                                onSelected: (action) {
                                  if (action == 'edit') _edit(video);
                                  if (action == 'delete') _delete(video);
                                },
                                itemBuilder: (context) => const [
                                  PopupMenuItem(
                                    value: 'edit',
                                    child: Text('Sửa'),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Xóa'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            if (_isWorking)
              LinearProgressIndicator(value: _uploadProgress, minHeight: 4),
            if (_uploadProgress case final progress?) ...[
              const SizedBox(height: 8),
              Text(
                'Đang tải video: ${(progress * 100).round()}%',
                textAlign: TextAlign.center,
              ),
            ],
            if (widget.accountRepository.currentUser != null) ...[
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: _isWorking
                    ? null
                    : () async {
                        final navigator = Navigator.of(context);
                        await widget.accountRepository.signOut();
                        if (!mounted) return;
                        if (widget.accountRepository.currentUser == null &&
                            navigator.canPop()) {
                          navigator.pop();
                        }
                      },
                icon: const Icon(Icons.logout),
                label: const Text('Đăng xuất'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _visibilityLabel(String visibility) => switch (visibility) {
  'public' => 'Công khai',
  'unlisted' => 'Không công khai',
  _ => 'Riêng tư',
};

String _visibilityDescription(String visibility) => switch (visibility) {
  'public' => 'Mọi người đều xem được; video xuất hiện trên trang chủ và kết quả tìm kiếm.',
  'unlisted' => 'Chỉ người có đường liên kết mới xem được; video không xuất hiện công khai trên trang chủ hay tìm kiếm.',
  _ => 'Chỉ bạn và người quản lý kênh xem được video này.',
};

class _VideoEditorResult {
  const _VideoEditorResult({
    required this.title,
    required this.description,
    required this.categoryId,
    required this.visibility,
    this.videoFile,
    this.videoMetadata,
  });

  final String title;
  final String description;
  final String categoryId;
  final String visibility;
  final PlatformFile? videoFile;
  final VideoMetadata? videoMetadata;
}

class _VideoEditorDialog extends StatefulWidget {
  const _VideoEditorDialog({this.video, this.requireFile = false});

  final ManagedYoutubeVideo? video;
  final bool requireFile;

  @override
  State<_VideoEditorDialog> createState() => _VideoEditorDialogState();
}

class _VideoEditorDialogState extends State<_VideoEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _titleController = TextEditingController(
    text: widget.video?.title ?? '',
  );
  late final _descriptionController = TextEditingController(
    text: widget.video?.description ?? '',
  );
  late String _categoryId = widget.video?.categoryId ?? '1';
  late String _visibility = widget.video?.privacyStatus ?? 'private';
  PlatformFile? _videoFile;
  VideoMetadata? _videoMetadata;
  bool _isExtractingMetadata = false;
  String? _metadataError;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickVideo() async {
    final picked = await FilePicker.pickFile(type: FileType.video);
    if (picked == null) return;
    setState(() {
      _videoFile = picked;
      _videoMetadata = null;
      _metadataError = null;
      _isExtractingMetadata = true;
    });
    try {
      final metadata = await extractVideoMetadata(picked.uri);
      if (!mounted) return;
      setState(() {
        _videoMetadata = metadata;
        if (metadata == null) {
          _metadataError = 'Không đọc được ảnh thu nhỏ/thời lượng trên thiết bị này. Video vẫn có thể tải lên.';
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _metadataError =
            'Không thể tạo ảnh thu nhỏ từ video: $error. Video vẫn có thể tải lên.';
      });
    } finally {
      if (mounted) setState(() => _isExtractingMetadata = false);
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    if (widget.requireFile && _videoFile == null) return;
    Navigator.pop(
      context,
      _VideoEditorResult(
        title: _titleController.text,
        description: _descriptionController.text,
        categoryId: _categoryId,
        visibility: _visibility,
        videoFile: _videoFile,
        videoMetadata: _videoMetadata,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.requireFile ? 'Đăng video' : 'Sửa video'),
    content: SizedBox(
      width: 480,
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.requireFile) ...[
                OutlinedButton.icon(
                  onPressed: _pickVideo,
                  icon: const Icon(Icons.video_file_outlined),
                  label: Text(_videoFile?.name ?? 'Chọn tệp video'),
                ),
                if (_videoFile == null)
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Chọn tệp video để tải lên.'),
                  ),
                if (_isExtractingMetadata) const LinearProgressIndicator(),
                if (_videoMetadata case final metadata?) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Image.memory(
                        metadata.thumbnailBytes,
                        width: 96,
                        height: 54,
                        fit: BoxFit.cover,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Thời lượng: ${_formatDuration(metadata.durationSeconds)}',
                      ),
                    ],
                  ),
                ],
                if (_metadataError case final error?)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      error,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _titleController,
                maxLength: 200,
                decoration: const InputDecoration(
                  labelText: 'Tiêu đề',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Nhập tiêu đề video.'
                    : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _descriptionController,
                maxLength: 5000,
                maxLines: 4,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(
                  labelText: 'Mô tả',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _categoryId,
                decoration: const InputDecoration(
                  labelText: 'Danh mục',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: '1', child: Text('Âm nhạc')),
                  DropdownMenuItem(value: '2', child: Text('Trò chơi')),
                  DropdownMenuItem(value: '3', child: Text('Tin tức')),
                  DropdownMenuItem(value: '4', child: Text('Blog / đời sống')),
                  DropdownMenuItem(value: '5', child: Text('Trực tiếp')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _categoryId = value);
                },
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _visibility,
                decoration: const InputDecoration(
                  labelText: 'Chế độ hiển thị',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'private', child: Text('Riêng tư')),
                  DropdownMenuItem(
                    value: 'unlisted',
                    child: Text('Không công khai'),
                  ),
                  DropdownMenuItem(value: 'public', child: Text('Công khai')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _visibility = value);
                },
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _visibilityDescription(_visibility),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Hủy'),
      ),
      FilledButton(
        onPressed: _isExtractingMetadata ? null : _submit,
        child: Text(widget.requireFile ? 'Đăng video' : 'Lưu thay đổi'),
      ),
    ],
  );
}

String _formatDuration(int seconds) {
  final duration = Duration(seconds: seconds);
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final remainingSeconds = duration.inSeconds
      .remainder(60)
      .toString()
      .padLeft(2, '0');
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:$remainingSeconds';
  }
  return '${duration.inMinutes}:$remainingSeconds';
}
