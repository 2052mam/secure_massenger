import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/user_model.dart';
import '../../data/services/api_service.dart';
import '../../data/services/storage_service.dart';
import '../../data/services/account_service.dart';

final authNotifierProvider =
    StateNotifierProvider<AuthNotifier, AsyncValue<UserModel?>>((ref) {
  return AuthNotifier()..checkSession();
});

class AuthNotifier extends StateNotifier<AsyncValue<UserModel?>> {
  AuthNotifier() : super(const AsyncValue.loading());

  Future<void> checkSession() async {
    final token = StorageService.getToken();
    if (token == null || token.isEmpty) {
      state = const AsyncValue.data(null);
      return;
    }
    try {
      ApiService().setToken(token);
      final res = await ApiService().get('/users/me');
      final user = UserModel.fromJson(res);
      state = AsyncValue.data(user);
    } catch (_) {
      await StorageService.clearTokens();
      state = const AsyncValue.data(null);
    }
  }

  Future<void> setLoggedIn(UserModel user, String accessToken, String refreshToken) async {
    await StorageService.saveToken(accessToken);
    await StorageService.saveRefreshToken(refreshToken);
    await StorageService.saveUserId(user.id);
    ApiService().setToken(accessToken);
    await AccountService.save(SavedAccount.fromUser(user, accessToken, refreshToken));
    state = AsyncValue.data(user);
  }

  void setUser(UserModel? user) {
    state = AsyncValue.data(user);
  }

  Future<void> logout() async {
    try {
      await ApiService().post('/auth/logout', {});
    } catch (_) {}
    final uid = StorageService.getUserId();
    if (uid != null) await AccountService.remove(uid);
    await StorageService.clearTokens();
    ApiService().setToken(null);
    state = const AsyncValue.data(null);
  }

  /// خروج از اکانت فعلی بدون پاک کردن لیست اکانت‌های ذخیره‌شده (برای افزودن اکانت جدید)
  Future<void> logoutKeepAccounts() async {
    try {
      await ApiService().post('/auth/logout', {});
    } catch (_) {}
    await StorageService.clearTokens();
    ApiService().setToken(null);
    state = const AsyncValue.data(null);
  }
}
