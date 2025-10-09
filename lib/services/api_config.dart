class ApiConfig {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://backend-server-11f5.onrender.com',
  );

  static String get _baseWithoutTrailingSlash => apiBaseUrl.endsWith('/')
      ? apiBaseUrl.substring(0, apiBaseUrl.length - 1)
      : apiBaseUrl;

  static Uri buildUri(String path, [Map<String, dynamic>? queryParameters]) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final uri = Uri.parse('$_baseWithoutTrailingSlash$normalizedPath');
    if (queryParameters == null || queryParameters.isEmpty) {
      return uri;
    }
    return uri.replace(
      queryParameters: Map.fromEntries(
        queryParameters.entries
            .where((entry) => entry.value != null)
            .map((entry) => MapEntry(entry.key, entry.value.toString())),
      ),
    );
  }
}
