import 'package:flutter/material.dart';

class ListeningStatsBarDatum {
  const ListeningStatsBarDatum({
    required this.label,
    required this.value,
    required this.valueLabel,
  });

  final String label;
  final int value;
  final String valueLabel;
}

class ListeningStatsBarChart extends StatelessWidget {
  const ListeningStatsBarChart({
    super.key,
    required this.title,
    required this.icon,
    required this.color,
    required this.data,
  });

  final String title;
  final IconData icon;
  final Color color;
  final List<ListeningStatsBarDatum> data;

  @override
  Widget build(BuildContext context) {
    final visibleData = data.where((datum) => datum.value > 0).take(5).toList();
    if (visibleData.isEmpty) {
      return const SizedBox.shrink();
    }
    final maxValue = visibleData
        .map((datum) => datum.value)
        .reduce((left, right) => left > right ? left : right);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (var index = 0; index < visibleData.length; index += 1) ...<Widget>[
          _ListeningStatsBarRow(
            datum: visibleData[index],
            color: color,
            fraction: visibleData[index].value / maxValue,
          ),
          if (index != visibleData.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _ListeningStatsBarRow extends StatelessWidget {
  const _ListeningStatsBarRow({
    required this.datum,
    required this.color,
    required this.fraction,
  });

  final ListeningStatsBarDatum datum;
  final Color color;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '${datum.label}, ${datum.valueLabel}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  datum.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                datum.valueLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: fraction.clamp(0.0, 1.0).toDouble(),
              color: color,
              backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
            ),
          ),
        ],
      ),
    );
  }
}
