part of 'home_screen.dart';

mixin _SourcesArchiveSection on State<_SourcesTab> {
  InternetArchiveProvider get _archiveProvider;
  bool _offlineModeBlocksSourceNetwork(BuildContext context);

  final _archiveSearchController = TextEditingController();
  final _archiveCollectionController = TextEditingController();
  final _archiveSubjectController = TextEditingController();
  final _archiveCreatorController = TextEditingController();
  final _archiveYearController = TextEditingController();
  List<InternetArchiveItem> _archiveItems = <InternetArchiveItem>[];
  List<InternetArchiveFacet> _archiveFacets = <InternetArchiveFacet>[];
  int _archivePage = 0;
  int? _archiveTotalResults;
  int _archiveRequestSerial = 0;
  bool _archiveHasMore = false;
  bool _archiveLoading = false;
  String? _archiveError;

  void _disposeInternetArchiveSection() {
    _archiveSearchController.dispose();
    _archiveCollectionController.dispose();
    _archiveSubjectController.dispose();
    _archiveCreatorController.dispose();
    _archiveYearController.dispose();
  }

  List<Widget> _internetArchiveSectionWidgets(
    BuildContext context, {
    required bool offlineModeEnabled,
  }) {
    return <Widget>[
      const SizedBox(height: 16),
      Text(
        'Internet Archive audio',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
      Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: _archiveSearchController,
              enabled: !offlineModeEnabled,
              decoration: const InputDecoration(
                labelText: 'Archive search',
                prefixIcon: Icon(Icons.search),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: offlineModeEnabled || _archiveLoading
                  ? null
                  : (_) => _searchArchiveItems(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            tooltip: 'Search archive audio',
            onPressed: _archiveLoading || offlineModeEnabled
                ? null
                : _searchArchiveItems,
            icon: const Icon(Icons.search),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          _archiveFilterField(
            controller: _archiveCollectionController,
            labelText: 'Collection',
            icon: Icons.collections_bookmark_outlined,
          ),
          _archiveFilterField(
            controller: _archiveSubjectController,
            labelText: 'Subject',
            icon: Icons.sell_outlined,
          ),
          _archiveFilterField(
            controller: _archiveCreatorController,
            labelText: 'Creator',
            icon: Icons.person_search_outlined,
          ),
          _archiveFilterField(
            controller: _archiveYearController,
            labelText: 'Year',
            icon: Icons.calendar_month_outlined,
            keyboardType: TextInputType.number,
          ),
          OutlinedButton.icon(
            onPressed: _archiveLoading ? null : _clearArchiveFilters,
            icon: const Icon(Icons.filter_alt_off_outlined),
            label: const Text('Clear'),
          ),
        ],
      ),
      if (_archiveFacets.isNotEmpty) ...<Widget>[
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _archiveFacetChips(offlineModeEnabled: offlineModeEnabled),
        ),
      ],
      if (_archiveLoading) ...<Widget>[
        const SizedBox(height: 12),
        const LinearProgressIndicator(),
      ],
      if (_archiveError != null && _archiveItems.isEmpty) ...<Widget>[
        const SizedBox(height: 8),
        ListTile(
          leading: const Icon(Icons.error_outline),
          title: const Text('Archive search failed'),
          subtitle: Text(_archiveError!),
        ),
      ] else if (_archiveItems.isEmpty && !_archiveLoading) ...<Widget>[
        const SizedBox(height: 8),
        const ListTile(
          leading: Icon(Icons.archive_outlined),
          title: Text('No archive audio loaded'),
          subtitle: Text(
            'Search by keyword, collection, subject, creator, or year.',
          ),
        ),
      ] else ...<Widget>[
        const SizedBox(height: 8),
        for (final item in _archiveItems)
          ListTile(
            leading: const Icon(Icons.archive_outlined),
            title: Text(item.title),
            subtitle: Text(_archiveItemSubtitle(item)),
            onTap: () => _openArchiveItem(context, item),
            trailing: const Icon(Icons.chevron_right),
          ),
      ],
      if (_archiveItems.isNotEmpty && _archiveError != null) ...<Widget>[
        const SizedBox(height: 8),
        ListTile(
          leading: const Icon(Icons.error_outline),
          title: const Text('Could not load more archive audio'),
          subtitle: Text(_archiveError!),
          trailing: IconButton(
            tooltip: 'Retry loading archive results',
            onPressed: _archiveLoading || offlineModeEnabled
                ? null
                : _loadMoreArchiveItems,
            icon: const Icon(Icons.refresh),
          ),
        ),
      ],
      if (_archiveItems.isNotEmpty && _archiveHasMore) ...<Widget>[
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _archiveLoading || offlineModeEnabled
                ? null
                : _loadMoreArchiveItems,
            icon: const Icon(Icons.expand_more),
            label: Text(_archiveLoadMoreLabel),
          ),
        ),
      ] else if (_archiveItems.isNotEmpty &&
          _archiveTotalResults != null) ...<Widget>[
        const SizedBox(height: 8),
        Text(
          'All $_archiveTotalResults archive results loaded.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ];
  }

  Future<void> _searchArchiveItems() async {
    await _loadArchiveItems(reset: true);
  }

  Future<void> _loadMoreArchiveItems() async {
    await _loadArchiveItems(reset: false);
  }

  Future<void> _loadArchiveItems({required bool reset}) async {
    if (_archiveLoading || (!reset && !_archiveHasMore)) {
      return;
    }

    if (_offlineModeBlocksSourceNetwork(context)) {
      setState(() {
        _archiveRequestSerial += 1;
        _archiveItems = <InternetArchiveItem>[];
        _archiveFacets = <InternetArchiveFacet>[];
        _archivePage = 0;
        _archiveTotalResults = null;
        _archiveHasMore = false;
        _archiveLoading = false;
        _archiveError = 'Offline mode is on.';
      });
      return;
    }

    final requestSerial = reset
        ? ++_archiveRequestSerial
        : _archiveRequestSerial;
    final requestedPage = reset ? 1 : _archivePage + 1;

    setState(() {
      _archiveLoading = true;
      _archiveError = null;
      if (reset) {
        _archiveItems = <InternetArchiveItem>[];
        _archiveFacets = <InternetArchiveFacet>[];
        _archivePage = 0;
        _archiveTotalResults = null;
        _archiveHasMore = false;
      }
    });

    try {
      final page = await _archiveProvider.searchAudioPage(
        _archiveSearchController.text,
        filters: _archiveFilters(),
        page: requestedPage,
        includeFacets: reset,
      );
      if (!mounted || requestSerial != _archiveRequestSerial) {
        return;
      }

      setState(() {
        _archiveItems = reset
            ? page.items
            : _mergeArchiveItems(_archiveItems, page.items);
        if (reset) {
          _archiveFacets = page.facets;
        }
        _archivePage = page.page;
        _archiveTotalResults = page.totalResults;
        _archiveHasMore = page.hasMore;
        _archiveLoading = false;
      });
    } catch (error) {
      if (!mounted || requestSerial != _archiveRequestSerial) {
        return;
      }

      setState(() {
        if (reset) {
          _archiveItems = <InternetArchiveItem>[];
          _archiveFacets = <InternetArchiveFacet>[];
          _archivePage = 0;
          _archiveTotalResults = null;
          _archiveHasMore = false;
        }
        _archiveLoading = false;
        _archiveError = error.toString();
      });
    }
  }

  List<InternetArchiveItem> _mergeArchiveItems(
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

  String get _archiveLoadMoreLabel {
    final totalResults = _archiveTotalResults;
    if (totalResults == null) {
      return 'Load more archive results';
    }

    final remaining = totalResults - _archiveItems.length;
    return remaining > 0
        ? 'Load more archive results ($remaining remaining)'
        : 'Load more archive results';
  }

  String _archiveItemSubtitle(InternetArchiveItem item) {
    final playableFileCount = item.files
        .where((file) => file.isPlayableAudio)
        .length;
    final parts = <String>[
      if (item.creator.isNotEmpty) item.creator,
      if (item.year.isNotEmpty) item.year,
      '$playableFileCount playable ${playableFileCount == 1 ? 'file' : 'files'}',
    ];
    return parts.join(' / ');
  }

  Future<void> _openArchiveItem(
    BuildContext context,
    InternetArchiveItem item,
  ) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => InternetArchiveItemScreen(
          item: item,
          provider: _archiveProvider,
          onOpenCollection: (collection) =>
              _openArchiveCollection(context, collection),
        ),
      ),
    );
  }

  Future<void> _openArchiveCollection(BuildContext context, String collection) {
    final normalized = collection.trim();
    if (normalized.isEmpty) {
      return Future<void>.value();
    }
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => InternetArchiveCollectionScreen(
          collection: normalized,
          provider: _archiveProvider,
        ),
      ),
    );
  }

  Widget _archiveFilterField({
    required TextEditingController controller,
    required String labelText,
    required IconData icon,
    TextInputType? keyboardType,
  }) {
    return SizedBox(
      width: 168,
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: labelText,
          prefixIcon: Icon(icon),
        ),
        keyboardType: keyboardType,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _searchArchiveItems(),
      ),
    );
  }

  List<Widget> _archiveFacetChips({required bool offlineModeEnabled}) {
    final chips = <Widget>[];
    for (final field in <String>['collection', 'subject', 'creator', 'year']) {
      chips.addAll(
        _archiveFacets
            .where((facet) => facet.field == field)
            .take(4)
            .map(
              (facet) => ActionChip(
                avatar: Icon(_archiveFacetIcon(facet.field), size: 18),
                label: Text(
                  '${_archiveFacetLabel(facet.field)}: ${facet.value} '
                  '(${facet.count})',
                ),
                tooltip: 'Filter ${_archiveFacetLabel(facet.field)}',
                onPressed: offlineModeEnabled || _archiveLoading
                    ? null
                    : () => _applyArchiveFacet(facet),
              ),
            ),
      );
    }

    return chips;
  }

  TextEditingController? _archiveFacetController(String field) {
    switch (field) {
      case 'collection':
        return _archiveCollectionController;
      case 'subject':
        return _archiveSubjectController;
      case 'creator':
        return _archiveCreatorController;
      case 'year':
        return _archiveYearController;
    }

    return null;
  }

  IconData _archiveFacetIcon(String field) {
    switch (field) {
      case 'collection':
        return Icons.collections_bookmark_outlined;
      case 'subject':
        return Icons.sell_outlined;
      case 'creator':
        return Icons.person_search_outlined;
      case 'year':
        return Icons.calendar_month_outlined;
    }

    return Icons.filter_alt_outlined;
  }

  String _archiveFacetLabel(String field) {
    switch (field) {
      case 'collection':
        return 'Collection';
      case 'subject':
        return 'Subject';
      case 'creator':
        return 'Creator';
      case 'year':
        return 'Year';
    }

    return 'Facet';
  }

  void _applyArchiveFacet(InternetArchiveFacet facet) {
    final controller = _archiveFacetController(facet.field);
    if (controller == null) {
      return;
    }

    controller.text = facet.value;
    unawaited(_searchArchiveItems());
  }

  InternetArchiveSearchFilters _archiveFilters() {
    return InternetArchiveSearchFilters(
      collection: _archiveCollectionController.text,
      subject: _archiveSubjectController.text,
      creator: _archiveCreatorController.text,
      year: _archiveYearController.text,
    );
  }

  void _clearArchiveFilters() {
    setState(() {
      _archiveCollectionController.clear();
      _archiveSubjectController.clear();
      _archiveCreatorController.clear();
      _archiveYearController.clear();
      _archiveRequestSerial += 1;
      _archiveItems = <InternetArchiveItem>[];
      _archiveFacets = <InternetArchiveFacet>[];
      _archivePage = 0;
      _archiveTotalResults = null;
      _archiveHasMore = false;
      _archiveError = null;
    });
  }
}
