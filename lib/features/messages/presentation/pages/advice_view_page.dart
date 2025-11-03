import 'package:flutter/material.dart';
import 'package:newjuststock/features/messages/services/advice_service.dart';

class AdviceViewPage extends StatelessWidget {
  final AdviceDetail detail;
  const AdviceViewPage({super.key, required this.detail});

  String _formatTimestamp(DateTime ts) {
    final local = ts.toLocal();
    const months = [
      'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    final m = months[local.month - 1];
    final d = local.day.toString().padLeft(2, '0');
    final y = local.year;
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$d $m $y • $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget buildCard(String label, String value, Color color) {
      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          child: Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.all(8),
                child: Icon(Icons.flag_rounded, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.onSurface.withOpacity(0.7),
                          fontWeight: FontWeight.w600,
                        )),
                    const SizedBox(height: 6),
                    Text(
                      value.isEmpty ? '-' : value,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Advice')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  detail.category,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _formatTimestamp(detail.createdAt),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                  ),
                ),
                const SizedBox(height: 16),
                buildCard('BUY', detail.buy ?? _extractValue(detail.text, 'BUY'), Colors.green.shade700),
                buildCard('TARGET', detail.target ?? _extractValue(detail.text, 'TARGET'), Colors.blue.shade700),
                buildCard('STOPLOSS', detail.stoploss ?? _extractValue(detail.text, 'STOPLOSS'), Colors.red.shade700),
                const SizedBox(height: 12),
                Card(
                  elevation: 1,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: SelectableText(
                      detail.text,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        height: 1.3,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _extractValue(String text, String key) {
    try {
      final lines = text.split('\n');
      for (final line in lines) {
        final idx = line.toUpperCase().indexOf('$key:');
        if (idx >= 0) {
          final value = line.substring(idx + key.length + 1).trim();
          if (value.isNotEmpty) return value;
        }
      }
    } catch (_) {}
    return '';
  }
}

