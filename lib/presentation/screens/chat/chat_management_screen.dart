import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../data/services/api_service.dart';
import '../../widgets/chat/chat_avatar.dart';

bool _fa(BuildContext context) =>
    Localizations.localeOf(context).languageCode == 'fa';
String _t(BuildContext context, String en, String fa) => _fa(context) ? fa : en;

const _permissionLabels = <String, List<String>>{
  'send_messages': ['Send messages', 'ارسال پیام'],
  'send_photos': ['Send photos', 'ارسال عکس'],
  'send_view_once_photos': ['Send view-once photos', 'ارسال عکس یک‌بارمصرف'],
  'send_videos': ['Send videos', 'ارسال ویدیو'],
  'send_voice': ['Send voice messages', 'ارسال پیام صوتی'],
  'send_files': ['Send files', 'ارسال فایل'],
  'invite_users': ['Add members / invite people', 'افزودن عضو / دعوت افراد'],
  'delete_own_messages': [
    'Delete own messages for everyone',
    'حذف پیام‌های خود برای همه',
  ],
  'delete_messages': ['Delete messages for everyone', 'حذف پیام‌ها برای همه'],
  'pin_messages': ['Pin messages', 'سنجاق کردن پیام‌ها'],
  'change_info': ['Change chat information', 'تغییر اطلاعات'],
  'restrict_members': [
    'Remove members / manage group permissions',
    'حذف اعضا / مدیریت دسترسی گروه',
  ],
  'promote_members': ['Add administrators', 'افزودن مدیر'],
  'post_messages': ['Publish channel posts', 'انتشار پست کانال'],
};
const _adminDefaults = <String, bool>{
  'send_messages': true,
  'send_photos': true,
  'send_view_once_photos': true,
  'send_videos': true,
  'send_voice': true,
  'send_files': true,
  'invite_users': true,
  'delete_messages': true,
  'pin_messages': true,
  'change_info': true,
  'restrict_members': true,
  'post_messages': true,
  'promote_members': false,
};

/// Separate entry points and terminology: groups configure member defaults;
/// channels configure publishing administrators, never subscriber send rights.
class GroupManagementScreen extends StatelessWidget {
  const GroupManagementScreen({
    super.key,
    required this.chatId,
    required this.api,
    this.token,
  });
  final String chatId;
  final ApiService api;
  final String? token;
  @override
  Widget build(BuildContext context) =>
      _ChatManagement(chatId: chatId, api: api, token: token, channel: false);
}

class ChannelManagementScreen extends StatelessWidget {
  const ChannelManagementScreen({
    super.key,
    required this.chatId,
    required this.api,
    this.token,
  });
  final String chatId;
  final ApiService api;
  final String? token;
  @override
  Widget build(BuildContext context) =>
      _ChatManagement(chatId: chatId, api: api, token: token, channel: true);
}

class _ChatManagement extends StatefulWidget {
  const _ChatManagement({
    required this.chatId,
    required this.api,
    required this.channel,
    this.token,
  });
  final String chatId;
  final ApiService api;
  final String? token;
  final bool channel;
  @override
  State<_ChatManagement> createState() => _ChatManagementState();
}

class _ChatManagementState extends State<_ChatManagement> {
  Map<String, dynamic>? _info;
  List<dynamic> _members = [];
  String? _error;
  bool _busy = false;
  bool _loading = true;
  Map<String, dynamic> get _rights =>
      Map<String, dynamic>.from(_info?['capabilities'] as Map? ?? {});
  bool _can(String key) => _rights[key] == true;
  bool get _owner => _info?['my_role'] == 'owner';
  bool get _admin => _owner || _info?['my_role'] == 'admin';
  String get _base => '/chats/${widget.chatId}';
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final info = await widget.api.get('$_base/info');
      final mayList =
          !widget.channel || ['owner', 'admin'].contains(info['my_role']);
      final members = mayList
          ? await widget.api.get('$_base/members')
          : <String, dynamic>{};
      if (!mounted) return;
      setState(() {
        _info = info;
        _members = members['members'] as List? ?? [];
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) await _load();
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _invite() async {
    final res = await widget.api.get('$_base/invite-link');
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_t(context, 'Invite link', 'لینک دعوت')),
        content: SelectableText(
          res['invite_link'] as String,
          textDirection: TextDirection.ltr,
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: res['invite_link'] as String),
              );
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text(_t(context, 'Copy link', 'کپی لینک')),
          ),
        ],
      ),
    );
  }

  Future<void> _edit() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ChatInfoEditor(
          api: widget.api,
          base: _base,
          initial: _info!,
          owner: _owner,
          channel: widget.channel,
        ),
      ),
    );
  }

  Future<void> _permissions() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _PermissionEditor(
          title: _t(context, 'Group permissions', 'دسترسی اعضای گروه'),
          initial: Map<String, bool>.from(_info!['permissions'] as Map),
          onSave: (rights) async {
            await widget.api.post('$_base/set-permissions', rights);
          },
        ),
      ),
    );
  }

  Future<void> _adminRights(Map<String, dynamic> member) async {
    final initial = {
      ..._adminDefaults,
      ...Map<String, bool>.from(member['permissions'] as Map? ?? {}),
    };
    if (!_owner) {
      for (final key in initial.keys.toList()) {
        initial[key] = initial[key]! && _can(key);
      }
    }
    if (widget.channel) initial['send_view_once_photos'] = false;
    // Not applicable to this chat type; do not expose confusing switches.
    final visible = Map<String, bool>.from(initial)
      ..remove(widget.channel ? 'send_view_once_photos' : 'post_messages');
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _PermissionEditor(
          title: _t(context, 'Administrator rights', 'دسترسی مدیر'),
          initial: visible,
          locked: _owner
              ? {}
              : {
                  for (final key in visible.keys)
                    if (!_can(key)) key,
                },
          channel: widget.channel,
          onSave: (rights) async {
            await widget.api.post('$_base/promote', {
              'user_id': member['id'],
              'role': 'admin',
              'permissions': {...initial, ...rights},
            });
          },
        ),
      ),
    );
  }

  Future<bool> _confirm(String title) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(_t(ctx, 'Are you sure?', 'آیا مطمئن هستید؟')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(_t(ctx, 'Cancel', 'لغو')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(_t(ctx, 'Confirm', 'تأیید')),
            ),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final title = widget.channel
        ? _t(context, 'Channel', 'کانال')
        : _t(context, 'Group', 'گروه');
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_busy) const LinearProgressIndicator(),
                    if (_error != null)
                      ListTile(
                        title: Text(_error!),
                        trailing: IconButton(
                          icon: const Icon(Icons.refresh),
                          onPressed: _load,
                        ),
                      ),
                    if (_info != null) ...[
                      Center(
                        child: ChatAvatar(
                          title: _info!['title'] as String? ?? title,
                          url: _info!['avatar_url'] as String?,
                          token: widget.token,
                          radius: 40,
                          fallbackIcon: widget.channel
                              ? Icons.campaign
                              : Icons.group,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _info!['title'] as String? ?? title,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      Text(
                        '${_info!['members_count']} ${widget.channel ? _t(context, 'subscribers', 'مشترک') : _t(context, 'members', 'عضو')}',
                        textAlign: TextAlign.center,
                      ),
                      if (_info!['username'] != null)
                        SelectableText(
                          '@${_info!['username']}',
                          textAlign: TextAlign.center,
                        ),
                      if (_info!['description'] != null)
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(_info!['description'] as String),
                        ),
                      if (widget.channel)
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            _t(
                              context,
                              'A broadcast channel. Only authorized administrators can publish. Posts appear under the channel name.',
                              'کانال انتشار: فقط مدیران مجاز می‌توانند پست منتشر کنند. پست‌ها با نام کانال نمایش داده می‌شوند.',
                            ),
                          ),
                        ),
                      if (_can('change_info'))
                        ListTile(
                          leading: const Icon(Icons.edit_outlined),
                          title: Text(
                            _t(context, 'Edit information', 'ویرایش اطلاعات'),
                          ),
                          onTap: _busy ? null : () => _run(_edit),
                        ),
                      if (!widget.channel && _can('manage_permissions'))
                        ListTile(
                          key: const ValueKey('group-permissions'),
                          leading: const Icon(Icons.security),
                          title: Text(_t(context, 'Permissions', 'دسترسی‌ها')),
                          onTap: _busy ? null : () => _run(_permissions),
                        ),
                      if (_can('invite_users')) ...[
                        ListTile(
                          key: const ValueKey('add-members'),
                          leading: const Icon(Icons.person_add_alt),
                          title: Text(
                            widget.channel
                                ? _t(context, 'Add subscribers', 'افزودن مشترک')
                                : _t(context, 'Add members', 'افزودن اعضا'),
                          ),
                          onTap: _busy
                              ? null
                              : () => _run(() async {
                                  await Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => AddChatMembersScreen(
                                        chatId: widget.chatId,
                                        api: widget.api,
                                        token: widget.token,
                                      ),
                                    ),
                                  );
                                }),
                        ),
                        ListTile(
                          leading: const Icon(Icons.link),
                          title: Text(_t(context, 'Invite link', 'لینک دعوت')),
                          onTap: _busy ? null : () => _run(_invite),
                        ),
                      ],
                      const Divider(),
                      if (!widget.channel || _admin) ...[
                        Text(
                          widget.channel
                              ? _t(
                                  context,
                                  'Administrators & subscribers',
                                  'مدیران و مشترکان',
                                )
                              : _t(
                                  context,
                                  'Members & administrators',
                                  'اعضا و مدیران',
                                ),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        for (final raw in _members)
                          _memberTile(Map<String, dynamic>.from(raw as Map)),
                      ],
                      const Divider(),
                      ListTile(
                        leading: const Icon(Icons.exit_to_app),
                        title: Text(
                          widget.channel
                              ? _t(context, 'Leave channel', 'خروج از کانال')
                              : _t(context, 'Leave group', 'خروج از گروه'),
                        ),
                        onTap: _busy
                            ? null
                            : () => _run(() async {
                                if (await _confirm(
                                  _t(
                                    context,
                                    'Leave this chat?',
                                    'خروج از این گفتگو؟',
                                  ),
                                )) {
                                  await widget.api.post('$_base/leave', {});
                                  if (mounted) Navigator.pop(context);
                                }
                              }),
                      ),
                      if (_owner)
                        ListTile(
                          leading: const Icon(
                            Icons.delete_forever,
                            color: Colors.red,
                          ),
                          title: Text(
                            widget.channel
                                ? _t(
                                    context,
                                    'Delete channel for everyone',
                                    'حذف کانال برای همه',
                                  )
                                : _t(
                                    context,
                                    'Delete group for everyone',
                                    'حذف گروه برای همه',
                                  ),
                          ),
                          onTap: _busy
                              ? null
                              : () => _run(() async {
                                  if (await _confirm(
                                    _t(
                                      context,
                                      'Delete this chat for everyone?',
                                      'حذف گفتگو برای همه؟',
                                    ),
                                  )) {
                                    await widget.api.post('$_base/delete', {
                                      'for_all': true,
                                    });
                                    if (mounted) Navigator.pop(context);
                                  }
                                }),
                        ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }

  Widget _memberTile(Map<String, dynamic> member) {
    final role = member['role'];
    final canEdit =
        role != 'owner' &&
        (_owner || (role != 'admin' && _can('promote_members')));
    final canRemove =
        role != 'owner' &&
        (_owner || (role != 'admin' && _can('restrict_members')));
    return ListTile(
      leading: ChatAvatar(
        title: member['display_name'] as String? ?? '?',
        url: member['avatar_url'] as String?,
        token: widget.token,
      ),
      title: Text(member['display_name'] as String? ?? ''),
      subtitle: Text(
        role == 'owner'
            ? _t(context, 'Owner', 'مالک')
            : role == 'admin'
            ? _t(context, 'Administrator', 'مدیر')
            : widget.channel
            ? _t(context, 'Subscriber', 'مشترک')
            : _t(context, 'Member', 'عضو'),
      ),
      trailing: (!canEdit && !canRemove)
          ? null
          : PopupMenuButton<String>(
              enabled: !_busy,
              onSelected: (action) => _run(() async {
                if (action == 'rights') {
                  await _adminRights(member);
                } else if (await _confirm(
                  action == 'remove'
                      ? _t(context, 'Remove member?', 'حذف عضو؟')
                      : _t(
                          context,
                          'Remove administrator rights?',
                          'حذف دسترسی مدیر؟',
                        ),
                )) {
                  await widget.api.post(
                    '$_base/${action == 'remove' ? 'remove-member' : 'promote'}',
                    {
                      'user_id': member['id'],
                      if (action != 'remove')
                        'role': widget.channel ? 'subscriber' : 'member',
                    },
                  );
                }
              }),
              itemBuilder: (_) => [
                if (canEdit)
                  PopupMenuItem(
                    value: 'rights',
                    child: Text(
                      role == 'admin'
                          ? _t(
                              context,
                              'Edit administrator rights',
                              'ویرایش دسترسی مدیر',
                            )
                          : _t(context, 'Add administrator', 'افزودن مدیر'),
                    ),
                  ),
                if (canEdit && role == 'admin')
                  PopupMenuItem(
                    value: 'demote',
                    child: Text(
                      _t(context, 'Remove administrator', 'حذف مدیر'),
                    ),
                  ),
                if (canRemove)
                  PopupMenuItem(
                    value: 'remove',
                    child: Text(_t(context, 'Remove member', 'حذف عضو')),
                  ),
              ],
            ),
    );
  }
}

class _PermissionEditor extends StatefulWidget {
  const _PermissionEditor({
    required this.title,
    required this.initial,
    required this.onSave,
    this.locked = const {},
    this.channel = false,
  });
  final String title;
  final Map<String, bool> initial;
  final Set<String> locked;
  final bool channel;
  final Future<void> Function(Map<String, bool>) onSave;
  @override
  State<_PermissionEditor> createState() => _PermissionEditorState();
}

class _PermissionEditorState extends State<_PermissionEditor> {
  late final Map<String, bool> _values = Map.of(widget.initial);
  bool _saving = false;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.title),
      actions: [
        TextButton(
          onPressed: _saving
              ? null
              : () async {
                  setState(() => _saving = true);
                  try {
                    await widget.onSave(_values);
                    if (mounted) Navigator.pop(context);
                  } catch (error) {
                    if (mounted)
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text('$error')));
                  } finally {
                    if (mounted) setState(() => _saving = false);
                  }
                },
          child: Text(_t(context, 'Save', 'ذخیره')),
        ),
      ],
    ),
    body: SafeArea(
      child: ListView(
        children: [
          if (_saving) const LinearProgressIndicator(),
          for (final key in _values.keys)
            SwitchListTile(
              key: ValueKey('permission-$key'),
              title: Text(
                key == 'restrict_members' && widget.channel
                    ? _t(context, 'Remove subscribers', 'حذف مشترکان')
                    : (_permissionLabels[key] ?? [key, key])[_fa(context)
                          ? 1
                          : 0],
              ),
              value: _values[key]!,
              onChanged: _saving || widget.locked.contains(key)
                  ? null
                  : (v) => setState(() => _values[key] = v),
            ),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: Text(
              _t(
                context,
                'Clear history for everyone: not allowed',
                'پاک کردن تاریخچه برای همه: غیرمجاز',
              ),
            ),
            subtitle: Text(
              _t(
                context,
                'This right cannot be granted. Only the owner can delete the entire group or channel.',
                'این دسترسی قابل واگذاری نیست. فقط مالک می‌تواند کل گروه یا کانال را حذف کند.',
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class AddChatMembersScreen extends StatefulWidget {
  const AddChatMembersScreen({
    super.key,
    required this.chatId,
    required this.api,
    this.token,
  });
  final String chatId;
  final ApiService api;
  final String? token;
  @override
  State<AddChatMembersScreen> createState() => _AddChatMembersScreenState();
}

class _AddChatMembersScreenState extends State<AddChatMembersScreen> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> _contacts = [], _results = [];
  final Map<String, String> _actions = {};
  bool _loading = true, _searching = false, _sending = false;
  String? _error;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _generation++;
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await widget.api.get('/chats/');
      final users = <String, Map<String, dynamic>>{};
      for (final chat in res['chats'] as List? ?? []) {
        if (chat['chat_type'] == 'private' && chat['other_user'] is Map) {
          final user = Map<String, dynamic>.from(chat['other_user'] as Map);
          users[user['id'] as String] = user;
        }
      }
      if (mounted)
        setState(() {
          _contacts = users.values.toList();
          _error = null;
        });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _find(String query) async {
    final generation = ++_generation;
    if (query.trim().length < 2) {
      setState(() {
        _results = [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    try {
      final res = await widget.api.get(
        '/users/search',
        query: {'q': query.trim()},
      );
      if (mounted && generation == _generation)
        setState(() {
          _results = (res['users'] as List? ?? [])
              .map((u) => Map<String, dynamic>.from(u as Map))
              .toList();
          _error = null;
        });
    } catch (error) {
      if (mounted && generation == _generation)
        setState(() => _error = '$error');
    } finally {
      if (mounted && generation == _generation)
        setState(() => _searching = false);
    }
  }

  Future<void> _add(String id, bool search) async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
      final res = await widget.api.post('/chats/${widget.chatId}/add-member', {
        'user_id': id,
        'source': search ? 'search' : 'chat_list',
      });
      if (mounted)
        setState(() => _actions[id] = res['action'] as String? ?? 'added');
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final searching = _search.text.trim().isNotEmpty;
    final users = searching ? _results : _contacts;
    return Scaffold(
      appBar: AppBar(title: Text(_t(context, 'Add people', 'افزودن افراد'))),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _search,
                onChanged: _find,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  labelText: _t(
                    context,
                    'Search username or ID',
                    'جستجوی نام کاربری یا شناسه',
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                _t(
                  context,
                  'Chat-list contacts are added if their privacy allows it. Search results always receive an invitation link instead.',
                  'افراد فهرست چت در صورت اجازه تنظیمات حریم خصوصی اضافه می‌شوند. برای نتایج جستجو همیشه لینک دعوت ارسال می‌شود.',
                ),
              ),
            ),
            if (_error != null)
              ListTile(
                title: Text(_error!),
                trailing: IconButton(
                  onPressed: searching ? () => _find(_search.text) : _load,
                  icon: const Icon(Icons.refresh),
                ),
              ),
            if (_loading || _searching || _sending)
              const LinearProgressIndicator(),
            Expanded(
              child: users.isEmpty && !_loading && !_searching
                  ? Center(
                      child: Text(
                        _t(context, 'No people found', 'کسی یافت نشد'),
                      ),
                    )
                  : ListView.builder(
                      itemCount: users.length,
                      itemBuilder: (ctx, index) {
                        final user = users[index];
                        final id = user['id'] as String;
                        final action = _actions[id];
                        return ListTile(
                          leading: ChatAvatar(
                            title: user['display_name'] as String? ?? '?',
                            url: user['avatar_url'] as String?,
                            token: widget.token,
                          ),
                          title: Text(user['display_name'] as String? ?? ''),
                          subtitle: Text('@${user['username']}'),
                          trailing: TextButton(
                            onPressed: _sending || action != null
                                ? null
                                : () => _add(id, searching),
                            child: Text(
                              action == 'invited'
                                  ? _t(ctx, 'Link sent', 'لینک ارسال شد')
                                  : action != null
                                  ? _t(ctx, 'Member', 'عضو')
                                  : searching
                                  ? _t(ctx, 'Send invite', 'ارسال دعوت')
                                  : _t(ctx, 'Add', 'افزودن'),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatInfoEditor extends StatefulWidget {
  const _ChatInfoEditor({
    required this.api,
    required this.base,
    required this.initial,
    required this.owner,
    required this.channel,
  });
  final ApiService api;
  final String base;
  final Map<String, dynamic> initial;
  final bool owner, channel;
  @override
  State<_ChatInfoEditor> createState() => _ChatInfoEditorState();
}

class _ChatInfoEditorState extends State<_ChatInfoEditor> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(
    text: widget.initial['title'] as String? ?? '',
  );
  late final _description = TextEditingController(
    text: widget.initial['description'] as String? ?? '',
  );
  late final _username = TextEditingController(
    text: widget.initial['username'] as String? ?? '',
  );
  late bool _public = widget.initial['is_public'] == true;
  bool _saving = false;
  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _username.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.api.post('${widget.base}/update', {
        'title': _title.text.trim(),
        'description': _description.text.trim(),
        if (widget.owner) 'is_public': _public,
        if (widget.owner) 'username': _username.text.trim().toLowerCase(),
      });
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.channel
            ? _t(context, 'Edit channel', 'ویرایش کانال')
            : _t(context, 'Edit group', 'ویرایش گروه'),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : _save,
          child: Text(_t(context, 'Save', 'ذخیره')),
        ),
      ],
    ),
    body: SafeArea(
      child: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (_saving) const LinearProgressIndicator(),
            TextFormField(
              controller: _title,
              enabled: !_saving,
              maxLength: 200,
              decoration: InputDecoration(
                labelText: _t(context, 'Title', 'عنوان'),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? _t(context, 'A title is required', 'عنوان الزامی است')
                  : null,
            ),
            TextFormField(
              controller: _description,
              enabled: !_saving,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: _t(context, 'Description', 'توضیحات'),
              ),
            ),
            if (widget.owner) ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _public,
                title: Text(_t(context, 'Public', 'عمومی')),
                onChanged: _saving ? null : (v) => setState(() => _public = v),
              ),
              TextFormField(
                controller: _username,
                enabled: !_saving,
                decoration: InputDecoration(
                  labelText: _t(context, 'Public username', 'نام کاربری عمومی'),
                  prefixText: '@',
                ),
                validator: (value) {
                  final text = (value ?? '').trim().toLowerCase();
                  return ((!_public && text.isEmpty) ||
                          RegExp(r'^[a-z0-9_]{3,30}$').hasMatch(text))
                      ? null
                      : _t(
                          context,
                          'Use 3–30 letters, numbers or underscores',
                          'از ۳ تا ۳۰ حرف انگلیسی، عدد یا زیرخط استفاده کنید',
                        );
                },
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
