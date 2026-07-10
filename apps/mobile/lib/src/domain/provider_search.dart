import 'music_source_provider.dart';
import 'search_matcher.dart';
import 'track.dart';

final class ProviderSearchCoordinator {
  const ProviderSearchCoordinator(
    this.providers, {
    this.maxResultsPerProvider = 10,
  });

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
    final outcomes = await Future.wait(
      <Future<_ProviderSearchOutcome>>[
        for (var index = 0; index < searchableProviders.length; index += 1)
          _searchProvider(
            searchableProviders[index],
            normalizedQuery,
            searchQuery,
            index,
          ),
      ],
    );
    final results = <ProviderSearchResult>[];
    final errors = <ProviderSearchError>[];

    for (final outcome in outcomes) {
      if (outcome.error != null) {
        errors.add(outcome.error!);
        continue;
      }

      results.addAll(outcome.results);
    }

    results.sort(_compareProviderSearchResults);

    return ProviderSearchResponse(
      query: normalizedQuery,
      results: results,
      errors: errors,
    );
  }

  Future<_ProviderSearchOutcome> _searchProvider(
    MusicSourceProvider provider,
    String query,
    SearchQuery searchQuery,
    int providerIndex,
  ) async {
    try {
      final tracks = await provider.search(query);
      return _ProviderSearchOutcome(
        results: tracks
            .take(maxResultsPerProvider)
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
      );
    } catch (error) {
      return _ProviderSearchOutcome(
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
  });

  final String query;
  final List<ProviderSearchResult> results;
  final List<ProviderSearchError> errors;

  bool get hasErrors => errors.isNotEmpty;
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
    required this.results,
    this.error,
  });

  final List<ProviderSearchResult> results;
  final ProviderSearchError? error;
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
