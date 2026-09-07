import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

class ChatLabels {
  ChatLabels.of(BuildContext context)
    : isFa = Localizations.localeOf(context).languageCode == 'fa';

  final bool isFa;
  String get online => isFa ? 'آنلاین' : 'Online';
  String get lastSeenHidden =>
      isFa ? 'آخرین بازدید پنهان است' : 'Last seen hidden';
  String get profile => isFa ? 'مشاهده پروفایل' : 'View profile';
  String get group => isFa ? 'گروه' : 'Group';
  String get channel => isFa ? 'کانال' : 'Channel';
  String get saved => isFa ? 'پیام‌های ذخیره‌شده' : 'Saved Messages';
  String get reply => isFa ? 'پاسخ' : 'Reply';
  String get forward => isFa ? 'فوروارد' : 'Forward';
  String get copy => isFa ? 'کپی متن' : 'Copy text';
  String get copied => isFa ? 'متن کپی شد' : 'Text copied';
  String get copyFailed => isFa ? 'کپی متن ناموفق بود' : 'Could not copy text';
  String get deleteForMe => isFa ? 'حذف برای من' : 'Delete for me';
  String get deleteForAll => isFa ? 'حذف برای همه' : 'Delete for everyone';
  String get invite => isFa ? 'لینک دعوت' : 'Invite link';
  String get copyLink => isFa ? 'کپی لینک' : 'Copy link';
  String get linkCopied => isFa ? 'لینک کپی شد' : 'Link copied';
  String get joinGroup => isFa ? 'عضویت در گروه' : 'Join group';
  String get joinChannel => isFa ? 'عضویت در کانال' : 'Join channel';
  String get cancel => isFa ? 'لغو' : 'Cancel';
  String get close => isFa ? 'بستن' : 'Close';
  String get inviteUnavailable => isFa
      ? 'لینک دعوت نامعتبر است یا اجازه عضویت ندارید'
      : 'This invite is invalid, unavailable, or you cannot join this chat';
  String get inviteFailed => isFa
      ? 'باز کردن لینک ناموفق بود. دوباره تلاش کنید.'
      : 'Could not open the invite. Please try again.';
  String get chatUnavailable =>
      isFa ? 'این چت دیگر در دسترس نیست' : 'This chat is no longer available';

  String members(int count, {bool subscribers = false}) => isFa
      ? '$count ${subscribers ? 'مشترک' : 'عضو'}'
      : '$count ${subscribers ? (count == 1 ? 'subscriber' : 'subscribers') : (count == 1 ? 'member' : 'members')}';

  String lastSeen(DateTime date) {
    final local = date.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    final time = DateFormat('HH:mm').format(local);
    final String when;
    if (day == today) {
      when = isFa ? 'امروز ساعت $time' : 'today at $time';
    } else if (day == DateTime(now.year, now.month, now.day - 1)) {
      when = isFa ? 'دیروز ساعت $time' : 'yesterday at $time';
    } else {
      when = DateFormat('yyyy/MM/dd HH:mm').format(local);
    }
    return isFa ? 'آخرین بازدید $when' : 'Last seen $when';
  }
}
