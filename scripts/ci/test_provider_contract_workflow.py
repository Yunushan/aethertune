#!/usr/bin/env python3
"""Regression checks for named provider-contract CI reporting."""

from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github" / "workflows" / "aethertune-ci.yml"

EXPECTED_PROVIDER_STEPS = {
    "Core source model": (
        "test/music_source_provider_test.dart",
        "test/provider_search_test.dart",
        "test/provider_home_feed_test.dart",
    ),
    "Local Library": (
        "test/local_library_provider_test.dart",
        "test/provider_binary_loader_test.dart",
    ),
    "Podcast RSS": (
        "test/itunes_podcast_directory_test.dart",
        "test/podcast_rss_provider_test.dart",
        "test/podcast_subscription_refresh_worker_test.dart",
    ),
    "Radio Browser": (
        "test/radio_browser_provider_test.dart",
        "test/radio_browser_station_screen_test.dart",
    ),
    "Internet Archive": (
        "test/internet_archive_provider_test.dart",
        "test/internet_archive_item_screen_test.dart",
        "test/internet_archive_collection_screen_test.dart",
    ),
    "Audius": ("test/audius_provider_test.dart",),
    "Jamendo": (
        "test/jamendo_provider_test.dart",
        "test/jamendo_settings_store_test.dart",
    ),
    "Custom Catalog": ("test/custom_catalog_provider_test.dart",),
    "Spotify metadata": (
        "test/spotify_metadata_provider_test.dart",
        "test/spotify_oauth_client_test.dart",
        "test/spotify_oauth_flow_test.dart",
    ),
    "YouTube Data metadata": (
        "test/youtube_data_metadata_provider_test.dart",
        "test/youtube_music_chart_screen_test.dart",
        "test/youtube_public_playlists_screen_test.dart",
        "test/youtube_followed_channel_feed_screen_test.dart",
    ),
    "Jellyfin": ("test/jellyfin_provider_test.dart",),
    "Navidrome and Subsonic": ("test/subsonic_provider_test.dart",),
    "LRCLIB lyrics": ("test/lrclib_lyrics_provider_test.dart",),
}


class ProviderContractWorkflowTest(unittest.TestCase):
    def test_reports_each_supported_provider_contract(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")

        for provider, targets in EXPECTED_PROVIDER_STEPS.items():
            command = "cd apps/mobile && flutter test " + " ".join(targets)
            self.assertIn(f"- name: Provider contract - {provider}", workflow)
            self.assertIn(command, workflow)


if __name__ == "__main__":
    unittest.main()
