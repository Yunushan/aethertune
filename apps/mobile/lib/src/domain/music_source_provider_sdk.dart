import 'music_source_provider.dart';

/// The semantic version of AetherTune's public provider SDK.
const aetherTuneProviderSdkVersion = '1.0.0';

/// A compatibility report produced before registering a provider adapter.
final class MusicSourceProviderContractReport {
  const MusicSourceProviderContractReport(this.issues);

  final List<MusicSourceProviderContractIssue> issues;

  bool get isCompliant => issues.isEmpty;
}

/// A concrete violation of the versioned provider SDK contract.
final class MusicSourceProviderContractIssue {
  const MusicSourceProviderContractIssue({
    required this.code,
    required this.message,
  });

  final MusicSourceProviderContractIssueCode code;
  final String message;
}

enum MusicSourceProviderContractIssueCode {
  missingId,
  invalidId,
  missingName,
  missingDescription,
  missingCapabilities,
  invalidNetworkDomain,
  duplicateNetworkDomain,
  missingNetworkDisclosure,
  undisclosedNetworkData,
  missingAuthenticationCapability,
  missingMediaCacheCapability,
  missingDownloadCapability,
  undisclosedMediaCache,
  undisclosedDownloads,
  missingSuggestionExtension,
}

/// Validates the stable v1 provider requirements without making network calls.
///
/// Provider IDs use URL-safe ASCII letters, digits, hyphens, and underscores.
/// This keeps persisted IDs portable across library snapshots, deep links, and
/// platform filesystems while allowing stable URL-safe Base64 account IDs.
MusicSourceProviderContractReport validateMusicSourceProviderContract(
  MusicSourceProvider provider,
) {
  final issues = <MusicSourceProviderContractIssue>[];
  final id = provider.id.trim();
  if (id.isEmpty) {
    issues.add(
      const MusicSourceProviderContractIssue(
        code: MusicSourceProviderContractIssueCode.missingId,
        message: 'Provider IDs must not be empty.',
      ),
    );
  } else if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]*$').hasMatch(id)) {
    issues.add(
      const MusicSourceProviderContractIssue(
        code: MusicSourceProviderContractIssueCode.invalidId,
        message:
            'Provider IDs must use URL-safe letters, digits, hyphens, or underscores.',
      ),
    );
  }
  if (provider.name.trim().isEmpty) {
    issues.add(
      const MusicSourceProviderContractIssue(
        code: MusicSourceProviderContractIssueCode.missingName,
        message: 'Provider names must not be empty.',
      ),
    );
  }
  if (provider.description.trim().isEmpty) {
    issues.add(
      const MusicSourceProviderContractIssue(
        code: MusicSourceProviderContractIssueCode.missingDescription,
        message: 'Provider descriptions must not be empty.',
      ),
    );
  }
  if (provider.capabilities.isEmpty) {
    issues.add(
      const MusicSourceProviderContractIssue(
        code: MusicSourceProviderContractIssueCode.missingCapabilities,
        message: 'Providers must declare at least one capability.',
      ),
    );
  }

  final disclosure = provider.disclosure;
  final domains = <String>{};
  for (final rawDomain in disclosure.networkDomains) {
    final domain = rawDomain.trim().toLowerCase();
    if (domain.isEmpty || domain.contains(RegExp(r'\s'))) {
      issues.add(
        const MusicSourceProviderContractIssue(
          code: MusicSourceProviderContractIssueCode.invalidNetworkDomain,
          message: 'Network domains must be non-empty host names without spaces.',
        ),
      );
    } else if (!domains.add(domain)) {
      issues.add(
        const MusicSourceProviderContractIssue(
          code: MusicSourceProviderContractIssueCode.duplicateNetworkDomain,
          message: 'Network domains must not be declared more than once.',
        ),
      );
    }
  }
  if (disclosure.usesNetwork && disclosure.dataSent.isEmpty) {
    issues.add(
      const MusicSourceProviderContractIssue(
        code: MusicSourceProviderContractIssueCode.missingNetworkDisclosure,
        message: 'Network providers must describe the data sent to each service.',
      ),
    );
  }
  if (!disclosure.usesNetwork && disclosure.dataSent.isNotEmpty) {
    issues.add(
      const MusicSourceProviderContractIssue(
        code: MusicSourceProviderContractIssueCode.undisclosedNetworkData,
        message: 'Providers that send data must declare their network domains.',
      ),
    );
  }
  if (disclosure.requiresUserCredentials &&
      !provider.capabilities.contains(MusicSourceCapability.authentication)) {
    issues.add(
      const MusicSourceProviderContractIssue(
        code: MusicSourceProviderContractIssueCode.missingAuthenticationCapability,
        message: 'Credentialed providers must declare Authentication.',
      ),
    );
  }
  if (disclosure.cachesMedia &&
      !provider.capabilities.contains(MusicSourceCapability.offlineCache)) {
    issues.add(
      const MusicSourceProviderContractIssue(
        code: MusicSourceProviderContractIssueCode.missingMediaCacheCapability,
        message: 'Media caching must be paired with the Offline cache capability.',
      ),
    );
  }
  if (disclosure.supportsDownloads &&
      !provider.capabilities.contains(MusicSourceCapability.downloads)) {
    issues.add(
      const MusicSourceProviderContractIssue(
        code: MusicSourceProviderContractIssueCode.missingDownloadCapability,
        message: 'Download support must be paired with the Download capability.',
      ),
    );
  }
  if (provider.capabilities.contains(MusicSourceCapability.offlineCache) &&
      !disclosure.cachesMedia) {
    issues.add(
      const MusicSourceProviderContractIssue(
        code: MusicSourceProviderContractIssueCode.undisclosedMediaCache,
        message: 'Offline cache capability requires a media-cache disclosure.',
      ),
    );
  }
  if (provider.capabilities.contains(MusicSourceCapability.downloads) &&
      !disclosure.supportsDownloads) {
    issues.add(
      const MusicSourceProviderContractIssue(
        code: MusicSourceProviderContractIssueCode.undisclosedDownloads,
        message: 'Download capability requires a download disclosure.',
      ),
    );
  }
  if (provider.capabilities.contains(
        MusicSourceCapability.searchSuggestions,
      ) &&
      provider is! MusicSourceSearchSuggestionProvider) {
    issues.add(
      const MusicSourceProviderContractIssue(
        code: MusicSourceProviderContractIssueCode.missingSuggestionExtension,
        message:
            'Search suggestions capability requires MusicSourceSearchSuggestionProvider.',
      ),
    );
  }

  return MusicSourceProviderContractReport(
    List<MusicSourceProviderContractIssue>.unmodifiable(issues),
  );
}
