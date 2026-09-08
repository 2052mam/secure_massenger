import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_messenger/data/services/api_service.dart';
import 'package:secure_messenger/presentation/screens/chat/chat_management_screen.dart';
import 'package:secure_messenger/presentation/screens/chat/create_channel_screen.dart';

class ManagementApi extends ApiService {
  ManagementApi({this.channel = false, this.subscriber = false})
    : super.withToken('alice');
  final bool channel, subscriber;
  final calls = <(String, Map<String, dynamic>)>[];
  final gets = <String>[];
  bool failAdd = false;
  Map<String, dynamic> get person => {
    'id': 'bob',
    'username': 'bob',
    'display_name': 'Bob',
    'role': 'member',
  };
  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? query,
  }) async {
    gets.add(path);
    if (path.endsWith('/info'))
      return {
        'id': 'group',
        'title': 'Our chat',
        'chat_type': channel ? 'channel' : 'group',
        'my_role': subscriber ? 'subscriber' : 'owner',
        'members_count': 2,
        'description': 'Description',
        'is_public': false,
        'permissions': {
          'send_messages': true,
          'send_photos': true,
          'send_view_once_photos': true,
        },
        'capabilities': {
          for (final key in [
            'change_info',
            'invite_users',
            'manage_permissions',
            'promote_members',
            'restrict_members',
          ])
            key: !subscriber,
        },
      };
    if (path.endsWith('/members'))
      return {
        'members': [person],
      };
    if (path == '/chats/')
      return {
        'chats': [
          {'chat_type': 'private', 'other_user': person},
        ],
      };
    if (path == '/users/search')
      return {
        'users': [person],
      };
    return {};
  }

  @override
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body,
  ) async {
    calls.add((path, Map.of(body)));
    if (path.endsWith('/add-member')) {
      if (failAdd)
        throw ApiException(statusCode: 403, message: 'Invitation failed');
      return {'action': body['source'] == 'search' ? 'invited' : 'added'};
    }
    return {'ok': true, 'chat_id': 'group', 'title': 'Our chat'};
  }
}

Widget host(Widget child, {String locale = 'en'}) => MaterialApp(
  locale: Locale(locale),
  supportedLocales: const [Locale('en'), Locale('fa')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  home: child,
);

void main() {
  testWidgets(
    'Group management saves real permissions and does not offer shared clear',
    (tester) async {
      final api = ManagementApi();
      await tester.pumpWidget(
        host(GroupManagementScreen(chatId: 'group', api: api)),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('group-permissions')),
      );
      await tester.tap(find.byKey(const ValueKey('group-permissions')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('permission-send_photos')));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(api.calls.single.$1, '/chats/group/set-permissions');
      expect(api.calls.single.$2['send_photos'], isFalse);
      expect(api.calls.single.$2.containsKey('clear_history_for_all'), isFalse);
    },
  );
  testWidgets(
    'Channel subscriber sees broadcast information, not group controls or member identities',
    (tester) async {
      final api = ManagementApi(channel: true, subscriber: true);
      await tester.pumpWidget(
        host(ChannelManagementScreen(chatId: 'group', api: api)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Channel'), findsOneWidget);
      expect(find.textContaining('broadcast channel'), findsOneWidget);
      expect(find.byKey(const ValueKey('group-permissions')), findsNothing);
      expect(find.byKey(const ValueKey('add-members')), findsNothing);
      expect(api.gets.any((path) => path.endsWith('/members')), isFalse);
      expect(find.text('Bob'), findsNothing);
    },
  );
  testWidgets('A contact can be added after creation', (tester) async {
    final api = ManagementApi();
    await tester.pumpWidget(
      host(AddChatMembersScreen(chatId: 'group', api: api)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(api.calls.single.$1, '/chats/group/add-member');
    expect(api.calls.single.$2, {'user_id': 'bob', 'source': 'chat_list'});
    expect(find.text('Member'), findsOneWidget);
  });
  testWidgets(
    'Search always sends an invite, including an existing chat contact',
    (tester) async {
      final api = ManagementApi();
      await tester.pumpWidget(
        host(AddChatMembersScreen(chatId: 'group', api: api)),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '@bob');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send invite'));
      await tester.pumpAndSettle();
      expect(api.calls.single.$2['source'], 'search');
      expect(find.text('Link sent'), findsOneWidget);
    },
  );
  testWidgets('Failed additions can be retried without claiming success', (
    tester,
  ) async {
    final api = ManagementApi()..failAdd = true;
    await tester.pumpWidget(
      host(AddChatMembersScreen(chatId: 'group', api: api)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('Invitation failed'), findsOneWidget);
    expect(find.text('Member'), findsNothing);
    api.failAdd = false;
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('Member'), findsOneWidget);
  });
  testWidgets(
    'Channel creation defaults to private and explains broadcast behavior',
    (tester) async {
      final api = ManagementApi();
      await tester.pumpWidget(host(CreateChannelScreen(api: api)));
      await tester.pumpAndSettle();
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );
      expect(
        find.textContaining('subscribers cannot send messages'),
        findsOneWidget,
      );
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(find.text('Public username'), findsOneWidget);
    },
  );
  testWidgets('Persian management remains RTL and uses group-only wording', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        GroupManagementScreen(chatId: 'group', api: ManagementApi()),
        locale: 'fa',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('گروه'), findsOneWidget);
    expect(find.text('کانال'), findsNothing);
    expect(
      Directionality.of(tester.element(find.text('گروه'))),
      TextDirection.rtl,
    );
  });
}
