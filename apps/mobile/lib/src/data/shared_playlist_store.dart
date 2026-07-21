import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/playlist.dart';
import '../domain/search_matcher.dart';
import 'library_store.dart';
import 'library_sync_client.dart';

typedef SharedPlaylistGatewayFactory = SharedPlaylistGateway Function();

class SharedPlaylistBinding {
  const SharedPlaylistBinding({
    required this.remoteId,
    required this.localPlaylistId,
    required this.revision,
    required this.role,
    this.updatedAt,
    this.updatedByDevice,
    this.collaborators = const <String, SharedPlaylistAccessRole>{},
    this.unavailableTrackCount = 0,
  });

  final String remoteId;
  final String localPlaylistId;
  final int revision;
  final SharedPlaylistAccessRole role;
  final DateTime? updatedAt;
  final String? updatedByDevice;
  final Map<String, SharedPlaylistAccessRole> collaborators;
  final int unavailableTrackCount;

  bool get canEdit => role != SharedPlaylistAccessRole.viewer;
  bool get isOwner => role == SharedPlaylistAccessRole.owner;

  SharedPlaylistBinding fromRemote(
    SharedPlaylistRemote remote, {
    int unavailableTrackCount = 0,
  }) {
    return SharedPlaylistBinding(
      remoteId: remote.id,
      localPlaylistId: localPlaylistId,
      revision: remote.revision,
      role: remote.role,
      updatedAt: remote.updatedAt,
      updatedByDevice: remote.updatedByDevice,
      collaborators: remote.collaborators,
      unavailableTrackCount: unavailableTrackCount,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'remoteId': remoteId,
    'localPlaylistId': localPlaylistId,
    'revision': revision,
    'role': role.name,
    'updatedAt': updatedAt?.toUtc().toIso8601String(),
    'updatedByDevice': updatedByDevice,
    'unavailableTrackCount': unavailableTrackCount,
    'collaborators': collaborators.map(
      (accountId, accessRole) => MapEntry<String, String>(
        accountId,
        accessRole.name,
      ),
    ),
  };

  static SharedPlaylistBinding? tryFromJson(Map<String, Object?> json) {
    final remoteId = json['remoteId'];
    final localPlaylistId = json['localPlaylistId'];
    final revision = json['revision'];
    final role = _roleFromName(json['role']);
    final collaborators = _collaboratorsFromJson(json['collaborators']);
    final unavailableTrackCount = json['unavailableTrackCount'] ?? 0;
    if (remoteId is! String ||
        !_isIdentifier(remoteId) ||
        localPlaylistId is! String ||
        localPlaylistId.trim().isEmpty ||
        revision is! int ||
        revision <= 0 ||
        role == null ||
        collaborators == null ||
        unavailableTrackCount is! int ||
        unavailableTrackCount < 0 ||
        unavailableTrackCount > 200 ||
        (role != SharedPlaylistAccessRole.owner && collaborators.isNotEmpty)) {
      return null;
    }
    return SharedPlaylistBinding(
      remoteId: remoteId,
      localPlaylistId: localPlaylistId,
      revision: revision,
      role: role,
      updatedAt: _optionalDate(json['updatedAt']),
      updatedByDevice: _optionalString(json['updatedByDevice']),
      collaborators: collaborators,
      unavailableTrackCount: unavailableTrackCount,
    );
  }
}

/// Links explicit local playlists to private, revisioned server playlists.
///
/// The binding persists only IDs, role, and metadata. Media URLs, local paths,
/// credentials, and playback state remain outside this feature.
class SharedPlaylistStore extends ChangeNotifier {
  SharedPlaylistStore({SharedPlaylistGatewayFactory? gatewayFactory})
      : _gatewayFactory = gatewayFactory;

  static const _metadataKey = 'aethertune.shared_playlists.v1';

  SharedPlaylistGatewayFactory? _gatewayFactory;
  final List<SharedPlaylistBinding> _bindings = <SharedPlaylistBinding>[];
  bool _loaded = false;
  bool _busy = false;
  String? _lastError;

  bool get loaded => _loaded;
  bool get busy => _busy;
  String? get lastError => _lastError;
  bool get available => _gatewayFactory != null;
  List<SharedPlaylistBinding> get bindings =>
      List<SharedPlaylistBinding>.unmodifiable(_bindings);

  void updateGatewayFactory(SharedPlaylistGatewayFactory? gatewayFactory) {
    if (identical(_gatewayFactory, gatewayFactory)) {
      return;
    }
    _gatewayFactory = gatewayFactory;
    notifyListeners();
  }

  Future<void> load() async {
    if (_loaded) {
      return;
    }
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_metadataKey);
      if (raw != null && raw.trim().isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is! List) {
          throw const FormatException('Shared playlist bindings must be a list.');
        }
        final seenRemoteIds = <String>{};
        final seenLocalIds = <String>{};
        for (final value in decoded.whereType<Map>()) {
          final binding = SharedPlaylistBinding.tryFromJson(
            Map<String, Object?>.from(value),
          );
          if (binding != null &&
              seenRemoteIds.add(binding.remoteId) &&
              seenLocalIds.add(binding.localPlaylistId)) {
            _bindings.add(binding);
          }
        }
      }
      _lastError = null;
    } on Object {
      _bindings.clear();
      _lastError = 'Could not load shared playlist settings.';
    } finally {
      _loaded = true;
      notifyListeners();
    }
  }

  SharedPlaylistBinding? bindingForLocalPlaylist(String playlistId) {
    for (final binding in _bindings) {
      if (binding.localPlaylistId == playlistId) {
        return binding;
      }
    }
    return null;
  }

  Future<SharedPlaylistBinding> host(
    LibraryStore library,
    Playlist playlist,
  ) {
    return _runBusy(() async {
      _requireOnline(library);
      if (bindingForLocalPlaylist(playlist.id) != null) {
        throw StateError('This playlist is already shared.');
      }
      final remote = await _requireGateway().createSharedPlaylist(
        name: playlist.name,
        trackIds: playlist.trackIds,
        trackReferences: _trackReferencesFor(library, playlist.trackIds),
      );
      final binding = SharedPlaylistBinding(
        remoteId: remote.id,
        localPlaylistId: playlist.id,
        revision: remote.revision,
        role: remote.role,
        updatedAt: remote.updatedAt,
        updatedByDevice: remote.updatedByDevice,
        collaborators: remote.collaborators,
      );
      await _addBinding(binding);
      return binding;
    });
  }

  Future<SharedPlaylistBinding> joinInvite(
    String inviteCode,
    LibraryStore library,
  ) {
    return _runBusy(() async {
      _requireOnline(library);
      final remote = await _requireGateway().joinSharedPlaylistInvite(inviteCode);
      final existing = _bindings.where((item) => item.remoteId == remote.id);
      if (existing.isNotEmpty) {
        final binding = existing.first;
        await _applyRemote(binding, remote, library);
        return bindingForLocalPlaylist(binding.localPlaylistId)!;
      }
      final playlist = await library.createPlaylist(remote.name);
      final resolution = _trackResolutionForRemote(library, remote);
      await library.replacePlaylistTracks(
        playlist.id,
        resolution.trackIds,
      );
      final binding = SharedPlaylistBinding(
        remoteId: remote.id,
        localPlaylistId: playlist.id,
        revision: remote.revision,
        role: remote.role,
        updatedAt: remote.updatedAt,
        updatedByDevice: remote.updatedByDevice,
        collaborators: remote.collaborators,
        unavailableTrackCount: resolution.unavailableTrackCount,
      );
      await _addBinding(binding);
      return binding;
    });
  }

  Future<SharedPlaylistBinding> refresh(
    SharedPlaylistBinding binding,
    LibraryStore library,
  ) {
    return _runBusy(() async {
      _requireOnline(library);
      final remote = await _requireGateway().fetchSharedPlaylist(binding.remoteId);
      await _applyRemote(binding, remote, library);
      return bindingForLocalPlaylist(binding.localPlaylistId)!;
    });
  }

  Future<List<SharedPlaylistRevision>> history(
    SharedPlaylistBinding binding,
    LibraryStore library,
  ) {
    return _runBusy(() async {
      _requireOnline(library);
      return _requireGateway().fetchSharedPlaylistHistory(binding.remoteId);
    });
  }

  Future<SharedPlaylistBinding> restoreRevision(
    SharedPlaylistBinding binding,
    SharedPlaylistRevision revision,
    LibraryStore library,
  ) {
    return _runBusy(() async {
      _requireOnline(library);
      if (!binding.canEdit) {
        throw StateError('This shared playlist is view-only.');
      }
      if (revision.revision >= binding.revision) {
        throw StateError('Only an earlier playlist revision can be restored.');
      }
      final remote = await _requireGateway().updateSharedPlaylist(
        playlistId: binding.remoteId,
        baseRevision: binding.revision,
        name: revision.name,
        trackIds: revision.trackIds,
        trackReferences: revision.trackReferences,
      );
      await _applyRemote(binding, remote, library);
      return bindingForLocalPlaylist(binding.localPlaylistId)!;
    });
  }

  Future<SharedPlaylistBinding> mergeAndPublish(
    SharedPlaylistBinding binding,
    LibraryStore library, {
    required bool preferLocalName,
  }) {
    return _runBusy(() async {
      _requireOnline(library);
      if (!binding.canEdit) {
        throw StateError('This shared playlist is view-only.');
      }
      final playlist = library.playlistById(binding.localPlaylistId);
      if (playlist == null) {
        throw StateError('The linked local playlist no longer exists.');
      }
      final current = await _requireGateway().fetchSharedPlaylist(
        binding.remoteId,
      );
      if (!current.canEdit) {
        throw StateError('This shared playlist is view-only.');
      }
      final localReferences = _trackReferencesFor(library, playlist.trackIds);
      final remote = await _requireGateway().updateSharedPlaylist(
        playlistId: binding.remoteId,
        baseRevision: current.revision,
        name: preferLocalName ? playlist.name : current.name,
        trackIds: current.trackReferences == null
            ? mergeSharedPlaylistTrackIds(current.trackIds, playlist.trackIds)
            : const <String>[],
        trackReferences: current.trackReferences == null
            ? null
            : mergeSharedPlaylistTrackReferences(
                current.trackReferences!,
                localReferences,
              ),
      );
      await _applyRemote(binding, remote, library);
      return bindingForLocalPlaylist(binding.localPlaylistId)!;
    });
  }

  Future<SharedPlaylistBinding> publish(
    SharedPlaylistBinding binding,
    LibraryStore library,
  ) {
    return _runBusy(() async {
      _requireOnline(library);
      if (!binding.canEdit) {
        throw StateError('This shared playlist is view-only.');
      }
      final playlist = library.playlistById(binding.localPlaylistId);
      if (playlist == null) {
        throw StateError('The linked local playlist no longer exists.');
      }
      final remote = await _requireGateway().updateSharedPlaylist(
        playlistId: binding.remoteId,
        baseRevision: binding.revision,
        name: playlist.name,
        trackIds: playlist.trackIds,
        trackReferences: _trackReferencesFor(library, playlist.trackIds),
      );
      await _replaceBinding(binding.fromRemote(remote));
      return bindingForLocalPlaylist(binding.localPlaylistId)!;
    });
  }

  Future<SharedPlaylistInvitation> createInvite(
    SharedPlaylistBinding binding,
    SharedPlaylistAccessRole role,
  ) {
    return _runBusy(() async {
      if (!binding.isOwner) {
        throw StateError('Only the shared playlist owner can create invitations.');
      }
      return _requireGateway().issueSharedPlaylistInvite(
        playlistId: binding.remoteId,
        role: role,
      );
    });
  }

  Future<int> invalidateUnusedInvites(
    SharedPlaylistBinding binding,
    LibraryStore library,
  ) {
    return _runBusy(() async {
      _requireOnline(library);
      if (!binding.isOwner) {
        throw StateError('Only the shared playlist owner can rotate invitations.');
      }
      return _requireGateway().invalidateSharedPlaylistInvites(
        playlistId: binding.remoteId,
      );
    });
  }

  Future<SharedPlaylistBinding> revokeCollaborator(
    SharedPlaylistBinding binding,
    String collaboratorId,
    LibraryStore library,
  ) {
    return _runBusy(() async {
      _requireOnline(library);
      if (!binding.isOwner) {
        throw StateError('Only the shared playlist owner can revoke access.');
      }
      final normalizedCollaboratorId = collaboratorId.trim();
      if (!binding.collaborators.containsKey(normalizedCollaboratorId)) {
        throw StateError('That collaborator no longer has access.');
      }
      final remote = await _requireGateway().revokeSharedPlaylistCollaborator(
        playlistId: binding.remoteId,
        collaboratorId: normalizedCollaboratorId,
        baseRevision: binding.revision,
      );
      await _replaceBinding(
        binding.fromRemote(
          remote,
          unavailableTrackCount: binding.unavailableTrackCount,
        ),
      );
      return bindingForLocalPlaylist(binding.localPlaylistId)!;
    });
  }

  Future<void> deleteHosted(
    SharedPlaylistBinding binding,
    LibraryStore library,
  ) {
    return _runBusy(() async {
      _requireOnline(library);
      if (!binding.isOwner) {
        throw StateError('Only the shared playlist owner can delete it.');
      }
      await _requireGateway().deleteSharedPlaylist(
        playlistId: binding.remoteId,
        baseRevision: binding.revision,
      );
      await _removeBinding(binding);
    });
  }

  Future<void> unlink(SharedPlaylistBinding binding) {
    return _runBusy(() => _removeBinding(binding));
  }

  Future<void> _applyRemote(
    SharedPlaylistBinding binding,
    SharedPlaylistRemote remote,
    LibraryStore library,
  ) async {
    final playlist = library.playlistById(binding.localPlaylistId);
    if (playlist == null) {
      throw StateError('The linked local playlist no longer exists.');
    }
    if (playlist.name != remote.name) {
      await library.renamePlaylist(playlist.id, remote.name);
    }
    final resolution = _trackResolutionForRemote(library, remote);
    await library.replacePlaylistTracks(playlist.id, resolution.trackIds);
    await _replaceBinding(
      binding.fromRemote(
        remote,
        unavailableTrackCount: resolution.unavailableTrackCount,
      ),
    );
  }

  SharedPlaylistGateway _requireGateway() {
    final factory = _gatewayFactory;
    if (factory == null) {
      throw StateError('Configure a library sync server first.');
    }
    return factory();
  }

  void _requireOnline(LibraryStore library) {
    if (library.offlineModeEnabled) {
      throw StateError('Turn off offline mode before using shared playlists.');
    }
  }

  List<SharedPlaylistTrackReference> _trackReferencesFor(
    LibraryStore library,
    List<String> trackIds,
  ) {
    final tracksById = {
      for (final track in library.tracks) track.id: track,
    };
    final references = <SharedPlaylistTrackReference>[];
    for (final trackId in trackIds) {
      final track = tracksById[trackId];
      if (track == null) {
        throw StateError('A shared playlist track is unavailable locally.');
      }
      references.add(
        SharedPlaylistTrackReference(
          title: track.title.trim(),
          artist: track.artist.trim(),
          album: track.album.trim(),
          durationMilliseconds: track.duration.inMilliseconds,
        ),
      );
    }
    return List<SharedPlaylistTrackReference>.unmodifiable(references);
  }

  _SharedPlaylistTrackResolution _trackResolutionForRemote(
    LibraryStore library,
    SharedPlaylistRemote remote,
  ) {
    final references = remote.trackReferences;
    if (references == null) {
      return _SharedPlaylistTrackResolution(
        trackIds: remote.trackIds,
        unavailableTrackCount: 0,
      );
    }
    final resolved = <String>[];
    for (final reference in references) {
      final candidates = library.tracks.where((track) {
        if (normalizeSearchText(track.title) != normalizeSearchText(reference.title) ||
            normalizeSearchText(track.artist) != normalizeSearchText(reference.artist) ||
            normalizeSearchText(track.album) != normalizeSearchText(reference.album)) {
          return false;
        }
        return reference.durationMilliseconds == 0 ||
            (track.duration.inMilliseconds - reference.durationMilliseconds).abs() <= 2000;
      }).toList(growable: false);
      if (candidates.length == 1) {
        resolved.add(candidates.single.id);
      }
    }
    return _SharedPlaylistTrackResolution(
      trackIds: resolved,
      unavailableTrackCount: references.length - resolved.length,
    );
  }

  Future<void> _addBinding(SharedPlaylistBinding binding) async {
    _bindings.add(binding);
    await _save();
    notifyListeners();
  }

  Future<void> _replaceBinding(SharedPlaylistBinding updated) async {
    final index = _bindings.indexWhere(
      (binding) => binding.remoteId == updated.remoteId,
    );
    if (index == -1) {
      throw StateError('Shared playlist binding no longer exists.');
    }
    _bindings[index] = updated;
    await _save();
    notifyListeners();
  }

  Future<void> _removeBinding(SharedPlaylistBinding binding) async {
    _bindings.removeWhere((item) => item.remoteId == binding.remoteId);
    await _save();
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _metadataKey,
      jsonEncode(_bindings.map((binding) => binding.toJson()).toList()),
    );
  }

  Future<T> _runBusy<T>(Future<T> Function() action) async {
    if (_busy) {
      throw StateError('A shared playlist operation is already running.');
    }
    _busy = true;
    _lastError = null;
    notifyListeners();
    try {
      return await action();
    } on Object catch (error) {
      _lastError = error.toString();
      rethrow;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}

class _SharedPlaylistTrackResolution {
  const _SharedPlaylistTrackResolution({
    required this.trackIds,
    required this.unavailableTrackCount,
  });

  final List<String> trackIds;
  final int unavailableTrackCount;
}

SharedPlaylistAccessRole? _roleFromName(Object? value) => switch (value) {
  'owner' => SharedPlaylistAccessRole.owner,
  'editor' => SharedPlaylistAccessRole.editor,
  'viewer' => SharedPlaylistAccessRole.viewer,
  _ => null,
};

Map<String, SharedPlaylistAccessRole>? _collaboratorsFromJson(Object? value) {
  if (value == null) {
    return const <String, SharedPlaylistAccessRole>{};
  }
  if (value is! Map) {
    return null;
  }
  final collaborators = <String, SharedPlaylistAccessRole>{};
  for (final entry in value.entries) {
    final accountId = entry.key;
    final role = _roleFromName(entry.value);
    if (accountId is! String ||
        accountId.trim().isEmpty ||
        accountId.length > 256 ||
        role == null ||
        role == SharedPlaylistAccessRole.owner) {
      return null;
    }
    collaborators[accountId] = role;
  }
  return Map<String, SharedPlaylistAccessRole>.unmodifiable(collaborators);
}

String? _optionalString(Object? value) {
  final normalized = value?.toString().trim() ?? '';
  return normalized.isEmpty ? null : normalized;
}

DateTime? _optionalDate(Object? value) {
  final text = _optionalString(value);
  return text == null ? null : DateTime.tryParse(text)?.toUtc();
}

bool _isIdentifier(String value) =>
    RegExp(r'^[A-Za-z0-9_-]{24}$').hasMatch(value);

/// Produces a non-destructive ordered merge for a shared playlist.
///
/// The current server order remains first. Only local occurrences beyond the
/// server's occurrence counts are appended, so this operation cannot silently
/// delete a collaborator's tracks or reshuffle their sequence.
List<String> mergeSharedPlaylistTrackIds(
  List<String> serverTrackIds,
  List<String> localTrackIds,
) {
  final remainingServerOccurrences = <String, int>{};
  for (final trackId in serverTrackIds) {
    remainingServerOccurrences[trackId] =
        (remainingServerOccurrences[trackId] ?? 0) + 1;
  }
  final merged = <String>[...serverTrackIds];
  for (final trackId in localTrackIds) {
    final remaining = remainingServerOccurrences[trackId] ?? 0;
    if (remaining > 0) {
      remainingServerOccurrences[trackId] = remaining - 1;
    } else {
      merged.add(trackId);
    }
  }
  return List<String>.unmodifiable(merged);
}

/// Merges portable references using their normalized metadata identity.
List<SharedPlaylistTrackReference> mergeSharedPlaylistTrackReferences(
  List<SharedPlaylistTrackReference> serverReferences,
  List<SharedPlaylistTrackReference> localReferences,
) {
  final remainingServerOccurrences = <String, int>{};
  for (final reference in serverReferences) {
    final key = _sharedPlaylistTrackReferenceKey(reference);
    remainingServerOccurrences[key] = (remainingServerOccurrences[key] ?? 0) + 1;
  }
  final merged = <SharedPlaylistTrackReference>[...serverReferences];
  for (final reference in localReferences) {
    final key = _sharedPlaylistTrackReferenceKey(reference);
    final remaining = remainingServerOccurrences[key] ?? 0;
    if (remaining > 0) {
      remainingServerOccurrences[key] = remaining - 1;
    } else {
      merged.add(reference);
    }
  }
  return List<SharedPlaylistTrackReference>.unmodifiable(merged);
}

String _sharedPlaylistTrackReferenceKey(
  SharedPlaylistTrackReference reference,
) => '${normalizeSearchText(reference.title)}\u0000'
    '${normalizeSearchText(reference.artist)}\u0000'
    '${normalizeSearchText(reference.album)}\u0000'
    '${reference.durationMilliseconds}';
