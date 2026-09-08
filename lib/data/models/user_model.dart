import '../../core/utils/api_datetime.dart';
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
  final bool allowGroupAdds;

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
    this.allowGroupAdds = true,
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
      lastSeen: parseApiDateTime(json['last_seen'] as String?),
      showLastSeen: json['show_last_seen'] as bool? ?? true,
      showProfilePhoto: json['show_profile_photo'] as bool? ?? true,
      showBio: json['show_bio'] as bool? ?? true,
      allowGroupAdds: json['allow_group_adds'] as bool? ?? true,
    );
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
      'last_seen': lastSeen?.toUtc().toIso8601String(),
      'show_last_seen': showLastSeen,
      'show_profile_photo': showProfilePhoto,
      'show_bio': showBio,
      'allow_group_adds': allowGroupAdds,
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
    allowGroupAdds,
  ];
}
