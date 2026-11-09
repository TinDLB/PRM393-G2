import 'package:flutter/material.dart';

enum YoutubeDestination { home, subscriptions, you }

class YoutubeNavigation extends StatelessWidget {
  final double width;
  final bool isPhone;
  final YoutubeDestination selected;
  final ValueChanged<YoutubeDestination> onSelected;
  final ValueChanged<String> onCollectionSelected;

  const YoutubeNavigation({
    super.key,
    required this.width,
    this.isPhone = false,
    required this.selected,
    required this.onSelected,
    required this.onCollectionSelected,
  });

  static const _destinations = [
    (YoutubeDestination.home, Icons.home_outlined, Icons.home, 'Trang chủ'),
    (
      YoutubeDestination.subscriptions,
      Icons.subscriptions_outlined,
      Icons.subscriptions,
      'Kênh đăng ký',
    ),
    (YoutubeDestination.you, Icons.person_outline, Icons.person, 'Bạn'),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (isPhone || width < 700) return const SizedBox.shrink();
    if (width < 1100) {
      return NavigationRail(
        selectedIndex: selected.index,
        labelType: NavigationRailLabelType.all,
        onDestinationSelected: (index) =>
            onSelected(YoutubeDestination.values[index]),
        destinations: [
          for (final item in _destinations)
            NavigationRailDestination(
              icon: Icon(item.$2),
              selectedIcon: Icon(item.$3),
              label: Text(item.$4),
            ),
        ],
      );
    }
    return SizedBox(
      width: 232,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
        children: [
          for (final item in _destinations)
            ListTile(
              selected: selected == item.$1,
              selectedTileColor: colors.secondaryContainer,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              leading: Icon(selected == item.$1 ? item.$3 : item.$2),
              title: Text(item.$4),
              onTap: () => onSelected(item.$1),
            ),
          const Divider(height: 28),
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 4, 0, 8),
            child: Text('Bạn', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          for (final label in ['Lịch sử', 'Video đã thích', 'Xem sau'])
            ListTile(
              dense: true,
              leading: Icon(_collectionIcon(label), size: 21),
              title: Text(label),
              onTap: () => onCollectionSelected(label),
            ),
        ],
      ),
    );
  }

  static Widget bottomBar({
    required YoutubeDestination selected,
    required ValueChanged<YoutubeDestination> onSelected,
  }) {
    return NavigationBar(
      height: 64,
      selectedIndex: selected.index,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      onDestinationSelected: (index) =>
          onSelected(YoutubeDestination.values[index]),
      destinations: [
        for (final item in _destinations)
          NavigationDestination(
            icon: Icon(item.$2),
            selectedIcon: Icon(item.$3),
            label: item.$4,
          ),
      ],
    );
  }

  static IconData _collectionIcon(String label) => switch (label) {
    'Lịch sử' => Icons.history,
    'Video đã thích' => Icons.thumb_up_outlined,
    _ => Icons.schedule,
  };
}
