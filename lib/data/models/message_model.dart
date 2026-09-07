import 'package:equatable/equatable.dart';

import 'user_model.dart';

class MessageModel extends Equatable {
  final String id;
  final String chatId;
  final String senderId;
  final UserModel? sender;
  final String messageType;
  final String? content;
  final String? mediaId;
  final String? mediaUrl;
  final String? replyToId;
  final String? forwardedFromId;
  final bool isViewOnce;
  final DateTime? viewedAt;
  final bool isEdited;
  final DateTime createdAt;
  final String status; // sent | delivered | read

  const MessageModel({
    required this.id,
    required this.chatId,
    required this.senderId,
    this.sender,
    required this.messageType,
    this.content,
    this.mediaId,
    this.mediaUrl,
    this.replyToId,
    this.forwardedFromId,
    this.isViewOnce = false,
    this.viewedAt,
    this.isEdited = false,
    required this.createdAt,
    this.status = 'sent',
  });

  factory MessageModel.fromJson(Map<String, dynamic> json) {
    return MessageModel(
      id: json['id'] as String,
      chatId: json['chat_id'] as String,
      senderId: json['sender_id'] as String,
      sender: json['sender'] != null
          ? UserModel.fromJson(json['sender'] as Map<String, dynamic>)
          : null,
      messageType: json['message_type'] as String? ?? 'text',
      content: json['content'] as String?,
      mediaId: json['media_id'] as String?,
      mediaUrl: json['media_url'] as String?,
      replyToId: json['reply_to_id'] as String?,
      forwardedFromId: json['forwarded_from_id'] as String?,
      isViewOnce: json['is_view_once'] as bool? ?? false,
      viewedAt: json['viewed_at'] != null
          ? DateTime.tryParse(json['viewed_at'] as String)
          : null,
      isEdited: json['is_edited'] as bool? ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String).toLocal()
          : DateTime.now(),
      status: json['status'] as String? ?? 'sent',
    );
  }

  MessageModel copyWith({
    String? status,
    bool? isViewOnce,
    DateTime? viewedAt,
  }) {
    return MessageModel(
      id: id,
      chatId: chatId,
      senderId: senderId,
      sender: sender,
      messageType: messageType,
      content: content,
      mediaId: mediaId,
      mediaUrl: mediaUrl,
      replyToId: replyToId,
      forwardedFromId: forwardedFromId,
      isViewOnce: isViewOnce ?? this.isViewOnce,
      viewedAt: viewedAt ?? this.viewedAt,
      isEdited: isEdited,
      createdAt: createdAt,
      status: status ?? this.status,
    );
  }

  @override
  List<Object?> get props => [id, chatId, content, createdAt, status, mediaUrl];
}
