import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/library_store.dart';
import '../data/radio_browser_provider.dart';
import '../domain/track.dart';

class RadioBrowserStationScreen extends StatefulWidget {
  const RadioBrowserStationScreen({
    super.key,
    required this.station,
    required this.provider,
    required this.onPlay,
    required this.onSave,
  });

  final RadioBrowserStation station;
  final RadioBrowserProvider provider;
  final Future<void> Function(Track track) onPlay;
  final Future<void> Function(Track track) onSave;

  @override
  State<RadioBrowserStationScreen> createState() =>
      _RadioBrowserStationScreenState();
}

class _RadioBrowserStationScreenState extends State<RadioBrowserStationScreen> {
  RadioBrowserStreamValidation? _validation;
  bool _validating = false;

  Track get _track => widget.station.toTrack(sourceId: widget.provider.id);

  @override
  Widget build(BuildContext context) {
    final station = widget.station;
    final offlineModeEnabled = context.watch<LibraryStore>().offlineModeEnabled;

    return Scaffold(
      appBar: AppBar(title: const Text('Station details')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text(station.name, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              Chip(
                avatar: Icon(
                  station.isOnline
                      ? Icons.check_circle_outline
                      : Icons.error_outline,
                ),
                label: Text(
                  station.isOnline
                      ? 'Directory status: online'
                      : 'Directory status: unavailable',
                ),
              ),
              if (station.countryCode.isNotEmpty)
                Chip(
                  avatar: const Icon(Icons.flag_outlined),
                  label: Text(station.countryCode),
                ),
              if (station.language.isNotEmpty)
                Chip(
                  avatar: const Icon(Icons.translate_outlined),
                  label: Text(station.language),
                ),
              if (station.codec.isNotEmpty)
                Chip(
                  avatar: const Icon(Icons.graphic_eq_outlined),
                  label: Text(
                    station.bitrateKbps > 0
                        ? '${station.codec} / ${station.bitrateKbps} kbps'
                        : station.codec,
                  ),
                ),
            ],
          ),
          if (station.tags.isNotEmpty) ...<Widget>[
            const SizedBox(height: 16),
            Text('Tags', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: station.tags
                  .map((tag) => Chip(label: Text(tag)))
                  .toList(growable: false),
            ),
          ],
          const SizedBox(height: 16),
          Text('Stream', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          SelectableText(station.streamUri.toString()),
          if (station.homepageUri != null) ...<Widget>[
            const SizedBox(height: 12),
            Text('Homepage', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            SelectableText(station.homepageUri.toString()),
          ],
          const SizedBox(height: 20),
          if (offlineModeEnabled)
            const ListTile(
              leading: Icon(Icons.cloud_off_outlined),
              title: Text('Offline mode is on'),
              subtitle: Text(
                'Station playback and stream validation are unavailable.',
              ),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              FilledButton.icon(
                key: const Key('radio-station-play'),
                onPressed: offlineModeEnabled ? null : _play,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Play station'),
              ),
              OutlinedButton.icon(
                key: const Key('radio-station-save'),
                onPressed: _save,
                icon: const Icon(Icons.library_add_outlined),
                label: const Text('Save station'),
              ),
              OutlinedButton.icon(
                key: const Key('radio-station-validate'),
                onPressed: offlineModeEnabled || _validating ? null : _validate,
                icon: _validating
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.network_check_outlined),
                label: const Text('Validate stream'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const ListTile(
            leading: Icon(Icons.do_not_disturb_on_outlined),
            title: Text('Live streams cannot be cached or downloaded'),
            subtitle: Text('AetherTune keeps Radio Browser streams live-only.'),
          ),
          if (_validation != null) ...<Widget>[
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(
                _validation!.isPlayable
                    ? Icons.check_circle_outline
                    : Icons.error_outline,
              ),
              title: Text(
                _validation!.isPlayable
                    ? 'Stream validated'
                    : 'Stream validation failed',
              ),
              subtitle: Text(_validationSummary(_validation!)),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _play() {
    return widget.onPlay(_track);
  }

  Future<void> _save() {
    return widget.onSave(_track);
  }

  Future<void> _validate() async {
    setState(() => _validating = true);
    final validation = await widget.provider.validateStream(_track);
    if (!mounted) {
      return;
    }
    setState(() {
      _validating = false;
      _validation = validation;
    });
  }

  String _validationSummary(RadioBrowserStreamValidation validation) {
    final parts = <String>[
      validation.reason,
      if (validation.statusCode != null) 'HTTP ${validation.statusCode}',
      if (validation.contentType != null && validation.contentType!.isNotEmpty)
        validation.contentType!,
    ];
    return parts.join(' / ');
  }
}
