class AuthConfig {
  static const String cognitoDomain =
      'brandotesthh.auth.us-east-1.amazoncognito.com';
  static const String userPoolId = 'us-east-1_Te02uMsxt';
  static const String clientId = '6j2chs8duid9k1ba861hsaqlr';
  static const String apiEndpoint =
      'https://mcssz9g3oc.execute-api.us-east-1.amazonaws.com';

  static const String mobileRedirectUri = 'myapp://callback';
  static const String webRedirectUri = 'http://localhost:8080/callback.html';
  static const String desktopRedirectUri = 'http://localhost:8085/callback';

  static const String mobileLogoutUri = 'myapp://signout';
  static const String webLogoutUri = 'http://localhost:8080';

  static const List<String> scopes = ['openid', 'email', 'profile'];
}
