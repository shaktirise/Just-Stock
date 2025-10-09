import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:newjuststock/features/messages/models/admin_message.dart';

class AdminMessageRepository {
  static const _pendingKey = 'admin_message_pending_v1';
  static const _historyKey = 'admin_message_history_v1';

  const AdminMessageRepository._();

  static Future<AdminMessage?> getPending() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pendingKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return AdminMessage.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  static Future<void> setPending(AdminMessage message) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingKey, jsonEncode(message.toJson()));
  }

  static Future<void> clearPending() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingKey);
  }

  static Future<List<AdminMessage>> getHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_historyKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      return list.map(AdminMessage.fromJson).toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> _saveHistory(List<AdminMessage> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _historyKey,
      jsonEncode(items.map((e) => e.toJson()).toList()),
    );
  }

  /// Moves current pending message to history and clears pending.
  static Future<AdminMessage?> markPendingSeen() async {
    final pending = await getPending();
    if (pending == null) return null;
    final history = await getHistory();
    final updated = List<AdminMessage>.from(history)..insert(0, pending);
    await _saveHistory(updated);
    await clearPending();
    return pending;
  }

  /// Helper to simulate an admin message without backend.
  static Future<void> simulateAdminMessage({
    String? title,
    required String body,
  }) async {
    final now = DateTime.now();
    final msg = AdminMessage(
      id: now.millisecondsSinceEpoch.toString(),
      title: (title == null || title.trim().isEmpty) ? 'Admin Message' : title,
      body: body,
      createdAt: now,
    );
    await setPending(msg);
  }
}

