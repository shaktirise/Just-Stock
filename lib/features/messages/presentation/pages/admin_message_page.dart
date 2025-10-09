import 'package:flutter/material.dart';

import 'package:newjuststock/features/messages/models/admin_message.dart';

class AdminMessagePage extends StatelessWidget {
  final AdminMessage message;

  const AdminMessagePage({super.key, required this.message});

  String _formatTimestamp(DateTime ts) {
    final local = ts.toLocal();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final month = months[local.month - 1];
    final day = local.day;
    final year = local.year;
    final hour24 = local.hour;
    final hour = hour24 % 12 == 0 ? 12 : hour24 % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = hour24 >= 12 ? 'PM' : 'AM';
    return '$day $month $year - $hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final width = MediaQuery.of(context).size.width;
    // Responsive sizing for prominent, legible message
    final titleSize = (width * 0.065).clamp(20.0, 28.0);
    final bodySize = (width * 0.075).clamp(22.0, 34.0);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Message'),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [scheme.primary, scheme.secondary],
            ),
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Card(
              elevation: 3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      message.title,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            fontSize: titleSize,
                            color: Colors.black87,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _formatTimestamp(message.createdAt),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.black54,
                            letterSpacing: 0.2,
                          ),
                    ),
                    const SizedBox(height: 24),
                    SelectableText(
                      message.body.isEmpty ? '-' : message.body,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.displaySmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            fontSize: bodySize,
                            height: 1.25,
                            color: Colors.black,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
