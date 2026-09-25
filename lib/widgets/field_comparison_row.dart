import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../services/metadata/metadata_models.dart';

/// One row of the metadata preservation comparison (spec §21/§22):
/// original vs. output, with a color-coded status.
class FieldComparisonRow extends StatelessWidget {
  final FieldComparison field;
  const FieldComparisonRow({super.key, required this.field});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (color, icon, label) = switch (field.status) {
      FieldStatus.preserved => (StatusColors.preserved, Icons.check_circle, 'Preserved'),
      FieldStatus.changed => (StatusColors.changed, Icons.info, 'Changed'),
      FieldStatus.removedByUser => (StatusColors.removed, Icons.remove_circle_outline, 'Removed by user'),
      FieldStatus.notSupportedByEncoder => (StatusColors.unsupported, Icons.cancel, 'Not supported by encoder'),
      FieldStatus.notPresentOriginally => (StatusColors.removed, Icons.remove, 'Not present originally'),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(field.label, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    Text(label, style: theme.textTheme.bodySmall?.copyWith(color: color)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${field.originalValue ?? '—'}  →  ${field.outputValue ?? '—'}',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
