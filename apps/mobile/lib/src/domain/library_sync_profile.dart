enum LibrarySyncProfileAvatarTone {
  azure,
  emerald,
  amber,
  rose,
  violet,
  slate;

  String get wireValue => name;

  static LibrarySyncProfileAvatarTone? fromJson(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is! String) {
      throw const FormatException('Library sync profile avatar tone is invalid.');
    }
    for (final tone in values) {
      if (tone.wireValue == value) {
        return tone;
      }
    }
    throw const FormatException('Library sync profile avatar tone is invalid.');
  }
}

class LibrarySyncProfile {
  const LibrarySyncProfile({
    required this.id,
    required this.managed,
    this.displayName,
    this.avatarTone,
    this.avatarToneSupported = false,
    this.publicProfileEnabled = false,
    this.publicProfileSupported = false,
    this.device,
    this.editable = false,
  });

  factory LibrarySyncProfile.fromServerJson(Map<String, Object?> json) {
    final rawAccount = json['account'];
    if (rawAccount is! Map) {
      throw const FormatException('Library sync profile account is missing.');
    }
    return LibrarySyncProfile.fromJson(<String, Object?>{
      ...Map<String, Object?>.from(rawAccount),
      'device': json['device'],
    });
  }

  factory LibrarySyncProfile.fromJson(Map<String, Object?> json) {
    final id = _requiredProfileText(
      json['id'],
      fieldName: 'account ID',
      maxLength: 64,
    );
    final managed = json['managed'];
    if (managed is! bool) {
      throw const FormatException(
        'Library sync profile management state is invalid.',
      );
    }
    final editable = json['editable'] ?? false;
    if (editable is! bool) {
      throw const FormatException(
        'Library sync profile edit capability is invalid.',
      );
    }
    final displayName = _optionalProfileText(
      json['displayName'],
      fieldName: 'display name',
      maxLength: 80,
    );
    final rawAvatarToneSupported = json['avatarToneSupported'];
    final avatarToneSupported = rawAvatarToneSupported ??
        json.containsKey('avatarTone');
    if (avatarToneSupported is! bool) {
      throw const FormatException(
        'Library sync profile avatar capability is invalid.',
      );
    }
    final avatarTone = LibrarySyncProfileAvatarTone.fromJson(
      json['avatarTone'],
    );
    if (!avatarToneSupported && avatarTone != null) {
      throw const FormatException(
        'Library sync profile avatar capability is inconsistent.',
      );
    }
    final rawPublicProfileSupported = json['publicProfileSupported'];
    final publicProfileSupported = rawPublicProfileSupported ??
        json.containsKey('publicProfileEnabled');
    if (publicProfileSupported is! bool) {
      throw const FormatException(
        'Library sync public profile capability is invalid.',
      );
    }
    final rawPublicProfileEnabled = json['publicProfileEnabled'] ?? false;
    if (rawPublicProfileEnabled is! bool) {
      throw const FormatException(
        'Library sync public profile visibility is invalid.',
      );
    }
    if (!publicProfileSupported && rawPublicProfileEnabled) {
      throw const FormatException(
        'Library sync public profile capability is inconsistent.',
      );
    }
    final rawDevice = json['device'];
    final device = rawDevice == null
        ? null
        : rawDevice is Map
        ? LibrarySyncProfileDevice.fromJson(
            Map<String, Object?>.from(rawDevice),
          )
        : throw const FormatException(
            'Library sync profile device is invalid.',
          );
    if (managed && device == null) {
      throw const FormatException(
        'Managed library sync profile device is missing.',
      );
    }
    if (!managed && avatarTone != null) {
      throw const FormatException(
        'Static library sync profiles cannot include an avatar.',
      );
    }
    if (editable && (!managed || device == null)) {
      throw const FormatException(
        'Editable library sync profile identity is invalid.',
      );
    }
    return LibrarySyncProfile(
      id: id,
      displayName: displayName,
      avatarTone: avatarTone,
      avatarToneSupported: avatarToneSupported,
      publicProfileEnabled: rawPublicProfileEnabled,
      publicProfileSupported: publicProfileSupported,
      managed: managed,
      device: device,
      editable: editable,
    );
  }

  final String id;
  final String? displayName;
  final LibrarySyncProfileAvatarTone? avatarTone;
  final bool avatarToneSupported;
  final bool publicProfileEnabled;
  final bool publicProfileSupported;
  final bool managed;
  final LibrarySyncProfileDevice? device;
  final bool editable;

  String get effectiveDisplayName => displayName ?? id;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'displayName': displayName,
    if (avatarToneSupported) 'avatarTone': avatarTone?.wireValue,
    'avatarToneSupported': avatarToneSupported,
    if (publicProfileSupported) 'publicProfileEnabled': publicProfileEnabled,
    'publicProfileSupported': publicProfileSupported,
    'managed': managed,
    'device': device?.toJson(),
    'editable': editable,
  };
}

class LibrarySyncProfileDevice {
  const LibrarySyncProfileDevice({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  factory LibrarySyncProfileDevice.fromJson(Map<String, Object?> json) {
    final rawCreatedAt = json['createdAt'];
    final createdAt = rawCreatedAt is String
        ? DateTime.tryParse(rawCreatedAt)
        : null;
    if (createdAt == null) {
      throw const FormatException(
        'Library sync profile device creation time is invalid.',
      );
    }
    return LibrarySyncProfileDevice(
      id: _requiredProfileText(
        json['id'],
        fieldName: 'device token ID',
        maxLength: 128,
      ),
      name: _requiredProfileText(
        json['deviceName'],
        fieldName: 'device name',
        maxLength: 80,
      ),
      createdAt: createdAt.toUtc(),
    );
  }

  final String id;
  final String name;
  final DateTime createdAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'deviceName': name,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };
}

String normalizeLibrarySyncProfileDisplayName(String value) {
  return _requiredProfileText(value, fieldName: 'display name', maxLength: 80);
}

String normalizeLibrarySyncProfileDeviceName(String value) {
  return _requiredProfileText(value, fieldName: 'device name', maxLength: 80);
}

String _requiredProfileText(
  Object? value, {
  required String fieldName,
  required int maxLength,
}) {
  final result = _optionalProfileText(
    value,
    fieldName: fieldName,
    maxLength: maxLength,
  );
  if (result == null) {
    throw FormatException('Library sync profile $fieldName is missing.');
  }
  return result;
}

String? _optionalProfileText(
  Object? value, {
  required String fieldName,
  required int maxLength,
}) {
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw FormatException('Library sync profile $fieldName is invalid.');
  }
  final normalized = value.trim();
  if (normalized.isEmpty ||
      normalized.length > maxLength ||
      normalized.runes.any((rune) => rune < 0x20 || rune == 0x7f)) {
    throw FormatException('Library sync profile $fieldName is invalid.');
  }
  return normalized;
}
