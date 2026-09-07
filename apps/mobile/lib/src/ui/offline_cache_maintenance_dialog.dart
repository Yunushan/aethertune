import 'package:flutter/material.dart';

Future<bool> confirmOfflineCacheClear(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Clear private offline media?'),
        content: const Text(
          'Completed downloads, partial downloads, and unindexed files in the private cache will be removed. Your original local files and library metadata are kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear media'),
          ),
        ],
      ),
    ) ==
    true;
