import 'music_catalog_provider.dart';

final class ProviderHomeSection {
  const ProviderHomeSection({
    required this.provider,
    required this.kind,
    required this.collections,
  });

  final MusicCatalogProvider provider;
  final MusicCatalogCollectionKind kind;
  final List<MusicCatalogCollection> collections;
}

final class ProviderHomeFeedError {
  const ProviderHomeFeedError({
    required this.providerId,
    required this.providerName,
    required this.kind,
  });

  final String providerId;
  final String providerName;
  final MusicCatalogCollectionKind kind;
}

final class ProviderHomeFeed {
  const ProviderHomeFeed({
    this.sections = const <ProviderHomeSection>[],
    this.errors = const <ProviderHomeFeedError>[],
  });

  final List<ProviderHomeSection> sections;
  final List<ProviderHomeFeedError> errors;

  bool get hasContent => sections.isNotEmpty;
}

final class ProviderHomeFeedCoordinator {
  const ProviderHomeFeedCoordinator();

  static const List<MusicCatalogCollectionKind> _supportedKinds =
      <MusicCatalogCollectionKind>[
        MusicCatalogCollectionKind.album,
        MusicCatalogCollectionKind.playlist,
      ];

  Future<ProviderHomeFeed> load(
    Iterable<MusicCatalogProvider> providers, {
    int limitPerSection = 6,
    int maxProviders = 8,
  }) async {
    if (limitPerSection <= 0 || maxProviders <= 0) {
      return const ProviderHomeFeed();
    }

    final uniqueProviders = <MusicCatalogProvider>[];
    final providerIds = <String>{};
    for (final provider in providers) {
      final providerId = provider.id.trim();
      if (providerId.isEmpty || !providerIds.add(providerId)) {
        continue;
      }
      uniqueProviders.add(provider);
      if (uniqueProviders.length == maxProviders) {
        break;
      }
    }
    if (uniqueProviders.isEmpty) {
      return const ProviderHomeFeed();
    }

    final results = await Future.wait<List<_ProviderHomeLoadResult>>(
      uniqueProviders.map(
        (provider) => Future.wait<_ProviderHomeLoadResult>(
          _supportedKinds.map(
            (kind) => _loadSection(provider, kind, limit: limitPerSection),
          ),
        ),
      ),
    );
    final sections = <ProviderHomeSection>[];
    final errors = <ProviderHomeFeedError>[];
    for (final providerResults in results) {
      for (final result in providerResults) {
        if (result.section != null) {
          sections.add(result.section!);
        }
        if (result.error != null) {
          errors.add(result.error!);
        }
      }
    }

    return ProviderHomeFeed(
      sections: List<ProviderHomeSection>.unmodifiable(sections),
      errors: List<ProviderHomeFeedError>.unmodifiable(errors),
    );
  }

  Future<_ProviderHomeLoadResult> _loadSection(
    MusicCatalogProvider provider,
    MusicCatalogCollectionKind kind, {
    required int limit,
  }) async {
    try {
      final collections = await provider.browseCollections(kind);
      final visible = <MusicCatalogCollection>[];
      final collectionIds = <String>{};
      for (final collection in collections) {
        final id = collection.id.trim();
        if (collection.kind != kind ||
            id.isEmpty ||
            collection.title.trim().isEmpty ||
            !collectionIds.add(id)) {
          continue;
        }
        visible.add(collection);
        if (visible.length == limit) {
          break;
        }
      }

      return _ProviderHomeLoadResult(
        section: visible.isEmpty
            ? null
            : ProviderHomeSection(
                provider: provider,
                kind: kind,
                collections: List<MusicCatalogCollection>.unmodifiable(visible),
              ),
      );
    } on Object {
      return _ProviderHomeLoadResult(
        error: ProviderHomeFeedError(
          providerId: provider.id,
          providerName: provider.name,
          kind: kind,
        ),
      );
    }
  }
}

final class _ProviderHomeLoadResult {
  const _ProviderHomeLoadResult({this.section, this.error});

  final ProviderHomeSection? section;
  final ProviderHomeFeedError? error;
}
