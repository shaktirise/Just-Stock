class SupportConfig {
  static const String _phone = String.fromEnvironment(
    'SUPPORT_WHATSAPP_PHONE',
    defaultValue: '917066844214',
  );

  static const String _message = String.fromEnvironment(
    'SUPPORT_WHATSAPP_MESSAGE',
    defaultValue: 'Hi, I need help with JustStock.',
  );

  static Uri? get whatsappUri => whatsappWebUri;

  static Uri? get whatsappAppUri {
    final normalized = _normalizedPhone;
    if (normalized.isEmpty) return null;
    final message = _trimmedMessage;
    final query = <String, String>{'phone': normalized};
    if (message.isNotEmpty) {
      query['text'] = message;
    }
    return Uri(
      scheme: 'whatsapp',
      host: 'send',
      queryParameters: Map<String, dynamic>.from(query),
    );
  }

  static Uri? get whatsappWebUri {
    final normalized = _normalizedPhone;
    if (normalized.isEmpty) return null;
    final query = <String, String>{'phone': normalized};
    final message = _trimmedMessage;
    if (message.isNotEmpty) {
      query['text'] = message;
    }
    return Uri.https(
      'api.whatsapp.com',
      '/send',
      Map<String, dynamic>.from(query),
    );
  }

  static List<Uri> get whatsappLaunchOrder {
    final uris = <Uri>[];
    final appUri = whatsappAppUri;
    final webUri = whatsappWebUri;
    if (appUri != null) uris.add(appUri);
    if (webUri != null) uris.add(webUri);
    return uris;
  }

  static String get _normalizedPhone => _normalizePhone(_phone);
  static String get _trimmedMessage => _message.trim();

  static String _normalizePhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.startsWith('0') ? digits.substring(1) : digits;
  }
}
