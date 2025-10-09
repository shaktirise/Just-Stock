class AdminMessage {
  final String id;
  final String title;
  final String body;
  final DateTime createdAt;

  const AdminMessage({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
  });

  factory AdminMessage.fromJson(Map<String, dynamic> json) {
    return AdminMessage(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? 'Admin Message').toString(),
      body: (json['body'] ?? '').toString(),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'createdAt': createdAt.toIso8601String(),
      };
}

