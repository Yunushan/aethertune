import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/internet_archive_provider.dart';
import '../data/library_store.dart';
import 'internet_archive_item_screen.dart';

class InternetArchiveCollectionScreen extends StatefulWidget {
  const InternetArchiveCollectionScreen({
    super.key,
    required this.collection,
    required this.provider,
  });

  final String collection;
  final InternetArchiveProvider provider;

  @override
  State<InternetArchiveCollectionScreen> createState() =>
      _InternetArchiveCollectionScreenState();
}

class _InternetArchiveCollectionScreenState
    extends State<InternetArchiveCollectionScreen> {
  List<InternetArchiveItem> _items = <InternetArchiveItem>[];
  int _page = 0;
  int? _totalResults;
  bool _hasMore = false;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load(reset: true));
  }

  @override
  Widget build(BuildContext context) {
    final offlineModeEnabled = context.watch<LibraryStore>().offlineModeEnabled;
    final title = widget.collection.trim();

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.collections_bookmark_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Internet Archive collection',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (offlineModeEnabled && _items.isEmpty)
            const ListTile(
              leading: Icon(Icons.cloud_off_outlined),
              title: Text('Offline mode is on'),
              subtitle: Text('Turn it off to browse this collection.'),
            ),
          if (_loading && _items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_error != null && _items.isEmpty)
            ListTile(
              leading: const Icon(Icons.error_outline),
              title: const Text('Could not load this collection'),
              subtitle: Text(_error!),
              trailing: IconButton(
                tooltip: 'Retry collection',
                onPressed: _loading || offlineModeEnabled
                    ? null
                    : () => unawaited(_load(reset: true)),
                icon: const Icon(Icons.refresh),
              ),
            ),
          if (!_loading && _error == null && _items.isEmpty && !offlineModeEnabled)
            const ListTile(
              leading: Icon(Icons.archive_outlined),
              title: Text('No playable archive items found'),
            ),
          for (final item in _items)
            ListTile(
              leading: const Icon(Icons.archive_outlined),
              title: Text(item.title),
              subtitle: Text(_itemSubtitle(item)),
              onTap: () => _openItem(item),
              trailing: const Icon(Icons.chevron_right),
            ),
          if (_loading && _items.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          if (_error != null && _items.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.error_outline),
              title: const Text('Could not load more archive items'),
              subtitle: Text(_error!),
              trailing: IconButton(
                tooltip: 'Retry collection page',
                onPressed: _loading || offlineModeEnabled
                    ? null
                    : () => unawaited(_load(reset: false)),
                icon: const Icon(Icons.refresh),
              ),
            ),
          if (_items.isNotEmpty && _hasMore)
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _loading || offlineModeEnabled
                    ? null
                    : () => unawaited(_load(reset: false)),
                icon: const Icon(Icons.expand_more),
                label: Text(_loadMoreLabel),
              ),
            )
          else if (_items.isNotEmpty && _totalResults != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'All $_totalResults archive results loaded.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _load({required bool reset}) async {
    if (_loading || (!reset && !_hasMore)) {
      return;
    }
    if (context.read<LibraryStore>().offlineModeEnabled) {
      setState(() {
        _loading = false;
        _error = 'Offline mode is on.';
      });
      return;
    }

    final requestedPage = reset ? 1 : _page + 1;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _items = <InternetArchiveItem>[];
        _page = 0;
        _totalResults = null;
        _hasMore = false;
      }
    });

    try {
      final page = await widget.provider.searchAudioPage(
        '',
        filters: InternetArchiveSearchFilters(collection: widget.collection),
        page: requestedPage,
        includeFacets: false,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _items = reset ? page.items : _mergeItems(_items, page.items);
        _page = page.page;
        _totalResults = page.totalResults;
        _hasMore = page.hasMore;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  List<InternetArchiveItem> _mergeItems(
    List<InternetArchiveItem> current,
    List<InternetArchiveItem> incoming,
  ) {
    final identifiers = current.map((item) => item.identifier).toSet();
    return <InternetArchiveItem>[
      ...current,
      for (final item in incoming)
        if (identifiers.add(item.identifier)) item,
    ];
  }

  String get _loadMoreLabel {
    final totalResults = _totalResults;
    if (totalResults == null) {
      return 'Load more archive items';
    }
    final remaining = totalResults - _items.length;
    return remaining > 0
        ? 'Load more archive items ($remaining remaining)'
        : 'Load more archive items';
  }

  String _itemSubtitle(InternetArchiveItem item) {
    final playableFileCount =
        item.files.where((file) => file.isPlayableAudio).length;
    final parts = <String>[
      if (item.creator.isNotEmpty) item.creator,
      if (item.year.isNotEmpty) item.year,
      '$playableFileCount playable ${playableFileCount == 1 ? 'file' : 'files'}',
    ];
    return parts.join(' / ');
  }

  Future<void> _openItem(InternetArchiveItem item) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => InternetArchiveItemScreen(
          item: item,
          provider: widget.provider,
          onOpenCollection: _openCollection,
        ),
      ),
    );
  }

  void _openCollection(String collection) {
    final normalized = collection.trim();
    if (normalized.isEmpty) {
      return;
    }
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => InternetArchiveCollectionScreen(
          collection: normalized,
          provider: widget.provider,
        ),
      ),
    );
  }
}
