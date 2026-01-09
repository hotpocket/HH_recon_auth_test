import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import 'auth_service_interface.dart';

class AuthService implements AuthServiceInterface {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  String? _accessToken;
  String? _idToken;
  String? _refreshToken;
  Map<String, dynamic>? _userInfo;

  @override
  String? get accessToken => _accessToken;
  @override
  Map<String, dynamic>? get userInfo => _userInfo;
  @override
  bool get isAuthenticated => _accessToken != null;

  @override
  Future<void> init() async {
    await _loadTokens();
    if (_accessToken != null) {
      await fetchUserInfo();
    }
  }

  Future<void> _loadTokens() async {
    try {
      _accessToken = await _secureStorage.read(key: 'access_token');
      _idToken = await _secureStorage.read(key: 'id_token');
      _refreshToken = await _secureStorage.read(key: 'refresh_token');
    } catch (e) {
      debugPrint('Error loading tokens: $e');
    }
  }

  Future<void> _saveTokens(Map<String, dynamic> tokens) async {
    _accessToken = tokens['access_token'];
    _idToken = tokens['id_token'];
    _refreshToken = tokens['refresh_token'];

    await _secureStorage.write(key: 'access_token', value: _accessToken);
    await _secureStorage.write(key: 'id_token', value: _idToken);
    await _secureStorage.write(key: 'refresh_token', value: _refreshToken);
  }

  Future<void> _clearTokens() async {
    _accessToken = null;
    _idToken = null;
    _refreshToken = null;
    _userInfo = null;
    await _secureStorage.deleteAll();
  }

  String _buildAuthUrl() {
    final params = {
      'client_id': AuthConfig.clientId,
      'response_type': 'code',
      'scope': AuthConfig.scopes.join(' '),
      'redirect_uri': AuthConfig.mobileRedirectUri,
      'identity_provider': 'Google',
    };

    final queryString = params.entries
        .map((e) =>
            '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');

    return 'https://${AuthConfig.cognitoDomain}/oauth2/authorize?$queryString';
  }

  @override
  Future<bool> signIn() async {
    try {
      final result = await FlutterWebAuth2.authenticate(
        url: _buildAuthUrl(),
        callbackUrlScheme: 'myapp',
      );

      final uri = Uri.parse(result);
      final code = uri.queryParameters['code'];
      final error = uri.queryParameters['error'];

      if (error != null) throw Exception('Auth error: $error');
      if (code == null) throw Exception('No authorization code');

      await _exchangeCodeForTokens(code);
      await fetchUserInfo();
      return true;
    } catch (e) {
      debugPrint('Sign in error: $e');
      rethrow;
    }
  }

  Future<void> _exchangeCodeForTokens(String code) async {
    final response = await http.post(
      Uri.parse('https://${AuthConfig.cognitoDomain}/oauth2/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'authorization_code',
        'client_id': AuthConfig.clientId,
        'code': code,
        'redirect_uri': AuthConfig.mobileRedirectUri,
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Token exchange failed: ${response.body}');
    }

    final tokens = jsonDecode(response.body) as Map<String, dynamic>;
    await _saveTokens(tokens);
  }

  @override
  Future<void> fetchUserInfo() async {
    if (_accessToken == null) return;

    try {
      final response = await http.get(
        Uri.parse('https://${AuthConfig.cognitoDomain}/oauth2/userInfo'),
        headers: {'Authorization': 'Bearer $_accessToken'},
      );

      if (response.statusCode == 200) {
        _userInfo = jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('Error fetching user info: $e');
    }
  }

  @override
  Future<void> refreshTokens() async {
    if (_refreshToken == null) throw Exception('No refresh token');

    final response = await http.post(
      Uri.parse('https://${AuthConfig.cognitoDomain}/oauth2/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'refresh_token',
        'client_id': AuthConfig.clientId,
        'refresh_token': _refreshToken,
      },
    );

    if (response.statusCode != 200) {
      await _clearTokens();
      throw Exception('Token refresh failed');
    }

    final tokens = jsonDecode(response.body) as Map<String, dynamic>;
    tokens['refresh_token'] ??= _refreshToken;
    await _saveTokens(tokens);
  }

  @override
  Future<http.Response> authenticatedRequest(
    String method,
    String endpoint, {
    Map<String, dynamic>? body,
  }) async {
    if (_accessToken == null) throw Exception('Not authenticated');

    final uri = Uri.parse('${AuthConfig.apiEndpoint}$endpoint');
    final headers = {
      'Authorization': 'Bearer $_accessToken',
      'Content-Type': 'application/json',
    };

    http.Response response;
    switch (method.toUpperCase()) {
      case 'GET':
        response = await http.get(uri, headers: headers);
      case 'POST':
        response =
            await http.post(uri, headers: headers, body: jsonEncode(body));
      case 'PUT':
        response =
            await http.put(uri, headers: headers, body: jsonEncode(body));
      case 'DELETE':
        response = await http.delete(uri, headers: headers);
      default:
        throw Exception('Unsupported method');
    }

    if (response.statusCode == 401) {
      await refreshTokens();
      return authenticatedRequest(method, endpoint, body: body);
    }
    return response;
  }

  @override
  Future<void> signOut() async => _clearTokens();
}
