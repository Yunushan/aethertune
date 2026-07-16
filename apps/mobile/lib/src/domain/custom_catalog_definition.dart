import 'dart:math';

const _maximumCustomCatalogNameLength = 80;
const _maximumCustomCatalogDescriptionLength = 280;
const _maximumCustomCatalogDomains = 12;

/// A user-approved, declarative JSON music catalog.
///
/// This is deliberately data-only: it cannot execute provider code, attach
/// credentials, or make requests outside its declared hosts.
final class CustomCatalogDefinition {
  CustomCatalogDefinition({
    required String id,
    required String name,
    required Uri catalogUri,
    required Iterable<String> mediaDomains,
    required this.allowInsecureHttp,
    String description = '',
  })  : id = _normalizeId(id),
        name = _normalizeName(name),
        catalogUri = _normalizeCatalogUri(
          catalogUri,
          allowInsecureHttp: allowInsecureHttp,
        ),
        mediaDomains = _normalizeDomains(mediaDomains, catalogUri.host),
        description = _normalizeDescription(description);

  factory CustomCatalogDefinition.create({
    required String name,
    required String catalogUrl,
    required Iterable<String> mediaDomains,
    required bool allowInsecureHttp,
    String description = '',
    String? id,
  }) {
    return CustomCatalogDefinition(
      id: id ?? _newCustomCatalogId(),
      name: name,
      catalogUri: Uri.parse(catalogUrl.trim()),
      mediaDomains: mediaDomains,
      allowInsecureHttp: allowInsecureHttp,
      description: description,
    );
  }

  final String id;
  final String name;
  final Uri catalogUri;
  final List<String> mediaDomains;
  final bool allowInsecureHttp;
  final String description;

  String get providerId => 'custom-catalog-$id';

  List<String> get declaredNetworkDomains => <String>[
    catalogUri.host,
    ...mediaDomains.where((domain) => domain != catalogUri.host),
  ];

  bool allowsRemoteUri(Uri uri) {
    if (!_isSupportedRemoteUri(uri, allowInsecureHttp: allowInsecureHttp)) {
      return false;
    }
    return declaredNetworkDomains.contains(uri.host.toLowerCase());
  }

  CustomCatalogDefinition copyWith({
    String? name,
    Uri? catalogUri,
    Iterable<String>? mediaDomains,
    bool? allowInsecureHttp,
    String? description,
  }) {
    return CustomCatalogDefinition(
      id: id,
      name: name ?? this.name,
      catalogUri: catalogUri ?? this.catalogUri,
      mediaDomains: mediaDomains ?? this.mediaDomains,
      allowInsecureHttp: allowInsecureHttp ?? this.allowInsecureHttp,
      description: description ?? this.description,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'version': 1,
      'id': id,
      'name': name,
      'catalogUrl': catalogUri.toString(),
      'mediaDomains': mediaDomains,
      'allowInsecureHttp': allowInsecureHttp,
      'description': description,
    };
  }

  factory CustomCatalogDefinition.fromJson(Map<String, Object?> json) {
    if (json['version'] != 1) {
      throw const FormatException('Unsupported custom catalog version.');
    }
    final catalogUrl = json['catalogUrl'];
    final rawDomains = json['mediaDomains'];
    if (catalogUrl is! String || rawDomains is! List) {
      throw const FormatException('Custom catalog is missing required fields.');
    }
    return CustomCatalogDefinition.create(
      id: json['id'] as String?,
      name: json['name'] as String? ?? '',
      catalogUrl: catalogUrl,
      mediaDomains: rawDomains.whereType<String>(),
      allowInsecureHttp: json['allowInsecureHttp'] as bool? ?? false,
      description: json['description'] as String? ?? '',
    );
  }
}

String _newCustomCatalogId() {
  final random = Random.secure().nextInt(1 << 32).toRadixString(16);
  return '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-$random';
}

String _normalizeId(String value) {
  final normalized = value.trim().toLowerCase();
  if (!RegExp(r'^[a-z0-9][a-z0-9-]{5,79}$').hasMatch(normalized)) {
    throw const FormatException('Custom catalog ID is invalid.');
  }
  return normalized;
}

String _normalizeName(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty || normalized.length > _maximumCustomCatalogNameLength) {
    throw const FormatException('Catalog name must be 1-80 characters.');
  }
  return normalized;
}

String _normalizeDescription(String value) {
  final normalized = value.trim();
  if (normalized.length > _maximumCustomCatalogDescriptionLength) {
    throw const FormatException('Catalog description is too long.');
  }
  return normalized;
}

Uri _normalizeCatalogUri(Uri value, {required bool allowInsecureHttp}) {
  if (!_isSupportedRemoteUri(value, allowInsecureHttp: allowInsecureHttp)) {
    throw const FormatException(
      'Catalog URL must be HTTPS, or HTTP with explicit consent.',
    );
  }
  return value.replace(fragment: '');
}

bool _isSupportedRemoteUri(
  Uri uri, {
  required bool allowInsecureHttp,
}) {
  final scheme = uri.scheme.toLowerCase();
  return uri.hasAuthority &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty &&
      !_containsCredentialQuery(uri) &&
      (scheme == 'https' || (scheme == 'http' && allowInsecureHttp));
}

bool _containsCredentialQuery(Uri uri) {
  for (final key in uri.queryParameters.keys) {
    if (RegExp(
      r'^(?:api_?key|access_?token|auth(?:entication)?|credential|password|secret|token)$',
      caseSensitive: false,
    ).hasMatch(key)) {
      return true;
    }
  }
  return false;
}

List<String> _normalizeDomains(Iterable<String> values, String catalogHost) {
  final domains = <String>{};
  for (final value in values) {
    final domain = value.trim().toLowerCase();
    if (domain.isEmpty) {
      continue;
    }
    if (!RegExp(r'^[a-z0-9.-]+$').hasMatch(domain) ||
        domain.startsWith('.') ||
        domain.endsWith('.')) {
      throw FormatException('Invalid media domain: $value');
    }
    domains.add(domain);
  }
  domains.remove(catalogHost.toLowerCase());
  if (domains.length > _maximumCustomCatalogDomains) {
    throw const FormatException('A catalog can declare at most 12 media domains.');
  }
  return List<String>.unmodifiable(domains.toList()..sort());
}
