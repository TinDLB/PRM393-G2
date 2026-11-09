import 'package:flutter/material.dart';

class YoutubeTopBar extends StatelessWidget implements PreferredSizeWidget {
  final bool isPhone;
  final bool isDarkMode;
  final VoidCallback onToggleTheme;
  final VoidCallback onHome;
  final String? accountName;
  final String? accountPhotoUrl;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onSearchSubmitted;
  final VoidCallback onPhoneSearch;
  final VoidCallback onPasteVideo;
  final VoidCallback onNotifications;
  final VoidCallback onAccount;

  const YoutubeTopBar({
    super.key,
    required this.isPhone,
    required this.isDarkMode,
    required this.onToggleTheme,
    required this.onHome,
    required this.accountName,
    required this.accountPhotoUrl,
    required this.searchController,
    required this.onSearchChanged,
    required this.onSearchSubmitted,
    required this.onPhoneSearch,
    required this.onPasteVideo,
    required this.onNotifications,
    required this.onAccount,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      titleSpacing: 16,
      title: Row(
        children: [
          InkWell(
            onTap: onHome,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 29,
                    height: 20,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF0033),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 5),
                  const Text(
                    'YouTube',
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
          if (!isPhone) ...[
            const SizedBox(width: 36),
            Expanded(
              child: SizedBox(
                height: 42,
                child: TextField(
                  controller: searchController,
                  textInputAction: TextInputAction.search,
                  onChanged: onSearchChanged,
                  onSubmitted: onSearchSubmitted,
                  decoration: InputDecoration(
                    hintText: 'Tìm kiếm',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 18),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    suffixIcon: IconButton(
                      tooltip: 'Tìm kiếm',
                      onPressed: () => onSearchSubmitted(searchController.text),
                      icon: const Icon(Icons.search),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
      actions: [
        if (isPhone)
          IconButton(
            constraints: const BoxConstraints.tightFor(width: 40, height: 40),
            padding: EdgeInsets.zero,
            tooltip: 'Tìm kiếm',
            onPressed: onPhoneSearch,
            icon: const Icon(Icons.search),
          ),
        if (!isPhone)
          IconButton(
            tooltip: 'Phát video từ đường liên kết',
            onPressed: onPasteVideo,
            icon: const Icon(Icons.video_call_outlined),
          ),
        if (!isPhone)
          IconButton(
            tooltip: 'Thông báo',
            onPressed: onNotifications,
            icon: const Icon(Icons.notifications_none_outlined),
          ),
        IconButton(
          constraints: isPhone
              ? const BoxConstraints.tightFor(width: 40, height: 40)
              : null,
          padding: isPhone ? EdgeInsets.zero : null,
          tooltip: isDarkMode ? 'Bật chế độ sáng' : 'Bật chế độ tối',
          onPressed: onToggleTheme,
          icon: Icon(
            isDarkMode ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
          ),
        ),
        IconButton(
          constraints: isPhone
              ? const BoxConstraints.tightFor(width: 40, height: 40)
              : null,
          padding: isPhone ? EdgeInsets.zero : null,
          tooltip: accountName ?? 'Tài khoản',
          onPressed: onAccount,
          icon: CircleAvatar(
            radius: 15,
            backgroundColor: const Color(0xFF376A9E),
            foregroundImage: accountPhotoUrl == null
                ? null
                : NetworkImage(accountPhotoUrl!),
            child: Text(
              accountName == null || accountName!.isEmpty
                  ? 'Y'
                  : accountName![0].toUpperCase(),
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
        ),
      ],
    );
  }
}
