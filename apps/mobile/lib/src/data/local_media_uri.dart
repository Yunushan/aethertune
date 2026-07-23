/// Converts a persisted local-media locator into the URI accepted by the
/// playback backend. Filesystem paths stay file URIs; Android SAF locators
/// retain their granted content URI instead of being reinterpreted as paths.
Uri localMediaUri(String locator) {
  final trimmed = locator.trim();
  final parsed = Uri.tryParse(trimmed);
  if (parsed != null &&
      parsed.scheme.toLowerCase() == 'content' &&
      parsed.host.isNotEmpty) {
    return parsed;
  }
  return Uri.file(locator);
}

bool isContentMediaUri(String locator) {
  final parsed = Uri.tryParse(locator.trim());
  return parsed != null &&
      parsed.scheme.toLowerCase() == 'content' &&
      parsed.host.isNotEmpty;
}
