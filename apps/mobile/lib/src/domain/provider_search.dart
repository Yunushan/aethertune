import 'music_source_provider.dart';
import 'search_matcher.dart';
import 'track.dart';

final class ProviderSearchCoordinator {
  const ProviderSearchCoordinator(
    this.providers, {
    this.maxResultsPerProvider = 10,
  }) : assert(maxResultsPerProvider > 0);

  final List<MusicSourceProvider> providers;
  final int maxResultsPerProvider;

  OfflineMediaPolicy get offlinePolicy => OfflineMediaPolicy(providers);

  MusicSourceProvider? providerFor(String providerId) {
    for (final provider in providers) {
      if (provider.id == providerId) {
        return provider;
      }
    }

    return null;
  }

  OfflineMediaPolicyDecision offlineDecision(
    Track track,
    OfflineMediaAction action,
  ) {
    return offlinePolicy.evaluate(track, action);
  }

  bool canCacheOffline(Track track) {
    return offlinePolicy.canCache(track);
  }

  bool canDownload(Track track) {
    return offlinePolicy.canDownload(track);
  }

  bool canResolve(Track track) {
    if (track.isPlayable) {
      return true;
    }

    return providerFor(track.sourceId)?.capabilities.contains(
          MusicSourceCapability.streamResolution,
        ) ??
        false;
  }

  Future<Track> resolvePlayableTrack(Track track) async {
    if (track.isPlayable) {
      return track;
    }

    final provider = providerFor(track.sourceId);
    final streamUri = await provider?.resolveStream(track);
    if (streamUri == null) {
      return track;
    }

    return track.copyWith(
      streamUrl: streamUri.toString(),
      streamUrlIsEphemeral:
          provider?.disclosure.requiresUserCredentials ?? false,
    );
  }

  Future<ProviderSearchResponse> search(String query) async {
    final normalizedQuery = query.trim();
    final searchQuery = SearchQuery.parse(normalizedQuery);
    if (searchQuery.isEmpty) {
      return const ProviderSearchResponse(
        query: '',
        results: <ProviderSearchResult>[],
        errors: <ProviderSearchError>[],
      );
    }

    final searchableProviders = providers
        .where(
          (provider) => provider.capabilities.contains(
            MusicSourceCapability.metadataSearch,
          ),
        )
        .toList(growable: false);
    return _searchProviders(
      normalizedQuery,
      searchQuery,
      <_ProviderSearchTarget>[
        for (var index = 0; index < searchableProviders.length; index += 1)
          _ProviderSearchTarget(
            provider: searchableProviders[index],
            providerIndex: index,
          ),
      ],
    );
  }

  Future<ProviderSearchResponse> continueSearch(
    String query,
    Map<String, String> continuations,
  ) async {
    final normalizedQuery = query.trim();
    final searchQuery = SearchQuery.parse(normalizedQuery);
    if (searchQuery.isEmpty || continuations.isEmpty) {
      return ProviderSearchResponse(
        query: normalizedQuery,
        results: const <ProviderSearchResult>[],
        errors: const <ProviderSearchError>[],
      );
    }

    final targets = <_ProviderSearchTarget>[];
    var providerIndex = 0;
    for (final provider in providers) {
      if (!provider.capabilities.contains(
            MusicSourceCapability.metadataSearch,
          )) {
        continue;
      }
      final cursor = continuations[provider.id];
      if (cursor != null && provider is MusicSourceSearchPagingProvider) {
        targets.add(
          _ProviderSearchTarget(
            provider: provider,
            providerIndex: providerIndex,
            cursor: cursor,
          ),
        );
      }
      providerIndex += 1;
    }

    return _searchProviders(normalizedQuery, searchQuery, targets);
  }

  Future<ProviderSearchResponse> _searchProviders(
    String query,
    SearchQuery searchQuery,
    List<_ProviderSearchTarget> targets,
  ) async {
    final outcomes = await Future.wait(
      <Future<_ProviderSearchOutcome>>[
        for (final target in targets)
          _searchProvider(
            target.provider,
            query,
            searchQuery,
            target.providerIndex,
            cursor: target.cursor,
          ),
      ],
    );
    final results = <ProviderSearchResult>[];
    final errors = <ProviderSearchError>[];
    final continuations = <String, String>{};
    final successfulProviderIds = <String>{};

    for (final outcome in outcomes) {
      if (outcome.error != null) {
        errors.add(outcome.error!);
        continue;
      }

      results.addAll(outcome.results);
      successfulProviderIds.add(outcome.providerId);
      final nextCursor = outcome.nextCursor;
      if (nextCursor != null) {
        continuations[outcome.providerId] = nextCursor;
      }
    }

    results.sort(_compareProviderSearchResults);

    return ProviderSearchResponse(
      query: query,
      results: results,
      errors: errors,
      continuations: Map<String, String>.unmodifiable(continuations),
      successfulProviderIds: Set<String>.unmodifiable(successfulProviderIds),
    );
  }

  Future<_ProviderSearchOutcome> _searchProvider(
    MusicSourceProvider provider,
    String query,
    SearchQuery searchQuery,
    int providerIndex, {
    String? cursor,
  }) async {
    try {
      final List<Track> tracks;
      String? nextCursor;
      if (provider is MusicSourceSearchPagingProvider) {
        final page = await provider.searchPage(
          query,
          cursor: cursor,
          limit: maxResultsPerProvider,
        );
        tracks = page.tracks;
        if (page.nextCursor != cursor) {
          nextCursor = page.nextCursor;
        }
      } else {
        tracks = (await provider.search(query))
            .take(maxResultsPerProvider)
            .toList(growable: false);
      }
      return _ProviderSearchOutcome(
        providerId: provider.id,
        results: tracks
            .map(
              (track) => ProviderSearchResult(
                providerId: provider.id,
                providerName: provider.name,
                providerIndex: providerIndex,
                track: track,
                score: _scoreTrack(track, searchQuery),
              ),
            )
            .toList(growable: false),
        nextCursor: nextCursor,
      );
    } catch (error) {
      return _ProviderSearchOutcome(
        providerId: provider.id,
        results: const <ProviderSearchResult>[],
        error: ProviderSearchError(
          providerId: provider.id,
          providerName: provider.name,
          message: error.toString(),
        ),
      );
    }
  }
}

final class ProviderSearchResponse {
  const ProviderSearchResponse({
    required this.query,
    required this.results,
    required this.errors,
    this.continuations = const <String, String>{},
    this.successfulProviderIds = const <String>{},
  });

  final String query;
  final List<ProviderSearchResult> results;
  final List<ProviderSearchError> errors;
  final Map<String, String> continuations;
  final Set<String> successfulProviderIds;

  bool get hasErrors => errors.isNotEmpty;
  bool get hasMore => continuations.isNotEmpty;
}

final class ProviderSearchResult {
  const ProviderSearchResult({
    required this.providerId,
    required this.providerName,
    required this.providerIndex,
    required this.track,
    required this.score,
  });

  final String providerId;
  final String providerName;
  final int providerIndex;
  final Track track;
  final int score;
}

final class ProviderSearchError {
  const ProviderSearchError({
    required this.providerId,
    required this.providerName,
    required this.message,
  });

  final String providerId;
  final String providerName;
  final String message;
}

final class _ProviderSearchOutcome {
  const _ProviderSearchOutcome({
    required this.providerId,
    required this.results,
    this.nextCursor,
    this.error,
  });

  final String providerId;
  final List<ProviderSearchResult> results;
  final String? nextCursor;
  final ProviderSearchError? error;
}

final class _ProviderSearchTarget {
  const _ProviderSearchTarget({
    required this.provider,
    required this.providerIndex,
    this.cursor,
  });

  final MusicSourceProvider provider;
  final int providerIndex;
  final String? cursor;
}

List<ProviderSearchResult> mergeProviderSearchResults(
  Iterable<ProviderSearchResult> existing,
  Iterable<ProviderSearchResult> additional,
) {
  final merged = <String, ProviderSearchResult>{};
  for (final result in <ProviderSearchResult>[...existing, ...additional]) {
    merged.putIfAbsent(
      '${result.providerId}\u0000${result.track.id}',
      () => result,
    );
  }
  final ranked = merged.values.toList(growable: false);
  ranked.sort(_compareProviderSearchResults);
  return List<ProviderSearchResult>.unmodifiable(ranked);
}

int _compareProviderSearchResults(
  ProviderSearchResult left,
  ProviderSearchResult right,
) {
  final scoreCompare = right.score.compareTo(left.score);
  if (scoreCompare != 0) {
    return scoreCompare;
  }

  final providerCompare = left.providerIndex.compareTo(right.providerIndex);
  if (providerCompare != 0) {
    return providerCompare;
  }

  return left.track.title.toLowerCase().compareTo(
        right.track.title.toLowerCase(),
      );
}

int _scoreTrack(Track track, SearchQuery query) {
  var score = track.isPlayable ? 20 : 0;
  score += _fieldScore(track.title, query, exact: 100);
  score += _fieldScore(track.artist, query, exact: 55);
  score += _fieldScore(track.album, query, exact: 35);
  score += _fieldScore(track.genre, query, exact: 25);
  return score;
}

int _fieldScore(
  String value,
  SearchQuery query, {
  required int exact,
}) {
  return searchTextScore(value, query, exact: exact);
}
