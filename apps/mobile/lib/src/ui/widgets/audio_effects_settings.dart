import 'dart:async';

import 'package:flutter/material.dart';

import '../../player/playback_audio_effects.dart';
import '../../player/player_controller.dart';

class AudioEffectsSettingsTile extends StatelessWidget {
  const AudioEffectsSettingsTile({super.key, required this.player});

  final PlayerController player;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: const ValueKey<String>('audio-effects-settings-tile'),
      leading: const Icon(Icons.tune_outlined),
      title: const Text('Audio effects'),
      subtitle: Text(_audioEffectsSummary(player)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => showAudioEffectsSettingsDialog(context, player),
    );
  }
}

Future<void> showAudioEffectsSettingsDialog(
  BuildContext context,
  PlayerController player,
) {
  if (player.supportsEqualizer) {
    unawaited(player.refreshEqualizerBands());
  }
  return showDialog<void>(
    context: context,
    builder: (context) => _AudioEffectsDialog(player: player),
  );
}

class _AudioEffectsDialog extends StatelessWidget {
  const _AudioEffectsDialog({required this.player});

  final PlayerController player;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: player,
      builder: (context, _) {
        final mediaQuery = MediaQuery.of(context);
        return AlertDialog(
          title: const Text('Audio effects'),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 520,
              maxHeight: mediaQuery.size.height * 0.72,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (player.supportsEqualizer) ...<Widget>[
                    SwitchListTile(
                      key: const ValueKey<String>('equalizer-enabled-switch'),
                      contentPadding: EdgeInsets.zero,
                      secondary: const Icon(Icons.equalizer),
                      title: const Text('Equalizer'),
                      subtitle: Text(
                        _equalizerPresetLabel(player.equalizerPreset),
                      ),
                      value: player.equalizerEnabled,
                      onChanged: (enabled) => unawaited(
                        _showAudioEffectError(
                          context,
                          player.setEqualizerEnabled(enabled),
                        ),
                      ),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Preset'),
                      trailing: DropdownButton<PlaybackEqualizerPreset>(
                        key: const ValueKey<String>(
                          'equalizer-preset-dropdown',
                        ),
                        value: player.equalizerPreset,
                        items: <DropdownMenuItem<PlaybackEqualizerPreset>>[
                          for (final preset in PlaybackEqualizerPreset.values)
                            if (preset != PlaybackEqualizerPreset.custom ||
                                player.hasCustomEqualizerProfile)
                              DropdownMenuItem<PlaybackEqualizerPreset>(
                                value: preset,
                                child: Text(_equalizerPresetLabel(preset)),
                              ),
                        ],
                        onChanged: !player.equalizerEnabled
                            ? null
                            : (preset) {
                                if (preset != null) {
                                  unawaited(
                                    _showAudioEffectError(
                                      context,
                                      player.setEqualizerPreset(preset),
                                    ),
                                  );
                                }
                              },
                      ),
                    ),
                    if (player.equalizerBandsLoading)
                      const LinearProgressIndicator(
                        key: ValueKey<String>('equalizer-bands-loading'),
                      )
                    else if (player.equalizerBands.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'Start playback to edit this device\'s frequency bands.',
                        ),
                      )
                    else
                      for (final band in player.equalizerBands)
                        _EqualizerBandSlider(
                          key: ValueKey<int>(band.index),
                          player: player,
                          band: band,
                        ),
                  ],
                  if (player.supportsEqualizer &&
                      player.supportsLoudnessEnhancer)
                    const Divider(height: 32),
                  if (player.supportsLoudnessEnhancer) ...<Widget>[
                    SwitchListTile(
                      key: const ValueKey<String>(
                        'loudness-enhancer-enabled-switch',
                      ),
                      contentPadding: EdgeInsets.zero,
                      secondary: const Icon(Icons.volume_up_outlined),
                      title: const Text('Volume boost'),
                      subtitle: Text(
                        _formatGainDb(player.loudnessEnhancerTargetGainDb),
                      ),
                      value: player.loudnessEnhancerEnabled,
                      onChanged: (enabled) => unawaited(
                        _showAudioEffectError(
                          context,
                          player.setLoudnessEnhancerEnabled(enabled),
                        ),
                      ),
                    ),
                    Slider(
                      key: const ValueKey<String>(
                        'loudness-enhancer-gain-slider',
                      ),
                      min: PlayerController.minLoudnessEnhancerGainDb,
                      max: PlayerController.maxLoudnessEnhancerGainDb,
                      divisions: 24,
                      value: player.loudnessEnhancerTargetGainDb,
                      label: _formatGainDb(player.loudnessEnhancerTargetGainDb),
                      semanticFormatterCallback: (value) =>
                          'Volume boost ${_formatGainDb(value)}',
                      onChanged: !player.loudnessEnhancerEnabled
                          ? null
                          : (gainDb) => unawaited(
                              _showAudioEffectError(
                                context,
                                player.previewLoudnessEnhancerTargetGain(
                                  gainDb,
                                ),
                              ),
                            ),
                      onChangeEnd: !player.loudnessEnhancerEnabled
                          ? null
                          : (gainDb) => unawaited(
                              _showAudioEffectError(
                                context,
                                player.setLoudnessEnhancerTargetGain(gainDb),
                              ),
                            ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }
}

class _EqualizerBandSlider extends StatelessWidget {
  const _EqualizerBandSlider({
    super.key,
    required this.player,
    required this.band,
  });

  final PlayerController player;
  final PlaybackEqualizerBand band;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        SizedBox(
          width: 64,
          child: Text(_formatFrequency(band.centerFrequencyHz)),
        ),
        Expanded(
          child: Slider(
            min: band.minGainDb,
            max: band.maxGainDb,
            value: band.gainDb,
            label: _formatGainDb(band.gainDb),
            semanticFormatterCallback: (value) =>
                '${_formatFrequency(band.centerFrequencyHz)} '
                '${_formatGainDb(value)}',
            onChanged: !player.equalizerEnabled
                ? null
                : (gainDb) => unawaited(
                    _showAudioEffectError(
                      context,
                      player.previewEqualizerBandGain(band.index, gainDb),
                    ),
                  ),
            onChangeEnd: !player.equalizerEnabled
                ? null
                : (_) => unawaited(
                    _showAudioEffectError(
                      context,
                      player.persistEqualizerBandGains(),
                    ),
                  ),
          ),
        ),
        SizedBox(
          width: 56,
          child: Text(_formatGainDb(band.gainDb), textAlign: TextAlign.end),
        ),
      ],
    );
  }
}

Future<void> _showAudioEffectError(
  BuildContext context,
  Future<void> operation,
) async {
  try {
    await operation;
  } on Object catch (error) {
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('Could not update audio effects: $error')),
      );
  }
}

String _audioEffectsSummary(PlayerController player) {
  final active = <String>[];
  if (player.supportsEqualizer && player.equalizerEnabled) {
    active.add(_equalizerPresetLabel(player.equalizerPreset));
  }
  if (player.supportsLoudnessEnhancer && player.loudnessEnhancerEnabled) {
    active.add(
      'Volume boost ${_formatGainDb(player.loudnessEnhancerTargetGainDb)}',
    );
  }
  return active.isEmpty ? 'Off' : active.join(', ');
}

String _equalizerPresetLabel(PlaybackEqualizerPreset preset) {
  return switch (preset) {
    PlaybackEqualizerPreset.flat => 'Flat',
    PlaybackEqualizerPreset.bassBoost => 'Bass boost',
    PlaybackEqualizerPreset.vocal => 'Vocal',
    PlaybackEqualizerPreset.treble => 'Treble',
    PlaybackEqualizerPreset.custom => 'Custom',
  };
}

String _formatFrequency(double frequencyHz) {
  if (frequencyHz >= 1000) {
    final kilohertz = frequencyHz / 1000;
    return '${kilohertz >= 10 ? kilohertz.toStringAsFixed(0) : kilohertz.toStringAsFixed(1)} kHz';
  }
  return '${frequencyHz.round()} Hz';
}

String _formatGainDb(double gainDb) {
  final prefix = gainDb > 0 ? '+' : '';
  return '$prefix${gainDb.toStringAsFixed(1)} dB';
}
