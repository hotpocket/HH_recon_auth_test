import 'package:http/http.dart' as http;

abstract class AuthServiceInterface {
  String? get accessToken;
  Map<String, dynamic>? get userInfo;
  bool get isAuthenticated;

  Future<void> init();
  Future<bool> signIn();
  Future<void> signOut();
  Future<void> fetchUserInfo();
  Future<void> refreshTokens();
  Future<http.Response> authenticatedRequest(
    String method,
    String endpoint, {
    Map<String, dynamic>? body,
  });
}
