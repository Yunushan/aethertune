part of 'home_screen.dart';

mixin _SourcesRadioSection on State<_SourcesTab> {
  RadioBrowserProvider get _radioProvider;
  bool _offlineModeBlocksSourceNetwork(BuildContext context);
  bool _offlineModeBlocksStream(BuildContext context, Track track);

  final _radioSearchController = TextEditingController();
  final _radioCountryCodeController = TextEditingController();
  final _radioLanguageController = TextEditingController();
  final _radioTagController = TextEditingController();
  final _radioCodecController = TextEditingController();
  final _radioMinBitrateController = TextEditingController();
  final _radioMaxBitrateController = TextEditingController();
  List<Track> _radioTracks = <Track>[];
  List<RadioBrowserStation> _radioStations = <RadioBrowserStation>[];
  int _radioNextOffset = 0;
  int _radioRequestSerial = 0;
  bool _radioHasMore = false;
  bool _radioLoading = false;
  bool _radioLoadingMore = false;
  String? _radioError;
  String? _radioLoadMoreError;

  void _disposeRadioBrowserSection() {
    _radioSearchController.dispose();
    _radioCountryCodeController.dispose();
    _radioLanguageController.dispose();
    _radioTagController.dispose();
    _radioCodecController.dispose();
    _radioMinBitrateController.dispose();
    _radioMaxBitrateController.dispose();
  }

  List<Widget> _radioBrowserSectionWidgets(
    BuildContext context, {
    required bool offlineModeEnabled,
  }) {
    return <Widget>[
      const SizedBox(height: 16),
      Text(
        'Radio Browser search',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
      Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: _radioSearchController,
              enabled: !offlineModeEnabled,
              decoration: const InputDecoration(
                labelText: 'Station search',
                prefixIcon: Icon(Icons.search),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: offlineModeEnabled
                  ? null
                  : (_) => _searchRadioStations(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            tooltip: 'Search stations',
            onPressed: _radioLoading || _radioLoadingMore || offlineModeEnabled
                ? null
                : _searchRadioStations,
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
          _radioFilterField(
            controller: _radioCountryCodeController,
            labelText: 'Country',
            icon: Icons.flag_outlined,
            textCapitalization: TextCapitalization.characters,
          ),
          _radioFilterField(
            controller: _radioLanguageController,
            labelText: 'Language',
            icon: Icons.translate_outlined,
          ),
          _radioFilterField(
            controller: _radioTagController,
            labelText: 'Tag',
            icon: Icons.sell_outlined,
          ),
          _radioFilterField(
            controller: _radioCodecController,
            labelText: 'Codec',
            icon: Icons.graphic_eq_outlined,
            textCapitalization: TextCapitalization.characters,
          ),
          _radioFilterField(
            controller: _radioMinBitrateController,
            labelText: 'Min kbps',
            icon: Icons.speed_outlined,
            keyboardType: TextInputType.number,
          ),
          _radioFilterField(
            controller: _radioMaxBitrateController,
            labelText: 'Max kbps',
            icon: Icons.speed,
            keyboardType: TextInputType.number,
          ),
          OutlinedButton.icon(
            onPressed: _clearRadioFilters,
            icon: const Icon(Icons.filter_alt_off_outlined),
            label: const Text('Clear'),
          ),
        ],
      ),
      if (_radioLoading) ...<Widget>[
        const SizedBox(height: 12),
        const LinearProgressIndicator(),
      ],
      if (_radioError != null) ...<Widget>[
        const SizedBox(height: 8),
        ListTile(
          leading: const Icon(Icons.error_outline),
          title: const Text('Radio search failed'),
          subtitle: Text(_radioError!),
        ),
      ] else if (_radioStations.isEmpty && !_radioLoading) ...<Widget>[
        const SizedBox(height: 8),
        const ListTile(
          leading: Icon(Icons.radio_outlined),
          title: Text('No stations loaded'),
          subtitle: Text(
            'Search by station name, country, language, tag, codec, or '
            'bitrate.',
          ),
        ),
      ] else ...<Widget>[
        const SizedBox(height: 8),
        for (final station in _radioStations)
          ListTile(
            leading: const Icon(Icons.radio_outlined),
            title: Text(station.name),
            subtitle: Text(_radioStationSummary(station)),
            onTap: () => _openRadioStation(context, station),
            trailing: const Icon(Icons.chevron_right),
          ),
      ],
      if (_radioLoadingMore) ...<Widget>[
        const SizedBox(height: 12),
        const LinearProgressIndicator(),
      ],
      if (_radioLoadMoreError != null) ...<Widget>[
        const SizedBox(height: 8),
        ListTile(
          leading: const Icon(Icons.error_outline),
          title: const Text('Could not load more stations'),
          subtitle: Text(_radioLoadMoreError!),
          trailing: IconButton(
            tooltip: 'Retry loading stations',
            onPressed: _radioLoadingMore || offlineModeEnabled
                ? null
                : _loadMoreRadioStations,
            icon: const Icon(Icons.refresh),
          ),
        ),
      ],
      if (_radioStations.isNotEmpty && _radioHasMore) ...<Widget>[
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _radioLoading || _radioLoadingMore || offlineModeEnabled
                ? null
                : _loadMoreRadioStations,
            icon: const Icon(Icons.expand_more),
            label: const Text('Load more stations'),
          ),
        ),
      ],
    ];
  }

  Widget _radioFilterField({
    required TextEditingController controller,
    required String labelText,
    required IconData icon,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) {
    return SizedBox(
      width: 156,
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: labelText,
          prefixIcon: Icon(icon),
        ),
        keyboardType: keyboardType,
        textCapitalization: textCapitalization,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _searchRadioStations(),
      ),
    );
  }

  RadioBrowserSearchFilters _radioFilters() {
    return RadioBrowserSearchFilters(
      countryCode: _radioCountryCodeController.text,
      language: _radioLanguageController.text,
      tag: _radioTagController.text,
      codec: _radioCodecController.text,
      minBitrateKbps: _positiveInt(_radioMinBitrateController.text),
      maxBitrateKbps: _positiveInt(_radioMaxBitrateController.text),
    );
  }

  int? _positiveInt(String value) {
    final parsed = int.tryParse(value.trim());
    if (parsed == null || parsed <= 0) {
      return null;
    }

    return parsed;
  }

  void _clearRadioFilters() {
    _radioCountryCodeController.clear();
    _radioLanguageController.clear();
    _radioTagController.clear();
    _radioCodecController.clear();
    _radioMinBitrateController.clear();
    _radioMaxBitrateController.clear();
  }

  Future<void> _searchRadioStations() async {
    if (_radioLoading || _radioLoadingMore) {
      return;
    }

    if (_offlineModeBlocksSourceNetwork(context)) {
      setState(() {
        _radioRequestSerial += 1;
        _radioTracks = <Track>[];
        _radioStations = <RadioBrowserStation>[];
        _radioNextOffset = 0;
        _radioHasMore = false;
        _radioLoading = false;
        _radioLoadingMore = false;
        _radioError = 'Offline mode is on.';
        _radioLoadMoreError = null;
      });
      return;
    }

    final requestSerial = ++_radioRequestSerial;
    setState(() {
      _radioLoading = true;
      _radioError = null;
      _radioLoadMoreError = null;
      _radioHasMore = false;
    });

    try {
      final page = await _radioProvider.searchStationPage(
        _radioSearchController.text,
        filters: _radioFilters(),
      );
      if (!mounted || requestSerial != _radioRequestSerial) {
        return;
      }

      setState(() {
        _radioTracks = page.tracks;
        _radioStations = page.stations;
        _radioNextOffset = page.nextOffset;
        _radioHasMore = page.hasMore;
        _radioLoading = false;
      });
    } catch (error) {
      if (!mounted || requestSerial != _radioRequestSerial) {
        return;
      }

      setState(() {
        _radioTracks = <Track>[];
        _radioStations = <RadioBrowserStation>[];
        _radioNextOffset = 0;
        _radioHasMore = false;
        _radioLoading = false;
        _radioError = error.toString();
      });
    }
  }

  Future<void> _loadMoreRadioStations() async {
    if (_radioLoading || _radioLoadingMore || !_radioHasMore) {
      return;
    }

    if (_offlineModeBlocksSourceNetwork(context)) {
      setState(() => _radioLoadMoreError = 'Offline mode is on.');
      return;
    }

    final requestSerial = _radioRequestSerial;
    final offset = _radioNextOffset;
    final query = _radioSearchController.text;
    final filters = _radioFilters();
    setState(() {
      _radioLoadingMore = true;
      _radioLoadMoreError = null;
    });

    try {
      final page = await _radioProvider.searchStationPage(
        query,
        filters: filters,
        offset: offset,
      );
      if (!mounted || requestSerial != _radioRequestSerial) {
        return;
      }

      setState(() {
        _radioStations = _mergeRadioStations(_radioStations, page.stations);
        _radioTracks = _mergeRadioTracks(_radioTracks, page.tracks);
        _radioNextOffset = page.nextOffset;
        _radioHasMore = page.hasMore;
        _radioLoadingMore = false;
      });
    } catch (error) {
      if (!mounted || requestSerial != _radioRequestSerial) {
        return;
      }

      setState(() {
        _radioLoadingMore = false;
        _radioLoadMoreError = error.toString();
      });
    }
  }

  List<RadioBrowserStation> _mergeRadioStations(
    List<RadioBrowserStation> current,
    List<RadioBrowserStation> incoming,
  ) {
    final keys = current
        .map((station) => '${station.stationUuid}|${station.streamUri}')
        .toSet();
    return <RadioBrowserStation>[
      ...current,
      ...incoming.where(
        (station) => keys.add('${station.stationUuid}|${station.streamUri}'),
      ),
    ];
  }

  List<Track> _mergeRadioTracks(List<Track> current, List<Track> incoming) {
    final ids = current.map((track) => track.id).toSet();
    return <Track>[...current, ...incoming.where((track) => ids.add(track.id))];
  }

  Future<void> _playRadioStation(BuildContext context, Track track) async {
    if (_offlineModeBlocksStream(context, track)) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final player = context.read<PlayerController>();

    try {
      await player.playTrack(track, queue: _radioTracks);
    } catch (_) {
      if (!context.mounted) {
        return;
      }

      messenger.showSnackBar(
        SnackBar(content: Text('Could not play ${track.title}.')),
      );
    }
  }

  String _radioStationSummary(RadioBrowserStation station) {
    final parts = <String>[
      if (station.countryCode.isNotEmpty) station.countryCode,
      if (station.language.isNotEmpty) station.language,
      if (station.codec.isNotEmpty) station.codec,
      if (station.bitrateKbps > 0) '${station.bitrateKbps} kbps',
    ];
    return parts.isEmpty ? 'Station details' : parts.join(' / ');
  }

  Future<void> _openRadioStation(
    BuildContext context,
    RadioBrowserStation station,
  ) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => RadioBrowserStationScreen(
          station: station,
          provider: _radioProvider,
          onPlay: (track) => _playRadioStation(context, track),
          onSave: (track) => _saveRadioStation(context, track),
        ),
      ),
    );
  }

  Future<void> _saveRadioStation(BuildContext context, Track track) async {
    final library = context.read<LibraryStore>();
    final messenger = ScaffoldMessenger.of(context);

    await library.addTracks(<Track>[track]);

    if (!context.mounted) {
      return;
    }

    messenger.showSnackBar(SnackBar(content: Text('Saved ${track.title}.')));
  }
}
