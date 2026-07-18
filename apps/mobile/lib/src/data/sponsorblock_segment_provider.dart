import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../domain/track_skip_segment.dart';

const maxSponsorBlockResponseBytes = 64 * 1024;
const maxSponsorBlockSegments = 50;

typedef SponsorBlockSegmentLoader = Future<List<TrackSkipSegment>> Function(
  String videoId, {
  required Duration maximum,
  Set<String> categories,
});

const sponsorBlockCategories = <String>{
  'sponsor',
  'intro',
  'outro',
  'selfpromo',
  'interaction',
  'preview',
  'filler',
  'music_offtopic',
};

/// Fetches public skip-only segments after a user explicitly enables it.
final class SponsorBlockSegmentProvider {
  SponsorBlockSegmentProvider({Uri? baseUri})
      : baseUri = baseUri ?? Uri.parse('https://sponsor.ajay.app');

  final Uri baseUri;

  Future<List<TrackSkipSegment>> loadSegments(
    String videoId, {
    required Duration maximum,
    Set<String> categories = sponsorBlockCategories,
  }) async {
    final normalizedVideoId = videoId.trim();
    if (!RegExp(r'^[A-Za-z0-9_-]{6,128}$').hasMatch(normalizedVideoId)) {
      throw const FormatException('A valid YouTube video ID is required.');
    }
    final selectedCategories = categories
        .where(sponsorBlockCategories.contains)
        .toSet();
    if (selectedCategories.isEmpty) {
      return const <TrackSkipSegment>[];
    }
    final prefix = sha256.convert(utf8.encode(normalizedVideoId)).toString().substring(0, 4);
    final uri = baseUri.replace(
      path: '${baseUri.path}/api/skipSegments/$prefix'.replaceAll('//', '/'),
      queryParameters: <String, String>{
        'categories': jsonEncode(selectedCategories.toList()..sort()),
      },
    );
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final response = await (await client.getUrl(uri)).close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('Segment request failed with HTTP ${response.statusCode}.', uri: uri);
      }
      final bytes = <int>[];
      await for (final chunk in response) {
        if (bytes.length + chunk.length > maxSponsorBlockResponseBytes) {
          throw const FormatException('Segment response is too large.');
        }
        bytes.addAll(chunk);
      }
      return parseSponsorBlockSegments(
        utf8.decode(bytes, allowMalformed: false),
        maximum: maximum,
        categories: selectedCategories,
      );
    } finally {
      client.close(force: true);
    }
  }
}

Future<List<TrackSkipSegment>> loadSponsorBlockSegments(
  String videoId, {
  required Duration maximum,
  Set<String> categories = sponsorBlockCategories,
}) => SponsorBlockSegmentProvider().loadSegments(
  videoId,
  maximum: maximum,
  categories: categories,
);

List<TrackSkipSegment> parseSponsorBlockSegments(
  String response, {
  required Duration maximum,
  Set<String> categories = sponsorBlockCategories,
}) {
  final decoded = jsonDecode(response);
  if (decoded is! List) {
    throw const FormatException('Segment response must be a JSON array.');
  }
  final segments = <TrackSkipSegment>[];
  for (final value in decoded.take(maxSponsorBlockSegments)) {
    if (value is! Map) continue;
    final category = value['category'];
    final actionType = value['actionType'];
    final range = value['segment'];
    if (category is! String ||
        actionType != 'skip' ||
        !categories.contains(category) ||
        range is! List ||
        range.length != 2) {
      continue;
    }
    final start = _secondsToDuration(range[0]);
    final end = _secondsToDuration(range[1]);
    if (start == null || end == null) continue;
    try {
      segments.add(TrackSkipSegment(start: start, end: end, label: 'SponsorBlock: $category'));
    } on ArgumentError {
      continue;
    }
  }
  return TrackSkipSegment.normalize(segments, maximum: maximum);
}

Duration? _secondsToDuration(Object? value) {
  if (value is! num || !value.isFinite || value.isNegative) return null;
  return Duration(milliseconds: (value * 1000).round());
}
