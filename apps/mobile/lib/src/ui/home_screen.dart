import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../data/demo_source_provider.dart';
import '../data/library_store.dart';
import '../domain/track.dart';
import '../player/player_controller.dart';
import 'widgets/player_bar.dart';
import 'widgets/track_tile.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchController = TextEditingController();
  int _tabIndex = 0;
  bool _favoritesOnly = false;
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AetherTune'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Import local audio',
            onPressed: () => _importAudio(context),
            icon: const Icon(Icons.library_add),
          ),
          IconButton(
            tooltip: 'Sleep timer',
            onPressed: () => _showSleepTimer(context),
            icon: const Icon(Icons.bedtime_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: IndexedStack(
                index: _tabIndex,
                children: <Widget>[
                  _LibraryTab(
                    searchController: _searchController,
                    query: _query,
                    favoritesOnly: _favoritesOnly,
                    onQueryChanged: (value) => setState(() => _query = value),
                    onFavoritesOnlyChanged: (value) {
                      setState(() => _favoritesOnly = value);
                    },
                    onImport: () => _importAudio(context),
                  ),
                  const _SourcesTab(),
                  const _SettingsTab(),
                ],
              ),
            ),
            const PlayerBar(),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (index) => setState(() => _tabIndex = index),
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.my_library_music_outlined),
            selectedIcon: Icon(Icons.my_library_music),
            label: 'Library',
          ),
          NavigationDestination(
            icon: Icon(Icons.extension_outlined),
            selectedIcon: Icon(Icons.extension),
            label: 'Sources',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune),
            label: 'Options',
          ),
        ],
      ),
    );
  }

  Future<void> _importAudio(BuildContext context) async {
    final library = context.read<LibraryStore>();
    final messenger = ScaffoldMessenger.of(context);

    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.audio,
    );

    if (result == null || result.files.isEmpty) {
      return;
    }

    final now = DateTime.now();
    final tracks = result.files
        .where((file) => file.path != null)
        .map(
          (file) => Track(
            id: Track.stableLocalId(file.path!),
            title: p.basenameWithoutExtension(file.name),
            artist: 'Local File',
            album: p.dirname(file.path!),
            localPath: file.path,
            sourceId: 'local',
            addedAt: now,
          ),
        )
        .toList(growable: false);

    await library.addTracks(tracks);

    messenger.showSnackBar(
      SnackBar(content: Text('Imported ${tracks.length} audio file(s).')),
    );
  }

  Future<void> _showSleepTimer(BuildContext context) async {
    final player = context.read<PlayerController>();
    final durations = <int>[5, 15, 30, 60, 90];

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.timer_off_outlined),
                title: const Text('Cancel sleep timer'),
                onTap: () {
                  player.cancelSleepTimer();
                  Navigator.of(context).pop();
                },
              ),
              for (final minutes in durations)
                ListTile(
                  leading: const Icon(Icons.bedtime_outlined),
                  title: Text('Stop playback in $minutes minutes'),
                  onTap: () {
                    player.startSleepTimer(Duration(minutes: minutes));
                    Navigator.of(context).pop();
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}

class _LibraryTab extends StatelessWidget {
  const _LibraryTab({
    required this.searchController,
    required this.query,
    required this.favoritesOnly,
    required this.onQueryChanged,
    required this.onFavoritesOnlyChanged,
    required this.onImport,
  });

  final TextEditingController searchController;
  final String query;
  final bool favoritesOnly;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<bool> onFavoritesOnlyChanged;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryStore>();
    final player = context.read<PlayerController>();
    final tracks = library.search(
      query,
      favoritesOnly: favoritesOnly,
    );

    if (!library.loaded) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: SearchBar(
            controller: searchController,
            hintText: 'Search title, artist, or album',
            leading: const Icon(Icons.search),
            trailing: <Widget>[
              IconButton(
                tooltip: favoritesOnly ? 'Showing favorites' : 'Show favorites',
                onPressed: () => onFavoritesOnlyChanged(!favoritesOnly),
                icon: Icon(
                  favoritesOnly ? Icons.favorite : Icons.favorite_border,
                ),
              ),
            ],
            onChanged: onQueryChanged,
          ),
        ),
        if (tracks.isEmpty)
          Expanded(
            child: _EmptyLibrary(
              favoritesOnly: favoritesOnly,
              onImport: onImport,
            ),
          )
        else
          Expanded(
            child: ListView.separated(
              itemCount: tracks.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final track = tracks[index];
                return TrackTile(
                  track: track,
                  onPlay: () => player.playTrack(track, queue: tracks),
                  onFavorite: () => library.toggleFavorite(track.id),
                  onRemove: () => library.removeTrack(track.id),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({
    required this.favoritesOnly,
    required this.onImport,
  });

  final bool favoritesOnly;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.music_note, size: 56),
            const SizedBox(height: 16),
            Text(
              favoritesOnly ? 'No favorite tracks yet' : 'Your library is empty',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              favoritesOnly
                  ? 'Favorite a track from your library to see it here.'
                  : 'Import local audio files to start using the real player.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onImport,
              icon: const Icon(Icons.library_add),
              label: const Text('Import audio'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourcesTab extends StatefulWidget {
  const _SourcesTab();

  @override
  State<_SourcesTab> createState() => _SourcesTabState();
}

class _SourcesTabState extends State<_SourcesTab> {
  final _provider = const DemoSourceProvider();
  List<Track> _demoTracks = <Track>[];

  @override
  void initState() {
    super.initState();
    _provider.search('').then((tracks) {
      if (mounted) {
        setState(() => _demoTracks = tracks);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text(
          'Provider plugins',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'AetherTune separates the open-source player from source adapters. Add legal providers for local files, self-hosted music, podcasts, radio, Internet Archive, or official APIs.',
        ),
        const SizedBox(height: 16),
        const _ProviderCard(
          title: 'Local Files',
          status: 'Enabled',
          description: 'Import and play files selected through the native picker.',
          icon: Icons.folder_open,
        ),
        _ProviderCard(
          title: _provider.name,
          status: 'Template',
          description: _provider.description,
          icon: Icons.code,
        ),
        const _ProviderCard(
          title: 'Jellyfin / Navidrome / Subsonic',
          status: 'Adapter roadmap',
          description: 'User-owned/self-hosted music server support belongs here.',
          icon: Icons.dns_outlined,
        ),
        const _ProviderCard(
          title: 'Podcasts / Radio / Internet Archive',
          status: 'Adapter roadmap',
          description: 'Open catalogs can provide discovery, streaming, and offline caching.',
          icon: Icons.public,
        ),
        const _ProviderCard(
          title: 'Commercial services',
          status: 'Official APIs only',
          description: 'No DRM bypass, scraping, or paid-service cloning is included.',
          icon: Icons.verified_user_outlined,
        ),
        const SizedBox(height: 16),
        Text('Demo provider tracks', style: Theme.of(context).textTheme.titleMedium),
        for (final track in _demoTracks)
          ListTile(
            leading: const Icon(Icons.music_note_outlined),
            title: Text(track.title),
            subtitle: Text('${track.artist} · ${track.album}'),
          ),
      ],
    );
  }
}

class _ProviderCard extends StatelessWidget {
  const _ProviderCard({
    required this.title,
    required this.status,
    required this.description,
    required this.icon,
  });

  final String title;
  final String status;
  final String description;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(description),
        trailing: Chip(label: Text(status)),
      ),
    );
  }
}

class _SettingsTab extends StatelessWidget {
  const _SettingsTab();

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text('Options', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        SwitchListTile(
          title: const Text('Shuffle queue'),
          subtitle: const Text('Randomize playback order when supported by the queue.'),
          value: player.shuffleEnabled,
          onChanged: player.setShuffleEnabled,
        ),
        ListTile(
          title: const Text('Repeat mode'),
          subtitle: Text(player.loopMode.name),
          trailing: DropdownButton<LoopMode>(
            value: player.loopMode,
            items: const <DropdownMenuItem<LoopMode>>[
              DropdownMenuItem(value: LoopMode.off, child: Text('Off')),
              DropdownMenuItem(value: LoopMode.one, child: Text('One')),
              DropdownMenuItem(value: LoopMode.all, child: Text('All')),
            ],
            onChanged: (mode) {
              if (mode != null) {
                player.setLoopMode(mode);
              }
            },
          ),
        ),
        const Divider(),
        const ListTile(
          leading: Icon(Icons.privacy_tip_outlined),
          title: Text('Privacy'),
          subtitle: Text('No ads, no telemetry, no forced account in the core app.'),
        ),
        const ListTile(
          leading: Icon(Icons.balance_outlined),
          title: Text('Legal source policy'),
          subtitle: Text('Provider adapters must use legal, documented, user-owned, or official APIs.'),
        ),
      ],
    );
  }
}
