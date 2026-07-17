import '../domain/track.dart';
import 'youtube_channel_follow_store.dart';
import 'youtube_data_metadata_provider.dart';

/// Bounded, metadata-only results from device-locally followed public channels.
///
/// This does not use a YouTube account subscription feed, and callers must
/// invoke it explicitly rather than schedule background refreshes.
final class YouTubeFollowedChannelFeed {
  const YouTubeFollowedChannelFeed({
    required this.items,
    required this.failedChannelCount,
    required this.requestedChannelCount,
  });

  final List<YouTubeFollowedChannelFeedItem> items;
  final int failedChannelCount;
  final int requestedChannelCount;
}

final class YouTubeFollowedChannelFeedItem {
  const YouTubeFollowedChannelFeedItem({
    required this.track,
    required this.channelTitle,
    required this.publishedAt,
  });

  final Track track;
  final String channelTitle;
  final DateTime? publishedAt;

  String get subtitle {
    final date = publishedAt?.toIso8601String().split('T').first;
    return date == null ? channelTitle : '$channelTitle · $date';
  }
}

Future<YouTubeFollowedChannelFeed> loadYouTubeFollowedChannelFeed(
  YouTubeDataMetadataProvider provider,
  Iterable<YouTubeChannelFollow> follows, {
  int limitPerChannel = 5,
  int? maxChannels,
}) async {
  if (limitPerChannel <= 0) {
    throw ArgumentError.value(
      limitPerChannel,
      'limitPerChannel',
      'Must be positive.',
    );
  }
  if (maxChannels != null && maxChannels <= 0) {
    throw ArgumentError.value(maxChannels, 'maxChannels', 'Must be positive.');
  }

  final selectedFollows = <YouTubeChannelFollow>[];
  final channelIds = <String>{};
  for (final follow in follows) {
    if (!channelIds.add(follow.id)) {
      continue;
    }
    selectedFollows.add(follow);
    if (maxChannels != null && selectedFollows.length == maxChannels) {
      break;
    }
  }
  final responses = await Future.wait<_ChannelFeedResponse>(
    selectedFollows.map((follow) async {
      try {
        final page = await provider.loadChannelVideosPage(
          follow.id,
          limit: limitPerChannel,
        );
        return _ChannelFeedResponse.success(
          channelTitle: follow.title,
          videos: page.videos,
        );
      } on Object {
        return const _ChannelFeedResponse.failure();
      }
    }),
  );
  final seenTrackIds = <String>{};
  final items = <YouTubeFollowedChannelFeedItem>[
    for (final response in responses)
      if (response.videos != null)
        for (final video in response.videos!)
          if (seenTrackIds.add(video.track.id))
            YouTubeFollowedChannelFeedItem(
              track: video.track,
              channelTitle: response.channelTitle!,
              publishedAt: video.publishedAt,
            ),
  ]..sort(_compareFeedItems);

  return YouTubeFollowedChannelFeed(
    items: List<YouTubeFollowedChannelFeedItem>.unmodifiable(items),
    failedChannelCount: responses
        .where((response) => response.videos == null)
        .length,
    requestedChannelCount: selectedFollows.length,
  );
}

final class _ChannelFeedResponse {
  const _ChannelFeedResponse.success({
    required this.channelTitle,
    required this.videos,
  });

  const _ChannelFeedResponse.failure()
    : channelTitle = null,
      videos = null;

  final String? channelTitle;
  final List<YouTubeDataChannelVideo>? videos;
}

int _compareFeedItems(
  YouTubeFollowedChannelFeedItem first,
  YouTubeFollowedChannelFeedItem second,
) {
  final firstTime = first.publishedAt;
  final secondTime = second.publishedAt;
  if (firstTime == null && secondTime == null) {
    return first.track.title.toLowerCase().compareTo(second.track.title.toLowerCase());
  }
  if (firstTime == null) {
    return 1;
  }
  if (secondTime == null) {
    return -1;
  }
  final byTime = secondTime.compareTo(firstTime);
  return byTime != 0
      ? byTime
      : first.track.title.toLowerCase().compareTo(second.track.title.toLowerCase());
}
