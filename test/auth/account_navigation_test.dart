import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:secure_messenger/app.dart';
import 'package:secure_messenger/data/services/account_service.dart';
import 'package:secure_messenger/data/services/storage_service.dart';
import 'package:secure_messenger/presentation/providers/auth_provider.dart';
import 'package:secure_messenger/presentation/screens/auth/login_screen.dart';
import 'package:secure_messenger/presentation/screens/auth/register_screen.dart';
import 'package:secure_messenger/presentation/screens/auth/two_factor_screen.dart';
import 'package:secure_messenger/presentation/screens/auth/two_factor_setup_screen.dart';
import 'package:secure_messenger/presentation/screens/home/main_shell.dart';
import 'package:secure_messenger/presentation/screens/settings/account_switcher_screen.dart';

import '../support/messenger_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final storage = TestStorage();
  setUpAll(storage.open);
  setUp(storage.reset);
  tearDownAll(storage.close);

  for (final flow in ['login-2fa', 'register-2fa', 'direct-login']) {
    testWidgets(
      'Add account -> $flow lands on the new chat list without restart',
      (tester) async {
        final requests = <http.Request>[];
        final client = MockClient((request) async {
          requests.add(request);
          final path = request.url.path;
          if (path.endsWith('/chats/')) return jsonResponse({'chats': []});
          if (path.endsWith('/users/online-status') ||
              path.endsWith('/auth/logout'))
            return jsonResponse({'ok': true});
          if (path.endsWith('/auth/register')) {
            return jsonResponse({
              'user_id': 'bob',
              'totp_secret': 'JBSWY3DPEHPK3PXP',
              'totp_uri':
                  'otpauth://totp/SecureMessenger:bob?secret=JBSWY3DPEHPK3PXP',
              'warning': '',
            }, status: 201);
          }
          if (path.endsWith('/auth/login')) {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            if (flow != 'direct-login' && body['totp_code'] == null) {
              return jsonResponse({'error': '2FA required'}, status: 401);
            }
          }
          if (path.endsWith('/auth/login') ||
              path.endsWith('/auth/verify-2fa')) {
            return jsonResponse({
              'user': testUser('bob').toJson(),
              'access_token': 'bob-access',
              'refresh_token': 'bob-refresh',
            });
          }
          throw StateError('Unexpected request: ${request.method} $path');
        });

        await http.runWithClient(() async {
          final auth = AuthNotifier();
          await auth.setLoggedIn(
            testUser('alice'),
            'alice-access',
            'alice-refresh',
          );
          await tester.pumpWidget(
            ProviderScope(
              overrides: [authNotifierProvider.overrideWith((ref) => auth)],
              child: const SecureMessengerApp(),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Settings'));
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Accounts'));
          await tester.tap(find.text('Accounts'));
          await tester.pumpAndSettle();
          expect(find.byType(AccountSwitcherScreen), findsOneWidget);
          await tester.tap(find.text('Add account'));
          await tester.pumpAndSettle();
          expect(find.byType(LoginScreen), findsOneWidget);
          expect(
            find.byType(AccountSwitcherScreen, skipOffstage: false),
            findsNothing,
          );
          expect(StorageService.getUserId(), isNull);
          expect((await AccountService.list()).single.userId, 'alice');
          expect(
            requests
                .firstWhere((r) => r.url.path.endsWith('/auth/logout'))
                .headers['authorization'],
            'Bearer alice-access',
          );

          if (flow == 'register-2fa') {
            await tester.tap(find.text('حساب ندارید؟ ثبت‌نام کنید'));
            await tester.pumpAndSettle();
            expect(find.byType(RegisterScreen), findsOneWidget);
            final fields = find.byType(TextFormField);
            await tester.enterText(fields.at(0), 'Bob');
            await tester.enterText(fields.at(1), 'bob');
            await tester.enterText(fields.at(2), 'bob@example.test');
            await tester.enterText(fields.at(3), 'password-123');
            await tester.ensureVisible(find.text('ثبت‌نام و ادامه'));
            await tester.tap(find.text('ثبت‌نام و ادامه'));
            await tester.pumpAndSettle();
            expect(find.byType(TwoFactorSetupScreen), findsOneWidget);
            await tester.enterText(find.byType(TextField), '123456');
            await tester.ensureVisible(find.text('تأیید و ورود'));
            await tester.tap(find.text('تأیید و ورود'));
          } else {
            await tester.enterText(
              find.byType(TextFormField).at(0),
              'bob@example.test',
            );
            await tester.enterText(
              find.byType(TextFormField).at(1),
              'password-123',
            );
            await tester.tap(find.text('ورود'));
            await tester.pumpAndSettle();
            if (flow == 'login-2fa') {
              expect(find.byType(TwoFactorScreen), findsOneWidget);
              await tester.enterText(find.byType(TextField), '123456');
              await tester.tap(find.text('تأیید'));
            }
          }
          await tester.pumpAndSettle();
          expect(find.byType(MainShell), findsOneWidget);
          expect(find.byType(LoginScreen, skipOffstage: false), findsNothing);
          expect(
            find.byType(TwoFactorScreen, skipOffstage: false),
            findsNothing,
          );
          expect(
            find.byType(TwoFactorSetupScreen, skipOffstage: false),
            findsNothing,
          );
          expect(StorageService.getUserId(), 'bob');
          expect(StorageService.getToken(), 'bob-access');
          expect(await AccountService.activeId(), 'bob');
          expect(
            (await AccountService.list()).map((a) => a.userId),
            containsAll(['alice', 'bob']),
          );
          final container = ProviderScope.containerOf(
            tester.element(find.byType(MainShell)),
          );
          expect(container.read(shellIndexProvider), 0);
          expect(container.read(authNotifierProvider).valueOrNull!.id, 'bob');
          expect(
            tester.state<NavigatorState>(find.byType(Navigator).first).canPop(),
            isFalse,
          );
          expect(
            requests
                .where((r) => r.url.path.endsWith('/chats/'))
                .last
                .headers['authorization'],
            'Bearer bob-access',
          );
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }, () => client);
      },
    );
  }

  testWidgets(
    'Refreshing the same account retains routes and renews account-owned clients',
    (tester) async {
      final tokens = <String?>[];
      final client = MockClient((request) async {
        tokens.add(request.headers['authorization']);
        return request.url.path.endsWith('/chats/')
            ? jsonResponse({'chats': []})
            : jsonResponse({'ok': true});
      });
      await http.runWithClient(() async {
        final auth = AuthNotifier();
        await auth.setLoggedIn(
          testUser('alice'),
          'alice-access',
          'alice-refresh',
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [authNotifierProvider.overrideWith((ref) => auth)],
            child: const SecureMessengerApp(),
          ),
        );
        await tester.pumpAndSettle();
        final navigator = tester.state<NavigatorState>(
          find.byType(Navigator).first,
        );
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Keep this route')),
          ),
        );
        await tester.pumpAndSettle();
        await auth.setLoggedIn(
          testUser('alice'),
          'renewed-access',
          'alice-refresh',
        );
        await tester.pumpAndSettle();
        expect(find.text('Keep this route'), findsOneWidget);
        expect(navigator.canPop(), isTrue);
        expect(tokens.last, 'Bearer renewed-access');
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }, () => client);
    },
  );
}
