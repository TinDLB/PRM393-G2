import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/network/backend_api_client.dart';
import '../../../../core/storage/local_app_database.dart';
import '../../../account/models/managed_youtube_video.dart';
import '../../../account/presentation/screens/account_screen.dart';
import '../../../account/repository/account_repository.dart';
import '../../models/youtube_video.dart';
import '../../models/youtube_channel.dart';
import '../../repository/backend_youtube_video_repository.dart';
import '../../repository/youtube_video_repository.dart';
import '../../constants/youtube_constants.dart';
import '../widgets/youtube_feed.dart';
import '../widgets/youtube_library_views.dart';
import '../widgets/youtube_navigation.dart';
import '../widgets/youtube_top_bar.dart';
import 'youtube_video_screen.dart';
import 'youtube_channel_screen.dart';

class YoutubeScreen extends StatefulWidget {
  final YoutubeVideoRepository? repository;
  final AccountRepository accountRepository;
  final BackendApiClient apiClient;
  final LocalAppDatabase database;
  final bool isDarkMode;
  final VoidCallback onToggleTheme;

  const YoutubeScreen({
    super.key,
    this.repository,
    required this.accountRepository,
    required this.apiClient,
    required this.database,
    this.isDarkMode = false,
    this.onToggleTheme = _doNothing,
  });

  static void _doNothing() {}

  @override
  State<YoutubeScreen> createState() => _YoutubeScreenState();
}

class _YoutubeScreenState extends State<YoutubeScreen> {
  late final YoutubeVideoRepository _repository =
      widget.repository ?? BackendYoutubeVideoRepository(widget.apiClient);
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _likedVideoIds = {};
  final Set<String> _savedVideoIds = {};
  final Set<String> _subscribedChannels = {};
  final List<String> _historyVideoIds = [];
  final Map<String, YoutubeVideo> _videoCache = {};
  final Map<String, String> _channelIdsByName = {};

  List<YoutubeVideo> _videos = [];
  List<YoutubeVideo> _selectedLibraryVideos = [];
  List<YoutubeChannel> _subscribedChannelsForView = [];
  bool _isLoadingSubscriptions = false;
  bool _hasLoadedLibrary = false;
  bool _isLoading = true;
  String? _loadError;
  String? _lastAccountId;

  YoutubeDestination _destination = YoutubeDestination.home;
  String _selectedCategory = youtubeCategories.first;
  String _selectedCollection = 'Lịch sử';
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    widget.accountRepository.addListener(_onAccountChanged);
    _initialize();
  }

  void _onAccountChanged() {
    final userId = widget.accountRepository.currentUser?.id;
    if (userId == _lastAccountId) return;
    _lastAccountId = userId;
    if (mounted) setState(() {});
    if (userId == null) {
      _likedVideoIds.clear();
      _savedVideoIds.clear();
      _subscribedChannels.clear();
      _historyVideoIds.clear();
      _selectedLibraryVideos.clear();
      _subscribedChannelsForView.clear();
      _hasLoadedLibrary = false;
    } else {
      _loadSelectedLibrary();
    }
  }

  void _onSearchChanged(String value) {
    _searchQuery = value.trim();
    if (_searchController.value.composing.isCollapsed && mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _searchController.dispose();
    widget.accountRepository.removeListener(_onAccountChanged);
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      _likedVideoIds.addAll(widget.database.likedVideoIds);
      _savedVideoIds.addAll(widget.database.savedVideoIds);
      _subscribedChannels.addAll(widget.database.subscribedChannels);
      _historyVideoIds
        ..clear()
        ..addAll(widget.database.historyVideoIds);
      for (final record in widget.database.cachedVideos) {
        final video = YoutubeVideo.fromJson(record);
        _videoCache[video.videoId] = video;
      }
      if (mounted) {
        setState(() => _videos = _videoCache.values.toList());
      }
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'youtube library',
          context: ErrorDescription('while loading local library data'),
        ),
      );
    }
    await _loadPopular();
  }

  Future<void> _loadPopular({String? category}) async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      final selectedCategory = category ?? _selectedCategory;
      final videos = await _fetchVideos(
        category: selectedCategory,
        query: _searchQuery,
      );
      _rememberVideos(videos);
      if (mounted) setState(() => _videos = videos);
    } catch (error) {
      if (mounted) setState(() => _loadError = _errorMessage(error));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _errorMessage(Object error) {
    if (error is BackendApiException) return error.message;
    return 'Không thể tải dữ liệu máy chủ. Kiểm tra kết nối rồi thử lại.';
  }

  void _rememberVideos(Iterable<YoutubeVideo> videos) {
    for (final video in videos) {
      final cached = _videoCache[video.videoId];
      _videoCache[video.videoId] = cached?.isPublicUpload == true
          ? video.copyWith(isPublicUpload: true)
          : video;
    }
    unawaited(_persistUserState());
  }

  void _cacheManagedVideo(ManagedYoutubeVideo managed, String channel) {
    _cacheManagedVideos([managed], channel);
  }

  void _cacheManagedVideos(
    Iterable<ManagedYoutubeVideo> managedVideos,
    String channel,
  ) {
    for (final managed in managedVideos) {
      final video = YoutubeVideo(
        title: managed.title,
        channel: channel,
        details: '',
        videoId: managed.id,
        duration: managed.duration,
        category: switch (managed.categoryId) {
          '10' => 'Âm nhạc',
          '20' => 'Trò chơi',
          '25' => 'Tin tức',
          _ => 'Tất cả',
        },
        avatarColor: const Color(0xFFCC2929),
        thumbnailUrlOverride: managed.thumbnailUrl,
        durationSeconds: managed.durationSeconds,
        isPublicUpload: managed.privacyStatus == 'public',
      );
      _videoCache[video.videoId] = video;
    }
    unawaited(_persistUserState());
  }

  void _removeManagedVideo(String videoId) {
    _videoCache.remove(videoId);
    _videos.removeWhere((video) => video.videoId == videoId);
    _selectedLibraryVideos.removeWhere((video) => video.videoId == videoId);
    unawaited(_persistUserState());
  }

  Future<void> _persistUserState() async {
    try {
      await widget.database.saveLibrary(
        likedVideoIds: _likedVideoIds,
        savedVideoIds: _savedVideoIds,
        subscribedChannels: _subscribedChannels,
        historyVideoIds: _historyVideoIds,
        cachedVideos: _videoCache.values.map((video) => video.toJson()),
      );
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'youtube library',
          context: ErrorDescription('while saving local library data'),
        ),
      );
      if (mounted) _showMessage('Không thể lưu dữ liệu trên thiết bị.');
    }
  }

  void _selectDestination(YoutubeDestination destination) {
    setState(() {
      _destination = destination;
      if (destination == YoutubeDestination.home) {
        _searchQuery = '';
        _searchController.clear();
      }
    });
    if (destination == YoutubeDestination.home) {
      _loadPopular();
    } else if (destination == YoutubeDestination.subscriptions) {
      unawaited(_loadSubscriptions());
    } else if (destination == YoutubeDestination.you) {
      unawaited(_loadSelectedLibrary());
    }
  }

  Future<void> _loadSubscriptions() async {
    final repository = _repository;
    if (repository is! BackendYoutubeVideoRepository ||
        widget.accountRepository.currentUser == null) {
      return;
    }
    setState(() => _isLoadingSubscriptions = true);
    try {
      final channels = await repository.fetchSubscribedChannels();
      if (!mounted) return;
      _subscribedChannels
        ..clear()
        ..addAll(channels.map((channel) => channel.name));
      _channelIdsByName
        ..clear()
        ..addEntries(
          channels.map((channel) => MapEntry(channel.name, channel.id)),
        );
      setState(() {
        _subscribedChannelsForView = channels;
        _isLoadingSubscriptions = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _isLoadingSubscriptions = false);
        _showMessage(_errorMessage(error));
      }
    }
  }

  void _openChannel(YoutubeChannel channel) {
    final repository = _repository;
    if (repository is! BackendYoutubeVideoRepository) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => YoutubeChannelScreen(
          initialChannel: channel,
          repository: repository,
          apiClient: widget.apiClient,
          isSubscribed: _subscribedChannels.contains(channel.name),
          onToggleSubscription: () => _toggleSubscription(channel.name),
          savedVideoIds: _savedVideoIds,
          onOpenVideo: _openVideo,
          onSaveVideo: (video) => _toggleVideo(_savedVideoIds, video.videoId),
          onShareVideo: _shareVideo,
        ),
      ),
    );
  }

  void _selectCategory(String category) {
    setState(() => _selectedCategory = category);
    if (_searchQuery.isNotEmpty) {
      _handleSearch(_searchQuery);
    } else {
      _loadPopular(category: category);
    }
  }

  void _openVideo(YoutubeVideo video) {
    final isSignedIn = widget.accountRepository.currentUser != null;
    if (isSignedIn) {
      _historyVideoIds
        ..remove(video.videoId)
        ..insert(0, video.videoId);
    }
    _rememberVideos([video]);
    if (isSignedIn) {
      unawaited(_persistUserState());
      final repository = _repository;
      if (repository is BackendYoutubeVideoRepository) {
        unawaited(_recordView(repository, video.videoId));
      }
    }
    final recommendations = _videoCache.values
        .where((item) => item.videoId != video.videoId)
        .toList();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => YoutubeVideoScreen(
          video: video,
          apiClient: widget.apiClient,
          recommendations: recommendations,
          isLiked: isSignedIn && _likedVideoIds.contains(video.videoId),
          isSaved: isSignedIn && _savedVideoIds.contains(video.videoId),
          isSubscribed:
              isSignedIn && _subscribedChannels.contains(video.channel),
          accountRepository: widget.accountRepository,
          onRequireSignIn: _promptSignIn,
          onLikeChanged: () => _toggleVideo(_likedVideoIds, video.videoId),
          onSavedChanged: () => _toggleVideo(_savedVideoIds, video.videoId),
          onSubscribeChanged: () => _toggleSubscription(video.channel),
          onOpenVideo: _openVideo,
        ),
      ),
    );
  }

  Future<void> _recordView(
    BackendYoutubeVideoRepository repository,
    String videoId,
  ) async {
    try {
      await repository.recordView(videoId);
      if (_selectedCollection == 'Lịch sử') {
        await _loadSelectedLibrary();
      }
    } catch (error) {
      if (mounted) _showMessage(_errorMessage(error));
    }
  }

  void _toggleVideo(Set<String> collection, String videoId) {
    if (!_requireSignedIn()) return;
    final isLikedCollection = identical(collection, _likedVideoIds);
    final wasInCollection = collection.contains(videoId);
    setState(() {
      if (!collection.add(videoId)) collection.remove(videoId);
    });
    final repository = _repository;
    if (repository is BackendYoutubeVideoRepository) {
      unawaited(
        _persistVideoToggle(
          repository,
          videoId,
          isLiked: isLikedCollection,
          previousValue: wasInCollection,
        ),
      );
    } else {
      unawaited(_persistUserState());
    }
  }

  Future<void> _persistVideoToggle(
    BackendYoutubeVideoRepository repository,
    String videoId, {
    required bool isLiked,
    required bool previousValue,
  }) async {
    try {
      if (isLiked) {
        await repository.toggleLike(videoId);
      } else {
        await repository.toggleWatchLater(videoId);
      }
      if (_destination == YoutubeDestination.you) {
        await _loadSelectedLibrary();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        final collection = isLiked ? _likedVideoIds : _savedVideoIds;
        if (previousValue) {
          collection.add(videoId);
        } else {
          collection.remove(videoId);
        }
      });
      _showMessage(_errorMessage(error));
    }
  }

  void _toggleSubscription(String channel) {
    if (!_requireSignedIn()) return;
    final channelId = _channelIdsByName[channel];
    final wasSubscribed = _subscribedChannels.contains(channel);
    setState(() {
      if (!_subscribedChannels.add(channel)) {
        _subscribedChannels.remove(channel);
      }
    });
    final repository = _repository;
    if (repository is BackendYoutubeVideoRepository && channelId != null) {
      unawaited(
        _persistSubscriptionToggle(
          repository,
          channelId,
          channel,
          wasSubscribed,
        ),
      );
    }
  }

  Future<void> _persistSubscriptionToggle(
    BackendYoutubeVideoRepository repository,
    String channelId,
    String channelName,
    bool wasSubscribed,
  ) async {
    try {
      await repository.toggleSubscription(channelId);
      if (_destination == YoutubeDestination.subscriptions) {
        await _loadSubscriptions();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        if (wasSubscribed) {
          _subscribedChannels.add(channelName);
        } else {
          _subscribedChannels.remove(channelName);
        }
      });
      _showMessage(_errorMessage(error));
    }
  }

  void _selectCollection(String collection) {
    setState(() {
      _destination = YoutubeDestination.you;
      _selectedCollection = collection;
      _hasLoadedLibrary = false;
      _selectedLibraryVideos = [];
    });
    unawaited(_loadSelectedLibrary());
  }

  void _openVideoUrl(String url) {
    final parsed = Uri.tryParse(url.trim());
    final videoId = parsed == null || parsed.pathSegments.isEmpty
        ? null
        : parsed.pathSegments.last;
    if (videoId == null || videoId.isEmpty || videoId.contains('.')) {
      _showMessage('Đường liên kết video không hợp lệ.');
      return;
    }
    final video = _videoCache.values.firstWhere(
      (item) => item.videoId == videoId,
      orElse: () => YoutubeVideo(
        title: 'Video YouTube',
        channel: 'YouTube',
        details: '',
        videoId: videoId,
        duration: '',
        category: 'Tất cả',
        avatarColor: const Color(0xFFFF0033),
      ),
    );
    _openVideo(video);
  }

  Future<void> _handleSearch(String value) async {
    final query = value.trim();
    if (query.startsWith('https://') || query.startsWith('http://')) {
      _openVideoUrl(query);
      return;
    }
    if (query.isEmpty) {
      setState(() => _searchQuery = '');
      await _loadPopular();
      return;
    }
    setState(() {
      _searchQuery = query;
      _destination = YoutubeDestination.home;
      _isLoading = true;
      _loadError = null;
    });
    try {
      final videos = await _fetchVideos(
        query: query,
        category: _selectedCategory,
      );
      _rememberVideos(videos);
      if (mounted) setState(() => _videos = videos);
    } catch (error) {
      if (mounted) setState(() => _loadError = _errorMessage(error));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<List<YoutubeVideo>> _fetchVideos({
    String? category,
    String query = '',
  }) async {
    final repository = _repository;
    if (repository is BackendYoutubeVideoRepository) {
      final items = await repository.fetchVideos(
        category: category,
        query: query,
      );
      for (final item in items) {
        final video = item.video;
        if (item.channelId case final id?) {
          _channelIdsByName[video.channel] = id;
        }
        if (item.isLiked) {
          _likedVideoIds.add(video.videoId);
        } else {
          _likedVideoIds.remove(video.videoId);
        }
        if (item.isSaved) {
          _savedVideoIds.add(video.videoId);
        } else {
          _savedVideoIds.remove(video.videoId);
        }
        if (item.isSubscribed) {
          _subscribedChannels.add(video.channel);
        } else {
          _subscribedChannels.remove(video.channel);
        }
      }
      return items.map((item) => item.video).toList();
    }
    return query.isEmpty
        ? repository.fetchPopular(category: category)
        : repository.searchVideos(query, category: category);
  }

  Future<void> _loadSelectedLibrary() async {
    final repository = _repository;
    if (repository is! BackendYoutubeVideoRepository ||
        widget.accountRepository.currentUser == null) {
      return;
    }
    try {
      final collection = switch (_selectedCollection) {
        'Video đã thích' => YoutubeLibraryCollection.liked,
        'Xem sau' => YoutubeLibraryCollection.watchLater,
        _ => YoutubeLibraryCollection.history,
      };
      final items = await repository.fetchLibrary(collection);
      if (!mounted) return;
      for (final item in items) {
        if (item.channelId case final id?) {
          _channelIdsByName[item.video.channel] = id;
        }
      }
      setState(() {
        _selectedLibraryVideos = items.map((item) => item.video).toList();
        _hasLoadedLibrary = true;
      });
    } catch (error) {
      if (mounted) _showMessage(_errorMessage(error));
    }
  }

  Future<void> _showPhoneSearch() async {
    _urlController
      ..text = _searchQuery
      ..selection = TextSelection.collapsed(offset: _searchQuery.length);
    final query = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tìm kiếm YouTube'),
        content: TextField(
          controller: _urlController,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Tìm video hoặc dán đường liên kết',
            prefixIcon: Icon(Icons.search),
          ),
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _urlController.text.trim()),
            child: const Text('Tìm kiếm'),
          ),
        ],
      ),
    );
    if (query != null && mounted) await _handleSearch(query);
  }

  Future<void> _showUrlSearch() async {
    _urlController.clear();
    final url = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Phát video YouTube'),
        content: TextField(
          controller: _urlController,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            hintText: 'Dán đường liên kết video',
            prefixIcon: Icon(Icons.link),
          ),
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _urlController.text.trim()),
            child: const Text('Phát'),
          ),
        ],
      ),
    );

    if (url != null && url.isNotEmpty && mounted) {
      _openVideoUrl(url);
    }
  }

  Future<void> _shareVideo(YoutubeVideo video) async {
    final link = widget.apiClient.uriFor('/api/videos/${video.videoId}');
    await Clipboard.setData(ClipboardData(text: link.toString()));
    if (mounted) _showMessage('Đã sao chép đường liên kết video.');
  }

  Future<void> _openNotifications() async {
    if (!_requireSignedIn()) return;
    try {
      final response = await widget.apiClient.get('/api/notifications');
      final notifications = response['items'];
      if (notifications is! List) {
        throw const FormatException('Danh sách thông báo không hợp lệ.');
      }
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Thông báo'),
          content: SizedBox(
            width: 440,
            child: notifications.isEmpty
                ? const Text('Bạn chưa có thông báo.')
                : ListView(
                    shrinkWrap: true,
                    children: [
                      for (final item in notifications)
                        if (item is Map<String, dynamic>)
                          ListTile(
                            title: Text(item['message'] as String? ?? ''),
                            subtitle: Text(item['createdAt'] as String? ?? ''),
                            leading: Icon(
                              item['isRead'] == true
                                  ? Icons.notifications_none
                                  : Icons.notifications_active_outlined,
                            ),
                            onTap: () async {
                              final id = item['notificationId']?.toString();
                              if (id == null) return;
                              await widget.apiClient.post(
                                '/api/notifications/$id/read',
                              );
                            },
                          ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Đóng'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) _showMessage(_errorMessage(error));
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  bool _requireSignedIn() {
    if (widget.accountRepository.currentUser != null) return true;
    _promptSignIn();
    return false;
  }

  void _promptSignIn() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text(
            'Đăng nhập để lưu lịch sử, lượt thích và kênh đăng ký.',
          ),
          action: SnackBarAction(label: 'Đăng nhập', onPressed: _openAccount),
        ),
      );
  }

  void _openAccount() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => AccountScreen(
          repository: widget.accountRepository,
          apiClient: widget.apiClient,
          onManagedVideoAvailable: _cacheManagedVideo,
          onVideosLoaded: _cacheManagedVideos,
          onVideoDeleted: _removeManagedVideo,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isPhone =
            constraints.maxWidth < 700 || constraints.maxHeight < 500;
        return Scaffold(
          appBar: YoutubeTopBar(
            isPhone: isPhone,
            isDarkMode: widget.isDarkMode,
            onToggleTheme: widget.onToggleTheme,
            onHome: () => _selectDestination(YoutubeDestination.home),
            accountName: widget.accountRepository.currentUser?.displayName,
            accountPhotoUrl: widget.accountRepository.currentUser?.photoUrl,
            searchController: _searchController,
            onSearchChanged: _onSearchChanged,
            onSearchSubmitted: _handleSearch,
            onPhoneSearch: _showPhoneSearch,
            onPasteVideo: _showUrlSearch,
            onNotifications: _openNotifications,
            onAccount: _openAccount,
          ),
          body: Row(
            children: [
              YoutubeNavigation(
                width: constraints.maxWidth,
                isPhone: isPhone,
                selected: _destination,
                onSelected: _selectDestination,
                onCollectionSelected: _selectCollection,
              ),
              Expanded(child: _buildDestination()),
            ],
          ),
          bottomNavigationBar: isPhone
              ? YoutubeNavigation.bottomBar(
                  selected: _destination,
                  onSelected: _selectDestination,
                )
              : null,
        );
      },
    );
  }

  Widget _buildDestination() {
    switch (_destination) {
      case YoutubeDestination.home:
        final videos = _matchingVideos(_videos);
        final savedVideoIds = widget.accountRepository.currentUser == null
            ? const <String>{}
            : _savedVideoIds;
        return YoutubeFeed(
          apiClient: widget.apiClient,
          videos: videos,
          categories: youtubeCategories,
          selectedCategory: _selectedCategory,
          onCategorySelected: _selectCategory,
          showCategories: true,
          heading: null,
          savedVideoIds: savedVideoIds,
          onOpenVideo: _openVideo,
          onSaveVideo: (video) => _toggleVideo(_savedVideoIds, video.videoId),
          onShareVideo: _shareVideo,
          isLoading: _isLoading,
          errorMessage: _loadError,
          emptyMessage: _searchQuery.isNotEmpty
              ? 'Không tìm thấy video phù hợp với nội dung tìm kiếm.'
              : _selectedCategory == youtubeCategories.first
              ? 'Chưa có video công khai. Tải video lên và chọn chế độ Công khai để video xuất hiện ở đây.'
              : 'Chưa có video công khai trong danh mục này.',
          onRetry: () => _loadPopular(),
        );
      case YoutubeDestination.subscriptions:
        if (widget.accountRepository.currentUser == null) {
          return _buildSignInPrompt('Đăng nhập để xem các kênh đã đăng ký.');
        }
        return YoutubeSubscriptionsView(
          channels: _subscribedChannelsForView,
          isLoading: _isLoadingSubscriptions,
          onOpenChannel: _openChannel,
        );
      case YoutubeDestination.you:
        if (widget.accountRepository.currentUser == null) {
          return _buildSignInPrompt(
            'Đăng nhập để xem lịch sử, video đã thích và danh sách Xem sau.',
          );
        }
        return YoutubePersonalView(
          apiClient: widget.apiClient,
          user: widget.accountRepository.currentUser!,
          videos: _matchingVideos(
            _hasLoadedLibrary ? _selectedLibraryVideos : _collectionVideos(),
          ),
          collections: const ['Lịch sử', 'Video đã thích', 'Xem sau'],
          selectedCollection: _selectedCollection,
          onCollectionSelected: (collection) => _selectCollection(collection),
          savedVideoIds: _savedVideoIds,
          onOpenVideo: _openVideo,
          onSaveVideo: (video) => _toggleVideo(_savedVideoIds, video.videoId),
          onShareVideo: _shareVideo,
        );
    }
  }

  Widget _buildSignInPrompt(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.account_circle_outlined, size: 52),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _openAccount,
              icon: const Icon(Icons.login),
              label: const Text('Đăng nhập'),
            ),
          ],
        ),
      ),
    );
  }

  List<YoutubeVideo> _matchingVideos(Iterable<YoutubeVideo> source) {
    var result = source;
    if (_destination == YoutubeDestination.home &&
        _selectedCategory != youtubeCategories.first) {
      result = result.where((video) => video.category == _selectedCategory);
    }
    final query = _searchQuery.toLowerCase();
    if (query.isNotEmpty) {
      result = result.where(
        (video) => '${video.title} ${video.channel} ${video.category}'
            .toLowerCase()
            .contains(query),
      );
    }
    return result.toList();
  }

  Iterable<YoutubeVideo> _collectionVideos() {
    final ids = switch (_selectedCollection) {
      'Video đã thích' => _likedVideoIds,
      'Xem sau' => _savedVideoIds,
      _ => _historyVideoIds.toSet(),
    };
    final matching = _videoCache.values
        .where((video) => ids.contains(video.videoId))
        .toList();
    if (_selectedCollection == 'Lịch sử') {
      matching.sort(
        (first, second) => _historyVideoIds
            .indexOf(first.videoId)
            .compareTo(_historyVideoIds.indexOf(second.videoId)),
      );
    }
    return matching;
  }
}
