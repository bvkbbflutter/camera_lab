import 'package:flutter/material.dart';

/// One labeled row in the Image Details / metadata inspector screens
/// (spec §15/§45). Shows "Not available" rather than a fake value when
/// [value] is null or empty.
class MetadataTile extends StatelessWidget {
  final String label;
  final String? value;
  const MetadataTile({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final display = (value == null || value!.isEmpty) ? 'Not available' : value!;
    final isMissing = value == null || value!.isEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 130, child: Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant))),
          Expanded(
            child: Text(
              display,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontStyle: isMissing ? FontStyle.italic : FontStyle.normal,
                color: isMissing ? theme.colorScheme.outline : theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MetadataSectionHeader extends StatelessWidget {
  final String title;
  const MetadataSectionHeader({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.bold)),
          const Divider(height: 8),
        ],
      ),
    );
  }
}
