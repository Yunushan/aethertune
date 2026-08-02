import 'youtube_account_provider.dart';
import 'youtube_data_metadata_provider.dart';
import 'youtube_followed_channel_feed.dart';

/// Bounded, read-only recent metadata from a connected account's subscriptions.
///
/// Callers invoke this deliberately. The result is not persisted, merged into
/// the public Following cache, or used to alter a YouTube subscription.
final class YouTubeAccountFollowingFeed {
  const YouTubeAccountFollowingFeed({
    required this.items,
    required this.failedChannelCount,
    required this.requestedChannelCount,
  });

  final List<YouTubeFollowedChannelFeedItem> items;
  final int failedChannelCount;
  final int requestedChannelCount;
}

Future<YouTubeAccountFollowingFeed> loadYouTubeAccountFollowingFeed(
  YouTubeAccountProvider provider, {
  int limitPerChannel = 2,
  int maxChannels = 12,
}) async {
  if (limitPerChannel <= 0) {
    throw ArgumentError.value(
      limitPerChannel,
      'limitPerChannel',
      'Must be positive.',
    );
  }
  if (maxChannels <= 0) {
    throw ArgumentError.value(maxChannels, 'maxChannels', 'Must be positive.');
  }

  final subscriptionPage = await provider.loadMySubscriptionsPage(
    limit: maxChannels,
  );
  final selectedChannels = <YouTubeDataChannel>[];
  final channelIds = <String>{};
  for (final channel in subscriptionPage.channels) {
    if (channel.id.isEmpty || !channelIds.add(channel.id)) {
      continue;
    }
    selectedChannels.add(channel);
    if (selectedChannels.length == maxChannels) {
      break;
    }
  }

  final responses = await Future.wait<_AccountChannelFeedResponse>(
    selectedChannels.map((channel) async {
      try {
        final page = await provider.loadChannelVideosPage(
          channel.id,
          limit: limitPerChannel,
        );
        return _AccountChannelFeedResponse.success(
          channelTitle: channel.title,
          videos: page.videos,
        );
      } on Object {
        return const _AccountChannelFeedResponse.failure();
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

  return YouTubeAccountFollowingFeed(
    items: List<YouTubeFollowedChannelFeedItem>.unmodifiable(items),
    failedChannelCount: responses
        .where((response) => response.videos == null)
        .length,
    requestedChannelCount: selectedChannels.length,
  );
}

final class _AccountChannelFeedResponse {
  const _AccountChannelFeedResponse.success({
    required this.channelTitle,
    required this.videos,
  });

  const _AccountChannelFeedResponse.failure()
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
    return first.track.title.toLowerCase().compareTo(
      second.track.title.toLowerCase(),
    );
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
      : first.track.title.toLowerCase().compareTo(
          second.track.title.toLowerCase(),
        );
}
