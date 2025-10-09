import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:newjuststock/services/api_config.dart';

class SegmentMessage {
  final String key;
  final String label;
  final String message;
  final DateTime? updatedAt;
  final String? updatedBy;

  const SegmentMessage({
    required this.key,
    required this.label,
    required this.message,
    this.updatedAt,
    this.updatedBy,
  });

  bool get hasMessage => message.trim().isNotEmpty;

  factory SegmentMessage.fromJson(Map<String, dynamic> json) {
    final key = (json['key'] ?? json['segment'] ?? '').toString();
    final rawLabel = json['label'] ?? json['name'] ?? json['title'] ?? key;
    final label = rawLabel.toString().trim().isEmpty
        ? key.toUpperCase()
        : rawLabel.toString();
    final message = (json['message'] ?? '').toString();
    final updatedAtRaw = json['updatedAt'];
    return SegmentMessage(
      key: key,
      label: label,
      message: message,
      updatedAt: updatedAtRaw is String
          ? DateTime.tryParse(updatedAtRaw)
          : null,
      updatedBy: json['updatedBy']?.toString(),
    );
  }
}

class SegmentFetchResult {
  final Map<String, SegmentMessage> segments;
  final bool unauthorized;

  const SegmentFetchResult({
    required this.segments,
    required this.unauthorized,
  });
}

class SegmentService {
  static Uri _segmentUri(String key) =>
      ApiConfig.buildUri('/api/segments/$key');

  static Future<SegmentFetchResult> fetchSegments(
    Iterable<String> keys, {
    String? token,
  }) async {
    final client = http.Client();
    try {
      final futures = keys
          .map<
            Future<({String key, SegmentMessage? message, bool unauthorized})>
          >((key) async {
            final uri = _segmentUri(key);
            final headers = <String, String>{
              'Accept': 'application/json',
              if (token != null && token.trim().isNotEmpty)
                'Authorization': 'Bearer ${token.trim()}',
            };
            try {
              final response = await client.get(uri, headers: headers);
              final status = response.statusCode;
              if (status == 401 || status == 403) {
                return (key: key, message: null, unauthorized: true);
              }
              if (status >= 200 && status < 300) {
                final body = jsonDecode(response.body) as Map<String, dynamic>;
                return (
                  key: key,
                  message: SegmentMessage.fromJson(body),
                  unauthorized: false,
                );
              }
              debugPrint(
                'SegmentService: HTTP $status for $key -> ${response.body}',
              );
            } catch (e) {
              debugPrint('SegmentService: error fetching $key -> $e');
            }
            return (key: key, message: null, unauthorized: false);
          })
          .toList();

      final results = await Future.wait(futures);
      final segments = <String, SegmentMessage>{};
      var unauthorized = false;
      for (final result in results) {
        unauthorized = unauthorized || result.unauthorized;
        final message = result.message;
        if (message != null) {
          segments[result.key] = message;
        }
      }
      return SegmentFetchResult(segments: segments, unauthorized: unauthorized);
    } finally {
      client.close();
    }
  }

  static Future<SegmentMessage?> fetchSegment(
    String key, {
    String? token,
  }) async {
    final result = await fetchSegments([key], token: token);
    return result.segments[key];
  }
}
