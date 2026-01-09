import 'package:http/http.dart' as http;

import 'auth_service_interface.dart';

class AuthService implements AuthServiceInterface {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  @override
  String? get accessToken => null;
  @override
  Map<String, dynamic>? get userInfo => null;
  @override
  bool get isAuthenticated => false;

  @override
  Future<void> init() async {}
  @override
  Future<bool> signIn() async => throw UnimplementedError();
  @override
  Future<void> signOut() async {}
  @override
  Future<void> fetchUserInfo() async {}
  @override
  Future<void> refreshTokens() async {}
  @override
  Future<http.Response> authenticatedRequest(String method, String endpoint,
          {Map<String, dynamic>? body}) =>
      throw UnimplementedError();
}
