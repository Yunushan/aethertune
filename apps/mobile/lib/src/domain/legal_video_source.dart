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
  return uri.removeFragment();
}

Uri? localVideoUri(String path) {
  final normalized = path.trim();
  if (normalized.isEmpty) {
    return null;
  }
  final windowsPath = RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(normalized) ||
      normalized.startsWith(r'\\');
  return Uri.file(normalized, windows: windowsPath);
}
