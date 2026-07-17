import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/playlist.dart';
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
  });

  final String remoteId;
  final String localPlaylistId;
  final int revision;
  final SharedPlaylistAccessRole role;
  final DateTime? updatedAt;
  final String? updatedByDevice;
  final Map<String, SharedPlaylistAccessRole> collaborators;

  bool get canEdit => role != SharedPlaylistAccessRole.viewer;
  bool get isOwner => role == SharedPlaylistAccessRole.owner;

  SharedPlaylistBinding fromRemote(SharedPlaylistRemote remote) {
    return SharedPlaylistBinding(
      remoteId: remote.id,
      localPlaylistId: localPlaylistId,
      revision: remote.revision,
      role: remote.role,
      updatedAt: remote.updatedAt,
      updatedByDevice: remote.updatedByDevice,
      collaborators: remote.collaborators,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'remoteId': remoteId,
    'localPlaylistId': localPlaylistId,
    'revision': revision,
    'role': role.name,
    'updatedAt': updatedAt?.toUtc().toIso8601String(),
    'updatedByDevice': updatedByDevice,
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
    if (remoteId is! String ||
        !_isIdentifier(remoteId) ||
        localPlaylistId is! String ||
        localPlaylistId.trim().isEmpty ||
        revision is! int ||
        revision <= 0 ||
        role == null ||
        collaborators == null ||
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
      await library.replacePlaylistTracks(playlist.id, remote.trackIds);
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
      );
      await _replaceBinding(binding.fromRemote(remote));
      return bindingForLocalPlaylist(binding.localPlaylistId)!;
    });
  }

  Future<String> createInvite(
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
      await _replaceBinding(binding.fromRemote(remote));
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
    await library.replacePlaylistTracks(playlist.id, remote.trackIds);
    await _replaceBinding(binding.fromRemote(remote));
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
