import 'track.dart';

enum SelfHostedProviderKind { jellyfin, subsonic }

extension SelfHostedProviderKindDetails on SelfHostedProviderKind {
  String get label {
    switch (this) {
      case SelfHostedProviderKind.jellyfin:
        return 'Jellyfin';
      case SelfHostedProviderKind.subsonic:
        return 'Navidrome / Subsonic';
    }
  }

  String get identityLabel {
    switch (this) {
      case SelfHostedProviderKind.jellyfin:
        return 'User ID';
      case SelfHostedProviderKind.subsonic:
        return 'Username';
    }
  }

  String get secretLabel {
    switch (this) {
      case SelfHostedProviderKind.jellyfin:
        return 'API key';
      case SelfHostedProviderKind.subsonic:
        return 'Password';
    }
  }
}

final class SelfHostedProviderAccount {
  const SelfHostedProviderAccount({
    required this.id,
    required this.kind,
    required this.name,
    required this.baseUri,
    required this.identity,
    this.allowInsecureHttp = false,
  });

  final String id;
  final SelfHostedProviderKind kind;
  final String name;
  final Uri baseUri;
  final String identity;
  final bool allowInsecureHttp;

  String get providerId => 'self-hosted-${kind.name}-$id';
  bool get usesSecureTransport => baseUri.scheme.toLowerCase() == 'https';

  SelfHostedProviderAccount copyWith({
    String? id,
    SelfHostedProviderKind? kind,
    String? name,
    Uri? baseUri,
    String? identity,
    bool? allowInsecureHttp,
  }) {
    return SelfHostedProviderAccount(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      name: name ?? this.name,
      baseUri: baseUri ?? this.baseUri,
      identity: identity ?? this.identity,
      allowInsecureHttp: allowInsecureHttp ?? this.allowInsecureHttp,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'kind': kind.name,
      'name': name,
      'baseUrl': baseUri.toString(),
      'identity': identity,
      'allowInsecureHttp': allowInsecureHttp,
    };
  }

  factory SelfHostedProviderAccount.fromJson(Map<String, Object?> json) {
    final kindName = json['kind'] as String? ?? '';
    final kind = SelfHostedProviderKind.values.where(
      (candidate) => candidate.name == kindName,
    );
    if (kind.isEmpty) {
      throw FormatException('Unknown self-hosted provider kind: $kindName');
    }

    return validateSelfHostedProviderAccount(
      SelfHostedProviderAccount(
        id: json['id'] as String? ?? '',
        kind: kind.first,
        name: json['name'] as String? ?? '',
        baseUri: Uri.parse(json['baseUrl'] as String? ?? ''),
        identity: json['identity'] as String? ?? '',
        allowInsecureHttp: json['allowInsecureHttp'] as bool? ?? false,
      ),
    );
  }
}

SelfHostedProviderAccount createSelfHostedProviderAccount({
  required SelfHostedProviderKind kind,
  required String name,
  required String baseUrl,
  required String identity,
  required bool allowInsecureHttp,
}) {
  final normalizedUri = normalizeSelfHostedBaseUri(baseUrl);
  final normalizedIdentity = identity.trim();
  final id = Track.stableLocalId(
    '${kind.name}|$normalizedUri|$normalizedIdentity',
  );
  return validateSelfHostedProviderAccount(
    SelfHostedProviderAccount(
      id: id,
      kind: kind,
      name: name.trim().isEmpty ? kind.label : name.trim(),
      baseUri: normalizedUri,
      identity: normalizedIdentity,
      allowInsecureHttp: allowInsecureHttp,
    ),
  );
}

SelfHostedProviderAccount validateSelfHostedProviderAccount(
  SelfHostedProviderAccount account,
) {
  if (account.id.trim().isEmpty) {
    throw const FormatException('Provider account ID is required.');
  }
  if (account.identity.trim().isEmpty) {
    throw FormatException('${account.kind.identityLabel} is required.');
  }
  final normalizedUri = normalizeSelfHostedBaseUri(account.baseUri.toString());
  if (normalizedUri.scheme == 'http' && !account.allowInsecureHttp) {
    throw const FormatException(
      'HTTP sends provider credentials without TLS. Confirm insecure HTTP to continue.',
    );
  }
  return account.copyWith(
    name: account.name.trim().isEmpty ? account.kind.label : account.name.trim(),
    baseUri: normalizedUri,
    identity: account.identity.trim(),
  );
}

Uri normalizeSelfHostedBaseUri(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      !uri.hasScheme ||
      !uri.hasAuthority ||
      uri.host.trim().isEmpty ||
      (uri.scheme.toLowerCase() != 'https' &&
          uri.scheme.toLowerCase() != 'http')) {
    throw const FormatException(
      'Server URL must be a complete http or https URL.',
    );
  }
  if (uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
    throw const FormatException(
      'Server URL cannot contain credentials, query parameters, or a fragment.',
    );
  }

  var path = uri.path;
  while (path.length > 1 && path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  return uri.replace(
    scheme: uri.scheme.toLowerCase(),
    host: uri.host.toLowerCase(),
    path: path == '/' ? '' : path,
  );
}
