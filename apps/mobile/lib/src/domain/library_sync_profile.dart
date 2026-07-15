class LibrarySyncProfile {
  const LibrarySyncProfile({
    required this.id,
    required this.managed,
    this.displayName,
    this.device,
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
    final displayName = _optionalProfileText(
      json['displayName'],
      fieldName: 'display name',
      maxLength: 80,
    );
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
    return LibrarySyncProfile(
      id: id,
      displayName: displayName,
      managed: managed,
      device: device,
    );
  }

  final String id;
  final String? displayName;
  final bool managed;
  final LibrarySyncProfileDevice? device;

  String get effectiveDisplayName => displayName ?? id;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'displayName': displayName,
    'managed': managed,
    'device': device?.toJson(),
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
