import 'package:equatable/equatable.dart';

class UserModel extends Equatable {
  final String id;
  final String email;
  final String username;
  final String displayName;
  final String? bio;
  final String? avatarUrl;
  final bool isOnline;
  final DateTime? lastSeen;
  final bool showLastSeen;
  final bool showProfilePhoto;
  final bool showBio;

  const UserModel({
    required this.id,
    required this.email,
    required this.username,
    required this.displayName,
    this.bio,
    this.avatarUrl,
    this.isOnline = false,
    this.lastSeen,
    this.showLastSeen = true,
    this.showProfilePhoto = true,
    this.showBio = true,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String,
      email: json['email'] as String? ?? '',
      username: json['username'] as String,
      displayName: json['display_name'] as String,
      bio: json['bio'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      isOnline: json['is_online'] as bool? ?? false,
      lastSeen: _parseLastSeen(json['last_seen'] as String?),
      showLastSeen: json['show_last_seen'] as bool? ?? true,
      showProfilePhoto: json['show_profile_photo'] as bool? ?? true,
      showBio: json['show_bio'] as bool? ?? true,
    );
  }

  static DateTime? _parseLastSeen(String? value) {
    if (value == null || value.isEmpty) return null;
    // Existing Flask rows were serialized as naive UTC; newer responses use Z.
    final hasZone = RegExp(
      r'(Z|[+-]\d{2}:?\d{2})$',
      caseSensitive: false,
    ).hasMatch(value);
    return DateTime.tryParse(hasZone ? value : '${value}Z')?.toLocal();
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'username': username,
      'display_name': displayName,
      'bio': bio,
      'avatar_url': avatarUrl,
      'is_online': isOnline,
      'last_seen': lastSeen?.toIso8601String(),
      'show_last_seen': showLastSeen,
      'show_profile_photo': showProfilePhoto,
      'show_bio': showBio,
    };
  }

  @override
  List<Object?> get props => [
    id,
    email,
    username,
    displayName,
    bio,
    avatarUrl,
    isOnline,
    lastSeen,
    showLastSeen,
    showProfilePhoto,
    showBio,
  ];
}
