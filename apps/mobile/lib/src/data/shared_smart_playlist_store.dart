import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'library_store.dart';
import 'library_sync_client.dart';
import 'provider_credential_vault.dart';

typedef SharedSmartPlaylistGatewayFactory = SharedSmartPlaylistGateway
    Function();

class SharedSmartPlaylistBinding {
  const SharedSmartPlaylistBinding({
    required this.remoteId,
    required this.localSmartPlaylistId,
    required this.revision,
    required this.role,
    this.updatedAt,
    this.updatedByDevice,
  });

  final String remoteId;
  final String localSmartPlaylistId;
  final int revision;
  final SharedPlaylistAccessRole role;
  final DateTime? updatedAt;
  final String? updatedByDevice;

  bool get canEdit => role != SharedPlaylistAccessRole.viewer;
  bool get isOwner => role == SharedPlaylistAccessRole.owner;

  SharedSmartPlaylistBinding fromRemote(SharedPlaylistRemote remote) {
    if (remote.kind != SharedPlaylistKind.smart) {
      throw const FormatException('Shared playlist is not a smart playlist.');
    }
    return SharedSmartPlaylistBinding(
      remoteId: remote.id,
      localSmartPlaylistId: localSmartPlaylistId,
      revision: remote.revision,
      role: remote.role,
      updatedAt: remote.updatedAt,
      updatedByDevice: remote.updatedByDevice,
    );
  }

  SharedSmartPlaylistBinding withRevision(int value) {
    if (value <= revision) {
      throw const FormatException('Shared smart-playlist revision is invalid.');
    }
    return SharedSmartPlaylistBinding(
      remoteId: remoteId,
      localSmartPlaylistId: localSmartPlaylistId,
      revision: value,
      role: role,
      updatedAt: updatedAt,
      updatedByDevice: updatedByDevice,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'remoteId': remoteId,
    'localSmartPlaylistId': localSmartPlaylistId,
    'revision': revision,
    'role': role.name,
    'updatedAt': updatedAt?.toUtc().toIso8601String(),
    'updatedByDevice': updatedByDevice,
  };

  static SharedSmartPlaylistBinding? tryFromJson(Map<String, Object?> json) {
    final remoteId = json['remoteId'];
    final localId = json['localSmartPlaylistId'];
    final revision = json['revision'];
    final role = _roleFromJson(json['role']);
    if (remoteId is! String ||
        !_isIdentifier(remoteId) ||
        localId is! String ||
        localId.trim().isEmpty ||
        revision is! int ||
        revision <= 0 ||
        role == null) {
      return null;
    }
    return SharedSmartPlaylistBinding(
      remoteId: remoteId,
      localSmartPlaylistId: localId,
      revision: revision,
      role: role,
      updatedAt: _optionalDate(json['updatedAt']),
      updatedByDevice: _optionalText(json['updatedByDevice']),
    );
  }
}

/// A local smart playlist that the user explicitly chose to refresh from a
/// public link. The link itself is retained only in the credential vault.
class PublicSmartPlaylistSubscription {
  const PublicSmartPlaylistSubscription({
    required this.id,
    required this.remoteId,
    required this.localSmartPlaylistId,
    required this.revision,
  });

  final String id;
  final String remoteId;
  final String localSmartPlaylistId;
  final int revision;

  PublicSmartPlaylistSubscription withRevision(int value) {
    if (value < revision || value <= 0) {
      throw const FormatException('Public smart-playlist revision is invalid.');
    }
    return PublicSmartPlaylistSubscription(
      id: id,
      remoteId: remoteId,
      localSmartPlaylistId: localSmartPlaylistId,
      revision: value,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'remoteId': remoteId,
    'localSmartPlaylistId': localSmartPlaylistId,
    'revision': revision,
  };

  static PublicSmartPlaylistSubscription? tryFromJson(
    Map<String, Object?> json,
  ) {
    final id = json['id'];
    final remoteId = json['remoteId'];
    final localId = json['localSmartPlaylistId'];
    final revision = json['revision'];
    if (id is! String ||
        !_isPublicSubscriptionId(id) ||
        remoteId is! String ||
        !_isIdentifier(remoteId) ||
        localId is! String ||
        localId.trim().isEmpty ||
        revision is! int ||
        revision <= 0) {
      return null;
    }
    return PublicSmartPlaylistSubscription(
      id: id,
      remoteId: remoteId,
      localSmartPlaylistId: localId,
      revision: revision,
    );
  }
}

/// Links local dynamic rules to a private, revisioned shared smart playlist.
///
/// Only rule definitions cross the network. Every collaborator evaluates the
/// rules against their own local library, which may produce a different queue.
class SharedSmartPlaylistStore extends ChangeNotifier {
  SharedSmartPlaylistStore({
    SharedSmartPlaylistGatewayFactory? gatewayFactory,
    ProviderCredentialVault? publicLinkVault,
  }) : _gatewayFactory = gatewayFactory,
       _publicLinkVault = publicLinkVault ?? SecureProviderCredentialVault();

  static const _metadataKey = 'aethertune.shared_smart_playlists.v1';
  static const _publicLinkCredentialPrefix =
      'public-smart-playlist-link.';

  SharedSmartPlaylistGatewayFactory? _gatewayFactory;
  final ProviderCredentialVault _publicLinkVault;
  final List<SharedSmartPlaylistBinding> _bindings =
      <SharedSmartPlaylistBinding>[];
  final List<PublicSmartPlaylistSubscription> _publicSubscriptions =
      <PublicSmartPlaylistSubscription>[];
  bool _loaded = false;
  bool _busy = false;
  String? _lastError;

  bool get loaded => _loaded;
  bool get busy => _busy;
  bool get available => _gatewayFactory != null;
  String? get lastError => _lastError;
  List<SharedSmartPlaylistBinding> get bindings =>
      List<SharedSmartPlaylistBinding>.unmodifiable(_bindings);
  List<PublicSmartPlaylistSubscription> get publicSubscriptions =>
      List<PublicSmartPlaylistSubscription>.unmodifiable(_publicSubscriptions);

  void updateGatewayFactory(SharedSmartPlaylistGatewayFactory? factory) {
    if (identical(_gatewayFactory, factory)) {
      return;
    }
    _gatewayFactory = factory;
    notifyListeners();
  }

  Future<void> load() async {
    if (_loaded) {
      return;
    }
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_metadataKey);
      if (raw != null && raw.trim().isNotEmpty) {
        _loadMetadata(jsonDecode(raw));
      }
      _lastError = null;
    } on Object {
      _bindings.clear();
      _publicSubscriptions.clear();
      _lastError = 'Could not load shared smart-playlist settings.';
    } finally {
      _loaded = true;
      notifyListeners();
    }
  }

  SharedSmartPlaylistBinding? bindingForLocalSmartPlaylist(String id) {
    for (final binding in _bindings) {
      if (binding.localSmartPlaylistId == id) {
        return binding;
      }
    }
    return null;
  }

  PublicSmartPlaylistSubscription?
  publicSubscriptionForLocalSmartPlaylist(String id) {
    for (final subscription in _publicSubscriptions) {
      if (subscription.localSmartPlaylistId == id) {
        return subscription;
      }
    }
    return null;
  }

  Future<SharedSmartPlaylistBinding> host(
    LibraryStore library,
    CustomSmartPlaylist playlist,
  ) {
    return _runBusy(() async {
      _requireOnline(library);
      if (bindingForLocalSmartPlaylist(playlist.id) != null) {
        throw StateError('This smart playlist is already shared.');
      }
      final remote = await _requireGateway().createSharedSmartPlaylist(
        name: playlist.name,
        rule: _ruleJson(playlist),
      );
      final binding = _bindingFromRemote(remote, playlist.id);
      await _addBinding(binding);
      return binding;
    });
  }

  Future<SharedSmartPlaylistBinding> joinInvite(
    String inviteCode,
    LibraryStore library,
  ) {
    return _runBusy(() async {
      _requireOnline(library);
      final remote = await _requireGateway().joinSharedPlaylistInvite(inviteCode);
      if (remote.kind != SharedPlaylistKind.smart) {
        throw const FormatException('That invite is for a manual playlist.');
      }
      final existing = _bindings.where((item) => item.remoteId == remote.id);
      if (existing.isNotEmpty) {
        await _applyRemote(existing.first, remote, library);
        return bindingForLocalSmartPlaylist(
          existing.first.localSmartPlaylistId,
        )!;
      }
      final local = await _createLocal(remote, library);
      final binding = _bindingFromRemote(remote, local.id);
      await _addBinding(binding);
      return binding;
    });
  }

  Future<SharedSmartPlaylistBinding> refresh(
    SharedSmartPlaylistBinding binding,
    LibraryStore library,
  ) {
    return _runBusy(() async {
      _requireOnline(library);
      final remote = await _requireGateway().fetchSharedPlaylist(binding.remoteId);
      await _applyRemote(binding, remote, library);
      return bindingForLocalSmartPlaylist(binding.localSmartPlaylistId)!;
    });
  }

  Future<SharedSmartPlaylistBinding> publish(
    SharedSmartPlaylistBinding binding,
    LibraryStore library,
  ) {
    return _runBusy(() async {
      _requireOnline(library);
      if (!binding.canEdit) {
        throw StateError('This shared smart playlist is view-only.');
      }
      final local = library.customSmartPlaylistById(binding.localSmartPlaylistId);
      if (local == null) {
        throw StateError('The linked local smart playlist no longer exists.');
      }
      final remote = await _requireGateway().updateSharedSmartPlaylist(
        playlistId: binding.remoteId,
        baseRevision: binding.revision,
        name: local.name,
        rule: _ruleJson(local),
      );
      final updated = _bindingFromRemote(remote, local.id);
      await _replaceBinding(updated);
      return updated;
    });
  }

  Future<SharedPlaylistInvitation> createInvite(
    SharedSmartPlaylistBinding binding,
    SharedPlaylistAccessRole role,
  ) {
    return _runBusy(() async {
      if (!binding.isOwner) {
        throw StateError('Only the shared smart playlist owner can create invites.');
      }
      return _requireGateway().issueSharedPlaylistInvite(
        playlistId: binding.remoteId,
        role: role,
      );
    });
  }

  Future<SharedSmartPlaylistPublicLink> createPublicLink(
    SharedSmartPlaylistBinding binding,
    LibraryStore library,
  ) {
    return _runBusy(() async {
      _requireOnline(library);
      if (!binding.isOwner) {
        throw StateError('Only the shared smart playlist owner can create public links.');
      }
      final link = await _requireGateway().issueSharedSmartPlaylistPublicLink(
        playlistId: binding.remoteId,
        baseRevision: binding.revision,
      );
      await _replaceBinding(binding.withRevision(link.revision));
      return link;
    });
  }

  Future<void> revokePublicLink(
    SharedSmartPlaylistBinding binding,
    LibraryStore library,
  ) {
    return _runBusy(() async {
      _requireOnline(library);
      if (!binding.isOwner) {
        throw StateError('Only the shared smart playlist owner can revoke public links.');
      }
      final revision = await _requireGateway().revokeSharedSmartPlaylistPublicLink(
        playlistId: binding.remoteId,
        baseRevision: binding.revision,
      );
      await _replaceBinding(binding.withRevision(revision));
    });
  }

  /// Imports the rules behind a public link as an independent local playlist.
  ///
  /// The public capability is intentionally not saved. It cannot be refreshed
  /// silently and importing it never creates a private collaboration binding.
  Future<CustomSmartPlaylist> importPublicLink(
    String link,
    LibraryStore library, {
    LibrarySyncHttpExecutor? httpExecutor,
  }) {
    return _runBusy(() async {
      _requireOnline(library);
      final remote = await fetchPublicSharedSmartPlaylist(
        link,
        httpExecutor: httpExecutor,
      );
      return _createLocalDocument(remote.playlist, library);
    });
  }

  /// Stores a public link in the platform credential vault for user-triggered
  /// refreshes. No background fetches are scheduled.
  Future<PublicSmartPlaylistSubscription> subscribeToPublicLink(
    String link,
    LibraryStore library, {
    LibrarySyncHttpExecutor? httpExecutor,
  }) {
    return _runBusy(() async {
      _requireOnline(library);
      final remote = await fetchPublicSharedSmartPlaylist(
        link,
        httpExecutor: httpExecutor,
      );
      final id = _publicSubscriptionId(remote.uri);
      final existing = _publicSubscriptionById(id);
      if (existing != null) {
        if (remote.revision < existing.revision) {
          throw const FormatException('Public smart-playlist revision is invalid.');
        }
        await _applyPublicDocument(existing, remote.playlist, library);
        final updated = existing.withRevision(remote.revision);
        if (updated.revision != existing.revision) {
          await _replacePublicSubscription(updated);
        }
        return publicSubscriptionForLocalSmartPlaylist(
          existing.localSmartPlaylistId,
        )!;
      }
      if (_publicSubscriptionForRemoteId(remote.playlistId) != null) {
        throw StateError('This public smart playlist is already subscribed.');
      }
      final local = await _createLocalDocument(remote.playlist, library);
      final subscription = PublicSmartPlaylistSubscription(
        id: id,
        remoteId: remote.playlistId,
        localSmartPlaylistId: local.id,
        revision: remote.revision,
      );
      await _publicLinkVault.write(_publicLinkCredentialKey(id), remote.uri.toString());
      try {
        await _addPublicSubscription(subscription);
      } on Object {
        await _publicLinkVault.delete(_publicLinkCredentialKey(id));
        rethrow;
      }
      return subscription;
    });
  }

  Future<PublicSmartPlaylistSubscription> refreshPublicSubscription(
    PublicSmartPlaylistSubscription subscription,
    LibraryStore library, {
    LibrarySyncHttpExecutor? httpExecutor,
  }) {
    return _runBusy(() async {
      _requireOnline(library);
      final link = await _publicLinkVault.read(
        _publicLinkCredentialKey(subscription.id),
      );
      if (link == null || link.trim().isEmpty) {
        throw StateError('This public smart-playlist link is no longer available.');
      }
      final remote = await fetchPublicSharedSmartPlaylist(
        link,
        httpExecutor: httpExecutor,
      );
      if (remote.playlistId != subscription.remoteId) {
        throw const FormatException('Public smart-playlist link does not match.');
      }
      if (remote.revision < subscription.revision) {
        throw const FormatException('Public smart-playlist revision is invalid.');
      }
      await _applyPublicDocument(subscription, remote.playlist, library);
      final updated = subscription.withRevision(remote.revision);
      if (updated.revision != subscription.revision) {
        await _replacePublicSubscription(updated);
      }
      return publicSubscriptionForLocalSmartPlaylist(
        subscription.localSmartPlaylistId,
      )!;
    });
  }

  Future<void> unsubscribeFromPublicLink(
    PublicSmartPlaylistSubscription subscription,
  ) {
    return _runBusy(() async {
      await _publicLinkVault.delete(_publicLinkCredentialKey(subscription.id));
      await _removePublicSubscription(subscription);
    });
  }

  Future<void> unlink(SharedSmartPlaylistBinding binding) =>
      _runBusy(() => _removeBinding(binding));

  Future<void> deleteHosted(
    SharedSmartPlaylistBinding binding,
    LibraryStore library,
  ) {
    return _runBusy(() async {
      _requireOnline(library);
      if (!binding.isOwner) {
        throw StateError('Only the shared smart playlist owner can delete it.');
      }
      await _requireGateway().deleteSharedPlaylist(
        playlistId: binding.remoteId,
        baseRevision: binding.revision,
      );
      await _removeBinding(binding);
    });
  }

  Future<void> _applyRemote(
    SharedSmartPlaylistBinding binding,
    SharedPlaylistRemote remote,
    LibraryStore library,
  ) async {
    if (remote.kind != SharedPlaylistKind.smart) {
      throw const FormatException('Shared playlist is not a smart playlist.');
    }
    final local = library.customSmartPlaylistById(binding.localSmartPlaylistId);
    if (local == null) {
      throw StateError('The linked local smart playlist no longer exists.');
    }
    final values = _valuesFromRemote(remote);
    await library.updateCustomSmartPlaylist(
      local.id,
      name: remote.name,
      query: values.query,
      sourceId: values.sourceId,
      artist: values.artist,
      album: values.album,
      genre: values.genre,
      minimumDurationSeconds: values.minimumDurationSeconds,
      maximumDurationSeconds: values.maximumDurationSeconds,
      favoritesOnly: values.favoritesOnly,
      minimumPlayCount: values.minimumPlayCount,
      minimumDaysSinceLastPlayed: values.minimumDaysSinceLastPlayed,
      matchMode: values.matchMode,
      ruleGroups: values.ruleGroups,
      sortMode: values.sortMode,
      limit: values.limit,
    );
    await _replaceBinding(_bindingFromRemote(remote, local.id));
  }

  Future<void> _applyPublicDocument(
    PublicSmartPlaylistSubscription subscription,
    SharedSmartPlaylistDocument document,
    LibraryStore library,
  ) async {
    final local = library.customSmartPlaylistById(subscription.localSmartPlaylistId);
    if (local == null) {
      throw StateError('The linked local smart playlist no longer exists.');
    }
    final values = _valuesFromSmartDocument(document);
    await library.updateCustomSmartPlaylist(
      local.id,
      name: document.name,
      query: values.query,
      sourceId: values.sourceId,
      artist: values.artist,
      album: values.album,
      genre: values.genre,
      minimumDurationSeconds: values.minimumDurationSeconds,
      maximumDurationSeconds: values.maximumDurationSeconds,
      favoritesOnly: values.favoritesOnly,
      minimumPlayCount: values.minimumPlayCount,
      minimumDaysSinceLastPlayed: values.minimumDaysSinceLastPlayed,
      matchMode: values.matchMode,
      ruleGroups: values.ruleGroups,
      sortMode: values.sortMode,
      limit: values.limit,
    );
  }

  Future<CustomSmartPlaylist> _createLocal(
    SharedPlaylistRemote remote,
    LibraryStore library,
  ) async {
    final smart = remote.smartPlaylist;
    if (remote.kind != SharedPlaylistKind.smart || smart == null) {
      throw const FormatException('Shared playlist is not a smart playlist.');
    }
    return _createLocalDocument(smart, library);
  }

  Future<CustomSmartPlaylist> _createLocalDocument(
    SharedSmartPlaylistDocument smart,
    LibraryStore library,
  ) async {
    final values = _valuesFromSmartDocument(smart);
    return library.createCustomSmartPlaylist(
      name: smart.name,
      query: values.query,
      sourceId: values.sourceId,
      artist: values.artist,
      album: values.album,
      genre: values.genre,
      minimumDurationSeconds: values.minimumDurationSeconds,
      maximumDurationSeconds: values.maximumDurationSeconds,
      favoritesOnly: values.favoritesOnly,
      minimumPlayCount: values.minimumPlayCount,
      minimumDaysSinceLastPlayed: values.minimumDaysSinceLastPlayed,
      matchMode: values.matchMode,
      ruleGroups: values.ruleGroups,
      sortMode: values.sortMode,
      limit: values.limit,
    );
  }

  SharedSmartPlaylistBinding _bindingFromRemote(
    SharedPlaylistRemote remote,
    String localId,
  ) {
    if (remote.kind != SharedPlaylistKind.smart) {
      throw const FormatException('Shared playlist is not a smart playlist.');
    }
    return SharedSmartPlaylistBinding(
      remoteId: remote.id,
      localSmartPlaylistId: localId,
      revision: remote.revision,
      role: remote.role,
      updatedAt: remote.updatedAt,
      updatedByDevice: remote.updatedByDevice,
    );
  }

  SharedSmartPlaylistGateway _requireGateway() {
    final factory = _gatewayFactory;
    if (factory == null) {
      throw StateError('Configure a library sync server first.');
    }
    return factory();
  }

  void _requireOnline(LibraryStore library) {
    if (library.offlineModeEnabled) {
      throw StateError('Turn off offline mode before sharing smart playlists.');
    }
  }

  Future<void> _addBinding(SharedSmartPlaylistBinding binding) async {
    _bindings.add(binding);
    await _save();
    notifyListeners();
  }

  Future<void> _replaceBinding(SharedSmartPlaylistBinding binding) async {
    final index = _bindings.indexWhere((item) => item.remoteId == binding.remoteId);
    if (index < 0) {
      throw StateError('Shared smart playlist binding no longer exists.');
    }
    _bindings[index] = binding;
    await _save();
    notifyListeners();
  }

  Future<void> _removeBinding(SharedSmartPlaylistBinding binding) async {
    _bindings.removeWhere((item) => item.remoteId == binding.remoteId);
    await _save();
    notifyListeners();
  }

  Future<void> _addPublicSubscription(
    PublicSmartPlaylistSubscription subscription,
  ) async {
    _publicSubscriptions.add(subscription);
    await _save();
    notifyListeners();
  }

  Future<void> _replacePublicSubscription(
    PublicSmartPlaylistSubscription subscription,
  ) async {
    final index = _publicSubscriptions.indexWhere(
      (item) => item.id == subscription.id,
    );
    if (index < 0) {
      throw StateError('Public smart-playlist subscription no longer exists.');
    }
    _publicSubscriptions[index] = subscription;
    await _save();
    notifyListeners();
  }

  Future<void> _removePublicSubscription(
    PublicSmartPlaylistSubscription subscription,
  ) async {
    _publicSubscriptions.removeWhere((item) => item.id == subscription.id);
    await _save();
    notifyListeners();
  }

  Future<void> _save() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _metadataKey,
      jsonEncode(<String, Object?>{
        'version': 2,
        'privateBindings': _bindings
            .map((binding) => binding.toJson())
            .toList(growable: false),
        'publicSubscriptions': _publicSubscriptions
            .map((subscription) => subscription.toJson())
            .toList(growable: false),
      }),
    );
  }

  void _loadMetadata(Object? value) {
    final privateBindings = <Object?>[];
    final publicSubscriptions = <Object?>[];
    if (value is List) {
      privateBindings.addAll(value);
    } else if (value is Map) {
      final metadata = Map<String, Object?>.from(value);
      if (metadata['version'] != 2 ||
          metadata['privateBindings'] is! List ||
          metadata['publicSubscriptions'] is! List) {
        throw const FormatException('Shared smart playlist metadata is invalid.');
      }
      privateBindings.addAll(metadata['privateBindings'] as List);
      publicSubscriptions.addAll(metadata['publicSubscriptions'] as List);
    } else {
      throw const FormatException('Shared smart playlist metadata is invalid.');
    }
    final remoteIds = <String>{};
    final localIds = <String>{};
    for (final value in privateBindings.whereType<Map>()) {
      final binding = SharedSmartPlaylistBinding.tryFromJson(
        Map<String, Object?>.from(value),
      );
      if (binding != null &&
          remoteIds.add(binding.remoteId) &&
          localIds.add(binding.localSmartPlaylistId)) {
        _bindings.add(binding);
      }
    }
    final subscriptionIds = <String>{};
    final subscriptionRemoteIds = <String>{};
    for (final value in publicSubscriptions.whereType<Map>()) {
      final subscription = PublicSmartPlaylistSubscription.tryFromJson(
        Map<String, Object?>.from(value),
      );
      if (subscription != null &&
          subscriptionIds.add(subscription.id) &&
          subscriptionRemoteIds.add(subscription.remoteId) &&
          localIds.add(subscription.localSmartPlaylistId)) {
        _publicSubscriptions.add(subscription);
      }
    }
  }

  PublicSmartPlaylistSubscription? _publicSubscriptionById(String id) {
    for (final subscription in _publicSubscriptions) {
      if (subscription.id == id) {
        return subscription;
      }
    }
    return null;
  }

  PublicSmartPlaylistSubscription? _publicSubscriptionForRemoteId(String id) {
    for (final subscription in _publicSubscriptions) {
      if (subscription.remoteId == id) {
        return subscription;
      }
    }
    return null;
  }

  String _publicLinkCredentialKey(String id) =>
      '$_publicLinkCredentialPrefix$id';

  Future<T> _runBusy<T>(Future<T> Function() action) async {
    if (_busy) {
      throw StateError('A shared smart playlist operation is already running.');
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

Map<String, Object?> _ruleJson(CustomSmartPlaylist playlist) => <String, Object?>{
  'query': playlist.query,
  'sourceId': playlist.sourceId,
  'artist': playlist.artist,
  'album': playlist.album,
  'genre': playlist.genre,
  'minimumDurationSeconds': playlist.minimumDurationSeconds,
  'maximumDurationSeconds': playlist.maximumDurationSeconds,
  'favoritesOnly': playlist.favoritesOnly,
  'minimumPlayCount': playlist.minimumPlayCount,
  'minimumDaysSinceLastPlayed': playlist.minimumDaysSinceLastPlayed,
  'matchMode': playlist.matchMode.name,
  'ruleGroups': playlist.ruleGroups.map((group) => group.toJson()).toList(),
  'sortMode': playlist.sortMode.name,
  'limit': playlist.limit,
};

CustomSmartPlaylist _valuesFromRemote(SharedPlaylistRemote remote) {
  final smart = remote.smartPlaylist;
  if (remote.kind != SharedPlaylistKind.smart || smart == null) {
    throw const FormatException('Shared playlist is not a smart playlist.');
  }
  return _valuesFromSmartDocument(smart);
}

CustomSmartPlaylist _valuesFromSmartDocument(SharedSmartPlaylistDocument smart) {
  return CustomSmartPlaylist.fromJson(<String, Object?>{
    'id': 'shared-smart-playlist',
    'name': smart.name,
    ...smart.rule,
  });
}

SharedPlaylistAccessRole? _roleFromJson(Object? value) => switch (value) {
  'owner' => SharedPlaylistAccessRole.owner,
  'editor' => SharedPlaylistAccessRole.editor,
  'viewer' => SharedPlaylistAccessRole.viewer,
  _ => null,
};

String? _optionalText(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

DateTime? _optionalDate(Object? value) {
  final text = _optionalText(value);
  return text == null ? null : DateTime.tryParse(text)?.toUtc();
}

bool _isIdentifier(String value) =>
    RegExp(r'^[A-Za-z0-9_-]{24}$').hasMatch(value);

String _publicSubscriptionId(Uri uri) =>
    sha256.convert(utf8.encode(uri.toString())).toString();

bool _isPublicSubscriptionId(String value) =>
    RegExp(r'^[a-f0-9]{64}$').hasMatch(value);
