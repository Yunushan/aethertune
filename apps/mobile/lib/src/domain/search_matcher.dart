final class SearchQuery {
  const SearchQuery._({
    required this.raw,
    required this.terms,
  });

  factory SearchQuery.parse(String query) {
    final raw = normalizeSearchText(query);
    return SearchQuery._(
      raw: raw,
      terms: _searchTerms(raw),
    );
  }

  final String raw;
  final List<String> terms;

  bool get isEmpty => raw.isEmpty;
}

String normalizeSearchText(String value) => value.trim().toLowerCase();

bool searchTextMatches(String value, SearchQuery query) {
  if (query.isEmpty) {
    return true;
  }

  final normalized = normalizeSearchText(value);
  if (normalized.isEmpty) {
    return false;
  }
  if (normalized.contains(query.raw)) {
    return true;
  }

  final tokens = _searchTokens(normalized).toList(growable: false);
  if (tokens.isEmpty || query.terms.isEmpty) {
    return false;
  }

  return query.terms.every(
    (term) => _termMatchQuality(term, normalized, tokens) > 0,
  );
}

bool searchFieldsMatch(Iterable<String> values, SearchQuery query) {
  if (query.isEmpty) {
    return true;
  }

  final normalizedValues = values
      .map(normalizeSearchText)
      .where((value) => value.isNotEmpty)
      .toList(growable: false);
  if (normalizedValues.isEmpty) {
    return false;
  }

  final joined = normalizedValues.join(' ');
  if (joined.contains(query.raw)) {
    return true;
  }

  final tokens = <String>[
    for (final value in normalizedValues) ..._searchTokens(value),
  ];
  if (tokens.isEmpty || query.terms.isEmpty) {
    return false;
  }

  return query.terms.every(
    (term) => _termMatchQuality(term, joined, tokens) > 0,
  );
}

int searchTextScore(
  String value,
  SearchQuery query, {
  required int exact,
}) {
  if (query.isEmpty) {
    return 0;
  }

  final normalized = normalizeSearchText(value);
  if (normalized.isEmpty) {
    return 0;
  }
  if (normalized == query.raw) {
    return exact;
  }
  if (normalized.startsWith(query.raw)) {
    return (exact * 0.8).round();
  }
  if (normalized.contains(query.raw)) {
    return (exact * 0.6).round();
  }

  final tokens = _searchTokens(normalized).toList(growable: false);
  if (tokens.isEmpty || query.terms.isEmpty) {
    return 0;
  }

  var matchedTerms = 0;
  var qualityTotal = 0.0;
  for (final term in query.terms) {
    final quality = _termMatchQuality(term, normalized, tokens);
    if (quality <= 0) {
      continue;
    }

    matchedTerms += 1;
    qualityTotal += quality;
  }

  if (matchedTerms == 0) {
    return 0;
  }

  final coverage = matchedTerms / query.terms.length;
  final averageQuality = qualityTotal / matchedTerms;
  final weight = matchedTerms == query.terms.length ? 0.45 : 0.25;
  return (exact * weight * coverage * averageQuality).round();
}

List<String> _searchTerms(String normalizedQuery) {
  return _searchTokens(normalizedQuery).toList(growable: false);
}

Iterable<String> _searchTokens(String value) {
  return RegExp(r'[a-z0-9]+')
      .allMatches(value)
      .map((match) => match.group(0)!)
      .where((token) => token.isNotEmpty);
}

double _termMatchQuality(
  String term,
  String normalizedValue,
  List<String> tokens,
) {
  if (term.isEmpty) {
    return 0;
  }
  if (normalizedValue.contains(term)) {
    return 1;
  }

  final maxDistance = _maxTypoDistance(term);
  if (maxDistance == 0) {
    return 0;
  }

  var bestDistance = maxDistance + 1;
  for (final token in tokens) {
    final distance = _tokenDistance(term, token, maxDistance);
    if (distance < bestDistance) {
      bestDistance = distance;
    }
  }

  if (bestDistance > maxDistance) {
    return 0;
  }
  if (bestDistance == 1) {
    return 0.72;
  }
  return 0.55;
}

int _maxTypoDistance(String term) {
  if (term.length <= 2) {
    return 0;
  }
  if (term.length <= 5) {
    return 1;
  }
  return 2;
}

int _tokenDistance(String term, String token, int maxDistance) {
  if (token == term || token.startsWith(term)) {
    return 0;
  }

  final distance = _boundedDamerauLevenshtein(term, token, maxDistance);
  if (distance <= maxDistance) {
    return distance;
  }

  if (token.length > term.length) {
    final prefix = token.substring(0, term.length);
    return _boundedDamerauLevenshtein(term, prefix, maxDistance);
  }

  return distance;
}

int _boundedDamerauLevenshtein(
  String source,
  String target,
  int maxDistance,
) {
  if ((source.length - target.length).abs() > maxDistance) {
    return maxDistance + 1;
  }

  var previousPrevious = <int>[];
  var previous = List<int>.generate(target.length + 1, (index) => index);

  for (var sourceIndex = 1; sourceIndex <= source.length; sourceIndex += 1) {
    final current = List<int>.filled(target.length + 1, sourceIndex);
    for (var targetIndex = 1; targetIndex <= target.length; targetIndex += 1) {
      final substitutionCost = source.codeUnitAt(sourceIndex - 1) ==
              target.codeUnitAt(targetIndex - 1)
          ? 0
          : 1;
      var value = _min3(
        previous[targetIndex] + 1,
        current[targetIndex - 1] + 1,
        previous[targetIndex - 1] + substitutionCost,
      );

      if (sourceIndex > 1 &&
          targetIndex > 1 &&
          source.codeUnitAt(sourceIndex - 1) ==
              target.codeUnitAt(targetIndex - 2) &&
          source.codeUnitAt(sourceIndex - 2) ==
              target.codeUnitAt(targetIndex - 1)) {
        final transposition = previousPrevious[targetIndex - 2] + 1;
        if (transposition < value) {
          value = transposition;
        }
      }

      current[targetIndex] = value;
    }

    previousPrevious = previous;
    previous = current;
  }

  return previous[target.length];
}

int _min3(int a, int b, int c) {
  if (a <= b && a <= c) {
    return a;
  }
  if (b <= a && b <= c) {
    return b;
  }
  return c;
}
