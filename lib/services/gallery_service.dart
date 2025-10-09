import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:newjuststock/services/api_config.dart';

class GalleryImage {
  final String id;
  final String url;
  final int? width;
  final int? height;
  final String? format;
  final String? folder;
  final DateTime? createdAt;

  const GalleryImage({
    required this.id,
    required this.url,
    this.width,
    this.height,
    this.format,
    this.folder,
    this.createdAt,
  });

  factory GalleryImage.fromJson(Map<String, dynamic> json) {
    int? parseInt(dynamic value) {
      if (value is int) return value;
      if (value is String) {
        return int.tryParse(value);
      }
      return null;
    }

    DateTime? parseDate(dynamic value) {
      if (value is String) {
        return DateTime.tryParse(value);
      }
      return null;
    }

    return GalleryImage(
      id: json['id']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      width: parseInt(json['width']),
      height: parseInt(json['height']),
      format: json['format']?.toString(),
      folder: json['folder']?.toString(),
      createdAt: parseDate(json['createdAt']),
    );
  }

  bool get hasValidUrl => url.isNotEmpty;
}

class GalleryService {
  static Future<List<GalleryImage>> fetchImages({int limit = 50}) async {
    final uri = ApiConfig.buildUri('/api/images', {'limit': limit});
    final response = await http.get(
      uri,
      headers: {'Accept': 'application/json'},
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw GalleryFetchException(
        'Failed to load images (HTTP ${response.statusCode}).',
      );
    }

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic> && decoded['items'] is List) {
        final items = (decoded['items'] as List)
            .whereType<Map<String, dynamic>>()
            .map(GalleryImage.fromJson)
            .where((image) => image.hasValidUrl)
            .toList();
        items.sort(
          (a, b) => (b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
              .compareTo(a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)),
        );
        return items;
      }
    } catch (error) {
      throw GalleryFetchException('Invalid response format.');
    }
    throw GalleryFetchException('No images available.');
  }
}

class GalleryFetchException implements Exception {
  final String message;

  const GalleryFetchException(this.message);

  @override
  String toString() => message;
}
