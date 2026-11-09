import 'package:flutter/material.dart';

class YoutubeVideo {
  final String title;
  final String channel;
  final String details;
  final String videoId;
  final String duration;
  final String category;
  final Color avatarColor;
  final String? thumbnailUrlOverride;
  final int durationSeconds;
  final bool isPublicUpload;

  const YoutubeVideo({
    required this.title,
    required this.channel,
    required this.details,
    required this.videoId,
    required this.duration,
    required this.category,
    required this.avatarColor,
    this.thumbnailUrlOverride,
    this.durationSeconds = 0,
    this.isPublicUpload = false,
  });

  String get url => '/videos/$videoId';
  String get thumbnailUrl => thumbnailUrlOverride ?? '';

  Map<String, Object?> toJson() => {
    'title': title,
    'channel': channel,
    'details': details,
    'videoId': videoId,
    'duration': duration,
    'category': category,
    'avatarColor': avatarColor.toARGB32(),
    'thumbnailUrl': thumbnailUrlOverride,
    'durationSeconds': durationSeconds,
    'isPublicUpload': isPublicUpload,
  };

  factory YoutubeVideo.fromJson(Map<String, Object?> json) => YoutubeVideo(
    title: json['title'] as String? ?? '',
    channel: json['channel'] as String? ?? '',
    details: json['details'] as String? ?? '',
    videoId: json['videoId'] as String? ?? '',
    duration: json['duration'] as String? ?? '',
    category: json['category'] as String? ?? 'Tất cả',
    avatarColor: Color(json['avatarColor'] as int? ?? 0xFFCC2929),
    thumbnailUrlOverride: json['thumbnailUrl'] as String?,
    durationSeconds: json['durationSeconds'] as int? ?? 0,
    isPublicUpload: json['isPublicUpload'] as bool? ?? false,
  );

  YoutubeVideo copyWith({bool? isPublicUpload}) => YoutubeVideo(
    title: title,
    channel: channel,
    details: details,
    videoId: videoId,
    duration: duration,
    category: category,
    avatarColor: avatarColor,
    thumbnailUrlOverride: thumbnailUrlOverride,
    durationSeconds: durationSeconds,
    isPublicUpload: isPublicUpload ?? this.isPublicUpload,
  );
}
