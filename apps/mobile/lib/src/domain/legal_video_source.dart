/// Accepts only local files or explicit HTTPS video URLs.
///
/// This keeps the video renderer separate from provider adapters and rejects
/// embedded credentials, data URLs, and unencrypted network media.
Uri? parseLegalVideoUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      uri.scheme.toLowerCase() != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  return uri.replace(fragment: '');
}

Uri? localVideoUri(String path) {
  final normalized = path.trim();
  return normalized.isEmpty ? null : Uri.file(normalized);
}
